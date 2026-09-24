import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/auth/admin_recovery_code_store.dart';
import 'package:referredline/data/local/auth/credential_hasher.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:referredline/data/repositories/drift_user_repository.dart';
import 'package:referredline/data/repositories/local_auth_repository.dart';
import 'package:referredline/domain/entities/auth_recovery.dart';

import '../../support/in_memory_secure_key_store.dart';
import '../local/test_database.dart';

// Synthetic test PINs only.
const _pin = '728406';
const _newPin = '193527';

/// Lighter than production for speed; logic under test does not depend on
/// the iteration count (the production parameters are covered in
/// credential_hasher_test and kdf_versioning_test, and one test below runs
/// the whole reset at the production setting).
const _fast = CredentialKdfPolicy(iterations: 10000);

class _Harness {
  _Harness({this.policy = _fast})
    : db = openTestDatabase(),
      store = InMemorySecureKeyStore(),
      dbKeyStore = InMemorySecureKeyStore();

  final CredentialKdfPolicy policy;
  final AppDatabase db;
  final InMemorySecureKeyStore store;
  final InMemorySecureKeyStore dbKeyStore;
  DateTime now = DateTime.utc(2026, 9, 24, 9);

  LocalAuthRepository repo() => LocalAuthRepository(
    userRepository: DriftUserRepository(db),
    keyStore: store,
    audit: DatabaseSecurityAuditLog(db),
    kdfPolicy: policy,
    clock: () => now,
  );

  Future<List<String>> auditTexts() async => [
    for (final row in await db.select(db.auditLog).get())
      jsonEncode(row.toJson()),
  ];

  Future<List<String>> auditEvents() async => [
    for (final row in await db.select(db.auditLog).get())
      (jsonDecode(row.newValues!) as Map)['event'] as String,
  ];
}

Future<RecoveryCodeIssued> _setup(_Harness h) =>
    h.repo().setupBootstrapAdmin(displayName: 'Synthetic Admin', pin: _pin);

Future<Object?> _failureOf(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on Failure catch (e) {
    return e;
  }
}

void main() {
  late _Harness h;

  setUp(() => h = _Harness());
  tearDown(() => h.db.close());

  group('F. the Admin Recovery Code', () {
    test('is issued at first-run setup: 128-bit, AR-prefixed, stored only '
        'as a verifier, not yet confirmed', () async {
      final issued = await _setup(h);
      final code = SecretCode.parse(
        issued.recoveryCode!,
        SecretCodeKind.adminRecovery,
      );

      expect(code.bytes, hasLength(16));
      final record = await AdminRecoveryCodeStore(h.store).read();
      expect(record!.userId, issued.session.userId);
      expect(record.acknowledged, isFalse);
      expect(record.verifier, startsWith('pbkdf2-hmac-sha256\$'));
      expect(verifyCredential(code.canonical, record.verifier), isTrue);

      for (final v in h.store.values.values) {
        expect(v, isNot(contains(code.canonical)));
        expect(v, isNot(contains(issued.recoveryCode!)));
      }
    });

    test('differs every time (never fixed or predictable)', () async {
      final codes = <String>{};
      for (var i = 0; i < 3; i++) {
        final other = _Harness();
        addTearDown(other.db.close);
        codes.add((await _setup(other)).recoveryCode!);
      }
      expect(codes, hasLength(3));
    });

    test('confirming it marks it as written down', () async {
      await _setup(h);
      await h.repo().confirmRecoveryCodeRecorded();
      final status = await h.repo().adminRecoveryStatus();
      expect(status.exists, isTrue);
      expect(status.acknowledged, isTrue);
    });
  });

  group('E. PIN reset with the recovery code', () {
    test('a valid code resets the Admin PIN; the old PIN stops working; the '
        'database key and the data are untouched', () async {
      final issued = await _setup(h);
      final adminId = issued.session.userId;
      final dbKeys = DatabaseKeyManager(store: h.dbKeyStore);
      final dbKey = await dbKeys.resolveKey(databaseFileExists: false);
      final dbKeyWrites = h.dbKeyStore.writeCount;
      await Seeds(h.db).financialYear();

      final reset = await h.repo().resetPinWithRecoveryCode(
        recoveryCode: issued.recoveryCode!,
        newPin: _newPin,
      );

      expect(reset.session.userId, adminId);
      expect(reset.recoveryCodeSaved, isTrue);
      await expectLater(
        h.repo().login(userId: adminId, pin: _pin),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
      expect((await h.repo().login(userId: adminId, pin: _newPin)).userId, adminId);

      // Recovery never touches the database key or the database.
      expect(h.dbKeyStore.writeCount, dbKeyWrites);
      expect(await dbKeys.resolveKey(databaseFileExists: true), dbKey);
      expect(await h.db.select(h.db.financialYears).get(), hasLength(1));
      expect(await h.db.select(h.db.users).get(), hasLength(1));
    });

    test('works at the production KDF setting too', () async {
      final prod = _Harness(policy: CredentialKdfPolicy.current);
      addTearDown(prod.db.close);
      final issued = await _setup(prod);

      final reset = await prod.repo().resetPinWithRecoveryCode(
        recoveryCode: issued.recoveryCode!,
        newPin: _newPin,
      );

      expect(
        (await prod.repo().login(userId: reset.session.userId, pin: _newPin)).userId,
        reset.session.userId,
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('G. the code works once: reusing it is rejected, the new code works',
        () async {
      final issued = await _setup(h);
      final first = await h.repo().resetPinWithRecoveryCode(
        recoveryCode: issued.recoveryCode!,
        newPin: _newPin,
      );

      expect(
        await _failureOf(
          h.repo().resetPinWithRecoveryCode(
            recoveryCode: issued.recoveryCode!,
            newPin: '555555',
          ),
        ),
        isA<InvalidRecoveryCodeFailure>(),
      );
      expect(first.recoveryCode, isNot(issued.recoveryCode));
      final second = await h.repo().resetPinWithRecoveryCode(
        recoveryCode: first.recoveryCode!,
        newPin: '555555',
      );
      expect(second.session.userId, issued.session.userId);
    });

    test('an invalid code fails, changes nothing, and is audited', () async {
      final issued = await _setup(h);
      final other = SecretCode.generate(SecretCodeKind.adminRecovery);

      expect(
        await _failureOf(
          h.repo().resetPinWithRecoveryCode(
            recoveryCode: other.formatted,
            newPin: _newPin,
          ),
        ),
        isA<InvalidRecoveryCodeFailure>(),
      );
      expect(
        (await h.repo().login(userId: issued.session.userId, pin: _pin)).userId,
        issued.session.userId,
      );
      expect(
        await h.auditEvents(),
        contains(SecurityEventType.pinResetWithRecoveryCodeRejected.name),
      );
    });

    test('wrong codes are rate-limited: after 5, even the right code must '
        'wait', () async {
      final issued = await _setup(h);
      for (var i = 0; i < 5; i++) {
        await _failureOf(
          h.repo().resetPinWithRecoveryCode(
            recoveryCode: SecretCode.generate(SecretCodeKind.adminRecovery).formatted,
            newPin: _newPin,
          ),
        );
      }

      expect(
        await _failureOf(
          h.repo().resetPinWithRecoveryCode(
            recoveryCode: issued.recoveryCode!,
            newPin: _newPin,
          ),
        ),
        isA<AccountLockedFailure>(),
      );
      h.now = h.now.add(const Duration(seconds: 60));
      final reset = await h.repo().resetPinWithRecoveryCode(
        recoveryCode: issued.recoveryCode!,
        newPin: _newPin,
      );
      expect(reset.session.userId, issued.session.userId);
    });

    test('typing mistakes are explained and do not count as attempts',
        () async {
      final issued = await _setup(h);
      final chars = issued.recoveryCode!.split('');
      final i = chars.lastIndexOf('-') + 1;
      chars[i] = chars[i] == '2' ? '3' : '2';
      final typo = chars.join();

      for (var n = 0; n < 7; n++) {
        final failure = await _failureOf(
          h.repo().resetPinWithRecoveryCode(recoveryCode: typo, newPin: _newPin),
        );
        // A one-character change is caught by the check character (or, 1 in
        // 32, is a different valid-looking code, i.e. a wrong code).
        expect(failure, anyOf(isA<RecoveryCodeTypingFailure>(), isA<InvalidRecoveryCodeFailure>()));
        if (failure is InvalidRecoveryCodeFailure) {
          return; // Rare case; the lockout behaviour is covered above.
        }
      }
      final reset = await h.repo().resetPinWithRecoveryCode(
        recoveryCode: issued.recoveryCode!,
        newPin: _newPin,
      );
      expect(reset.session.userId, issued.session.userId);
    });

    test('entering the Backup Recovery Key by mistake gets a clear message',
        () async {
      await _setup(h);
      final failure = await _failureOf(
        h.repo().resetPinWithRecoveryCode(
          recoveryCode: SecretCode.generate(SecretCodeKind.backupRecovery).formatted,
          newPin: _newPin,
        ),
      );
      expect(failure, isA<RecoveryCodeTypingFailure>());
      expect((failure! as Failure).message, contains('Backup Recovery Key'));
    });

    test('a bad new PIN is rejected before the code is checked or used',
        () async {
      final issued = await _setup(h);
      expect(
        await _failureOf(
          h.repo().resetPinWithRecoveryCode(
            recoveryCode: issued.recoveryCode!,
            newPin: '12345',
          ),
        ),
        isA<InvalidPinFormatFailure>(),
      );
      // Code still valid.
      await h.repo().resetPinWithRecoveryCode(
        recoveryCode: issued.recoveryCode!,
        newPin: _newPin,
      );
    });

    test('no code set up on this phone', () async {
      await Seeds(h.db).user(id: 'a', role: AppRole.ADMIN);
      expect(
        await _failureOf(
          h.repo().resetPinWithRecoveryCode(
            recoveryCode: SecretCode.generate(SecretCodeKind.adminRecovery).formatted,
            newPin: _newPin,
          ),
        ),
        isA<NoRecoveryCodeFailure>(),
      );
    });

    test('a deactivated Admin cannot be brought back with the code', () async {
      final issued = await _setup(h);
      await (h.db.update(h.db.users)
            ..where((t) => t.id.equals(issued.session.userId)))
          .write(const UsersCompanion(isActive: Value(false)));

      expect(
        await _failureOf(
          h.repo().resetPinWithRecoveryCode(
            recoveryCode: issued.recoveryCode!,
            newPin: _newPin,
          ),
        ),
        isA<RecoveryAccountUnavailableFailure>(),
      );
    });

    test('if the new code cannot be saved, the PIN is still reset and the '
        'old code stays valid — nobody is locked out', () async {
      final issued = await _setup(h);
      h.store.failWritesWhere = (k) => k == AdminRecoveryCodeStore.storageKey;

      final reset = await h.repo().resetPinWithRecoveryCode(
        recoveryCode: issued.recoveryCode!,
        newPin: _newPin,
      );

      expect(reset.recoveryCodeSaved, isFalse);
      expect(reset.recoveryCode, isNull);
      h.store.failWritesWhere = null;
      await h.repo().login(userId: issued.session.userId, pin: _newPin);
      await h.repo().resetPinWithRecoveryCode(
        recoveryCode: issued.recoveryCode!,
        newPin: '555555',
      );
    });
  });

  group('replacing the code (More → Admin Recovery Code)', () {
    test('needs the current PIN; the old code then stops working', () async {
      final issued = await _setup(h);

      expect(
        await _failureOf(h.repo().createNewRecoveryCode(currentPin: '000000')),
        isA<InvalidCredentialsFailure>(),
      );
      final replacement = await h.repo().createNewRecoveryCode(currentPin: _pin);

      expect(
        await _failureOf(
          h.repo().resetPinWithRecoveryCode(
            recoveryCode: issued.recoveryCode!,
            newPin: _newPin,
          ),
        ),
        isA<InvalidRecoveryCodeFailure>(),
      );
      await h.repo().resetPinWithRecoveryCode(
        recoveryCode: replacement,
        newPin: _newPin,
      );
    });

    test('a non-Admin cannot create one', () async {
      await _setup(h);
      await Seeds(h.db).user(id: 'mo', role: AppRole.MEDICAL_OFFICER);
      h.store.values[credentialVerifierStorageKey('mo')] =
          deriveCredentialVerifier(_pin, policy: _fast);
      await h.repo().logout();
      await h.repo().login(userId: 'mo', pin: _pin);

      expect(
        await _failureOf(h.repo().createNewRecoveryCode(currentPin: _pin)),
        isA<NotAuthorizedFailure>(),
      );
    });
  });

  group('K. audit', () {
    test('recovery operations are audited in audit_log, and no PIN or code '
        'appears anywhere in it', () async {
      final issued = await _setup(h);
      await h.repo().confirmRecoveryCodeRecorded();
      await _failureOf(
        h.repo().resetPinWithRecoveryCode(
          recoveryCode: SecretCode.generate(SecretCodeKind.adminRecovery).formatted,
          newPin: _newPin,
        ),
      );
      final reset = await h.repo().resetPinWithRecoveryCode(
        recoveryCode: issued.recoveryCode!,
        newPin: _newPin,
      );

      final events = await h.auditEvents();
      expect(events, containsAll([
        SecurityEventType.adminRecoveryCodeCreated.name,
        SecurityEventType.adminRecoveryCodeConfirmed.name,
        SecurityEventType.pinResetWithRecoveryCodeRejected.name,
        SecurityEventType.pinResetWithRecoveryCodeSucceeded.name,
      ]));
      final rows = await h.db.select(h.db.auditLog).get();
      expect(rows.every((r) => r.businessTableName == securityEventTableName), isTrue);
      expect(rows.every((r) => r.action == AuditAction.INSERT), isTrue);

      final secrets = [
        _pin,
        _newPin,
        issued.recoveryCode!,
        SecretCode.parse(issued.recoveryCode!, SecretCodeKind.adminRecovery).canonical,
        reset.recoveryCode!,
        SecretCode.parse(reset.recoveryCode!, SecretCodeKind.adminRecovery).canonical,
        ...h.store.values.values.where((v) => v.startsWith('pbkdf2')),
      ];
      for (final text in await h.auditTexts()) {
        for (final secret in secrets) {
          expect(text, isNot(contains(secret)));
        }
      }
    });
  });
}
