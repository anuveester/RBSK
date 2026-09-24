import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/auth/credential_hasher.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:referredline/data/repositories/drift_user_repository.dart';
import 'package:referredline/data/repositories/local_auth_repository.dart';

import '../../../support/in_memory_secure_key_store.dart';
import '../test_database.dart';

// Synthetic test PIN only.
const _pin = '604215';

class _Capture implements SecurityEventSink {
  final events = <SecurityEvent>[];

  @override
  Future<void> record(SecurityEvent event) async => events.add(event);
}

void main() {
  test('the approved parameters are in force: PBKDF2-HMAC-SHA256, 210,000 '
      'iterations, 16-byte salt, 32-byte key', () {
    const current = CredentialKdfPolicy.current;
    expect(CredentialKdfPolicy.algorithmTag, 'pbkdf2-hmac-sha256');
    expect(current.iterations, 210000);
    expect(current.saltLengthBytes, 16);
    expect(current.derivedKeyLengthBytes, 32);

    final parts = deriveCredentialVerifier(_pin).split(r'$');
    expect(parts[0], 'pbkdf2-hmac-sha256');
    expect(parts[1], '210000');
  });

  test('a verifier records its own parameters, and one made with weaker '
      'parameters is detected as outdated (never a stronger one)', () {
    const older = CredentialKdfPolicy(iterations: 10000);
    const future = CredentialKdfPolicy(iterations: 600000);
    final oldVerifier = deriveCredentialVerifier(_pin, policy: older);

    expect(oldVerifier.split(r'$')[1], '10000');
    expect(verifyCredential(_pin, oldVerifier), isTrue);
    expect(verifierNeedsRehash(oldVerifier), isTrue);
    expect(verifierNeedsRehash(oldVerifier, policy: older), isFalse);

    final current = deriveCredentialVerifier(_pin);
    expect(verifierNeedsRehash(current), isFalse);
    expect(verifierNeedsRehash(current, policy: future), isTrue);
    expect(
      verifierNeedsRehash(current, policy: older),
      isFalse,
      reason: 'no downgrade',
    );
  });

  test('verifiers outside the accepted bounds fail closed', () {
    final good = deriveCredentialVerifier(_pin).split(r'$');
    for (final iterations in ['9999', '10000001', '0', '-5']) {
      final bad = [good[0], iterations, good[2], good[3]].join(r'$');
      expect(verifyCredential(_pin, bad), isFalse, reason: iterations);
    }
  });

  group('re-hash after a successful login', () {
    late InMemorySecureKeyStore store;
    late _Capture audit;

    setUp(() {
      store = InMemorySecureKeyStore();
      audit = _Capture();
    });

    Future<LocalAuthRepository> repoWithUser(
      CredentialKdfPolicy policy, {
      required String existingVerifier,
    }) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await Seeds(db).user(id: 'u', role: AppRole.MEDICAL_OFFICER);
      store.values[credentialVerifierStorageKey('u')] = existingVerifier;
      return LocalAuthRepository(
        userRepository: DriftUserRepository(db),
        keyStore: store,
        audit: audit,
        kdfPolicy: policy,
      );
    }

    test('an outdated verifier is upgraded to the policy in force; the PIN '
        'is never stored', () async {
      // Today's verifier, and a hypothetical future policy — the path a real
      // iteration increase will take.
      const future = CredentialKdfPolicy(iterations: 250000);
      final repo = await repoWithUser(
        future,
        existingVerifier: deriveCredentialVerifier(_pin),
      );

      await repo.login(userId: 'u', pin: _pin);

      final upgraded = store.values[credentialVerifierStorageKey('u')]!;
      expect(upgraded.split(r'$')[1], '250000');
      expect(verifyCredential(_pin, upgraded), isTrue);
      expect(store.values.values.any((v) => v.contains(_pin)), isFalse);
      expect(
        audit.events.map((e) => e.type),
        contains(SecurityEventType.pinVerifierUpgraded),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a verifier already at the policy is left alone', () async {
      final verifier = deriveCredentialVerifier(_pin);
      final repo = await repoWithUser(
        CredentialKdfPolicy.current,
        existingVerifier: verifier,
      );

      await repo.login(userId: 'u', pin: _pin);

      expect(store.values[credentialVerifierStorageKey('u')], verifier);
      expect(audit.events, isEmpty);
    });

    test('if the upgrade cannot be saved, login still succeeds and the old, '
        'valid verifier is kept', () async {
      const future = CredentialKdfPolicy(iterations: 250000);
      final original = deriveCredentialVerifier(_pin);
      final repo = await repoWithUser(future, existingVerifier: original);
      store.failWritesWhere = (key) => key == credentialVerifierStorageKey('u');

      final session = await repo.login(userId: 'u', pin: _pin);

      expect(session.userId, 'u');
      expect(store.values[credentialVerifierStorageKey('u')], original);
      store.failWritesWhere = null;
      // Still works; the upgrade is retried next time.
      await repo.login(userId: 'u', pin: _pin);
      expect(
        store.values[credentialVerifierStorageKey('u')]!.split(r'$')[1],
        '250000',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a wrong PIN never triggers an upgrade', () async {
      const future = CredentialKdfPolicy(iterations: 250000);
      final original = deriveCredentialVerifier(_pin);
      final repo = await repoWithUser(future, existingVerifier: original);

      await expectLater(repo.login(userId: 'u', pin: '000000'), throwsA(anything));

      expect(store.values[credentialVerifierStorageKey('u')], original);
    });
  });
}
