import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/auth/credential_hasher.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/repositories/drift_user_repository.dart';
import 'package:referredline/data/repositories/local_auth_repository.dart';
import 'package:referredline/domain/entities/auth_status.dart';

import '../../support/in_memory_secure_key_store.dart';
import '../local/test_database.dart';

// Synthetic test PINs only — never a real credential.
const _pin = '314159';
const _wrongPin = '314158';

/// One verifier derived once and reused to provision test users, so the
/// suite doesn't pay the full KDF cost for every provisioned account.
late String _sharedVerifier;

class _Harness {
  _Harness() : db = openTestDatabase(), store = InMemorySecureKeyStore();

  final AppDatabase db;
  final InMemorySecureKeyStore store;
  DateTime now = DateTime.utc(2026, 9, 23, 9);

  /// A new repository over the same database and store — i.e. what the app
  /// sees after a restart.
  LocalAuthRepository repo() => LocalAuthRepository(
    userRepository: DriftUserRepository(db),
    keyStore: store,
    clock: () => now,
  );

  /// Creates a user the way a later user-management phase would: a `users`
  /// row plus a verifier for the synthetic [_pin]. Phase 1.4 has no in-app
  /// flow for creating non-Admin users, so tests provision them directly.
  Future<String> provision({
    String id = 'user-1',
    AppRole role = AppRole.TEAM_MEMBER,
  }) async {
    await Seeds(db).user(id: id, role: role);
    store.values[credentialVerifierStorageKey(id)] = _sharedVerifier;
    return id;
  }

  Future<void> deactivate(String id) =>
      (db.update(db.users)..where((t) => t.id.equals(id))).write(
        const UsersCompanion(isActive: Value(false)),
      );

  Future<int> userCount() => db
      .customSelect('SELECT COUNT(*) AS c FROM users')
      .getSingle()
      .then((r) => r.read<int>('c'));

  bool get hasPersistedSession =>
      (store.values[authSessionStorageKey] ?? '').isNotEmpty;
}

void main() {
  setUpAll(() {
    _sharedVerifier = deriveCredentialVerifier(_pin);
  });

  late _Harness h;

  setUp(() => h = _Harness());
  tearDown(() => h.db.close());

  group('first run', () {
    test('an empty database is UNINITIALIZED, with no session', () async {
      expect(await h.repo().determineStatus(), isA<AuthUninitialized>());
      expect(await h.repo().currentSession(), isNull);
    });

    test(
      'Admin setup creates exactly one ADMIN user and authenticates it',
      () async {
        final session = await h.repo().setupBootstrapAdmin(
          displayName: '  Synthetic Admin  ',
          pin: _pin,
        );
        final row = await h.db.select(h.db.users).getSingle();

        expect(session.role, AppRole.ADMIN);
        expect(session.userId, row.id);
        expect(row.role, AppRole.ADMIN);
        expect(row.displayName, 'Synthetic Admin');
        expect(row.staffId, isNull);
        expect(row.isActive, isTrue);

        final status = await h.repo().determineStatus();
        expect(status, isA<AuthAuthenticated>());
        expect((status as AuthAuthenticated).session.userId, row.id);
      },
    );

    test('Admin setup cannot be run a second time', () async {
      await h.repo().setupBootstrapAdmin(displayName: 'First', pin: _pin);

      await expectLater(
        h.repo().setupBootstrapAdmin(displayName: 'Second', pin: '999999'),
        throwsA(isA<BootstrapAlreadyCompletedFailure>()),
      );
      expect(await h.userCount(), 1);
    });

    test(
      'Admin setup is refused if any user already exists, whatever its role',
      () async {
        await h.provision(role: AppRole.TEAM_MEMBER);

        await expectLater(
          h.repo().setupBootstrapAdmin(displayName: 'Intruder', pin: _pin),
          throwsA(isA<BootstrapAlreadyCompletedFailure>()),
        );
        expect(await h.userCount(), 1);
      },
    );

    test('Admin setup rejects any PIN that is not exactly 6 digits, writing '
        'nothing', () async {
      for (final bad in [
        '',
        '12345',
        '1234567',
        '12345a',
        ' 12345',
        '12 456',
      ]) {
        await expectLater(
          h.repo().setupBootstrapAdmin(displayName: 'Admin', pin: bad),
          throwsA(isA<InvalidPinFormatFailure>()),
          reason: 'PIN "$bad"',
        );
      }
      expect(await h.userCount(), 0);
      expect(h.store.values, isEmpty);
      expect(await h.repo().determineStatus(), isA<AuthUninitialized>());
    });

    test('Admin setup rejects a blank name, writing nothing', () async {
      await expectLater(
        h.repo().setupBootstrapAdmin(displayName: '   ', pin: _pin),
        throwsA(isA<InvalidDisplayNameFailure>()),
      );
      expect(await h.userCount(), 0);
      expect(h.store.values, isEmpty);
    });
  });

  group('the raw PIN is never persisted', () {
    test('neither secure storage nor the users table contains it after '
        'setup, logout and login', () async {
      final repo = h.repo();
      final session = await repo.setupBootstrapAdmin(
        displayName: 'Admin',
        pin: _pin,
      );
      await repo.logout();
      await repo.login(userId: session.userId, pin: _pin);

      for (final entry in h.store.values.entries) {
        expect(entry.value, isNot(contains(_pin)), reason: entry.key);
      }
      final rows = await h.db.customSelect('SELECT * FROM users').get();
      for (final row in rows) {
        for (final value in row.data.values) {
          expect('$value', isNot(contains(_pin)));
        }
      }

      final verifier =
          h.store.values[credentialVerifierStorageKey(session.userId)]!;
      expect(verifier, startsWith('pbkdf2-hmac-sha256\$210000\$'));
      expect(verifyCredential(_pin, verifier), isTrue);
    });
  });

  group('login', () {
    test(
      'the correct PIN creates a session and records last_login_at',
      () async {
        final id = await h.provision(role: AppRole.MEDICAL_OFFICER);

        final session = await h.repo().login(userId: id, pin: _pin);
        final row = await (h.db.select(
          h.db.users,
        )..where((t) => t.id.equals(id))).getSingle();

        expect(session.userId, id);
        expect(session.role, AppRole.MEDICAL_OFFICER);
        expect(session.loggedInAt, h.now);
        expect(row.lastLoginAt, h.now);
        expect(h.hasPersistedSession, isTrue);
      },
    );

    test('an incorrect PIN is rejected and creates no session', () async {
      final id = await h.provision();

      await expectLater(
        h.repo().login(userId: id, pin: _wrongPin),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
      expect(h.hasPersistedSession, isFalse);
      expect(await h.repo().determineStatus(), isA<AuthLoggedOut>());
    });

    test(
      'an unknown user id is rejected the same way as a wrong PIN',
      () async {
        await h.provision();

        await expectLater(
          h.repo().login(userId: 'no-such-user', pin: _pin),
          throwsA(isA<InvalidCredentialsFailure>()),
        );
      },
    );

    test('a user with no stored verifier cannot log in', () async {
      await Seeds(h.db).user(id: 'no-credential');

      await expectLater(
        h.repo().login(userId: 'no-credential', pin: _pin),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
    });

    test('a deactivated user is rejected even with the correct PIN', () async {
      final id = await h.provision();
      await h.deactivate(id);

      await expectLater(
        h.repo().login(userId: id, pin: _pin),
        throwsA(isA<AccountDeactivatedFailure>()),
      );
      expect(h.hasPersistedSession, isFalse);
    });
  });

  group('role resolution', () {
    for (final role in AppRole.values) {
      test('a ${role.name} user gets a ${role.name} session', () async {
        final id = await h.provision(id: 'user-${role.name}', role: role);

        final session = await h.repo().login(userId: id, pin: _pin);
        final status = await h.repo().determineStatus() as AuthAuthenticated;

        expect(session.role, role);
        expect(status.session.role, role);
      });
    }
  });

  group('session', () {
    test(
      'is restored by a new repository instance (app restart), offline',
      () async {
        final id = await h.provision(role: AppRole.MEDICAL_OFFICER);
        final original = await h.repo().login(userId: id, pin: _pin);

        final restored = await h.repo().currentSession();

        expect(restored, isNotNull);
        expect(restored!.userId, original.userId);
        expect(restored.role, original.role);
        expect(restored.loggedInAt, original.loggedInAt);
      },
    );

    test('identifies the user by id; a restored session picks up the current '
        'role from the users row', () async {
      final id = await h.provision(role: AppRole.TEAM_MEMBER);
      await h.repo().login(userId: id, pin: _pin);
      await (h.db.update(h.db.users)..where((t) => t.id.equals(id))).write(
        const UsersCompanion(role: Value(AppRole.MEDICAL_OFFICER)),
      );

      final restored = await h.repo().currentSession();

      expect(restored!.userId, id);
      expect(restored.role, AppRole.MEDICAL_OFFICER);
    });

    test(
      'logout invalidates the session; the credential still works',
      () async {
        final id = await h.provision();
        final repo = h.repo();
        await repo.login(userId: id, pin: _pin);

        await repo.logout();

        expect(h.hasPersistedSession, isFalse);
        expect(await h.repo().currentSession(), isNull);
        expect(await h.repo().determineStatus(), isA<AuthLoggedOut>());
        expect(await h.repo().login(userId: id, pin: _pin), isNotNull);
      },
    );

    test('a corrupted persisted session is treated as logged out', () async {
      await h.provision();
      for (final bad in [
        '{',
        '{"userId":1}',
        '{"userId":"u","role":"KING",'
            '"loggedInAt":"2026-01-01T00:00:00Z"}',
      ]) {
        h.store.values[authSessionStorageKey] = bad;
        expect(await h.repo().currentSession(), isNull, reason: bad);
        expect(await h.repo().determineStatus(), isA<AuthLoggedOut>());
      }
    });

    test(
      'a session for a since-deactivated user is refused and cleared',
      () async {
        final id = await h.provision();
        await h.repo().login(userId: id, pin: _pin);
        await h.deactivate(id);

        expect(await h.repo().currentSession(), isNull);
        expect(h.hasPersistedSession, isFalse);
        expect(await h.repo().determineStatus(), isA<AuthLoggedOut>());
      },
    );

    test(
      'a session pointing at a user that does not exist is refused',
      () async {
        await h.provision();
        h.store.values[authSessionStorageKey] = '{"userId":"ghost","role":"ADMIN","loggedInAt":"2026-01-01T00:00:00.000Z"}';

        expect(await h.repo().currentSession(), isNull);
      },
    );
  });

  group('brute-force mitigation', () {
    test('5 wrong PINs lock the user out — even the correct PIN is refused '
        'until 60 seconds pass', () async {
      final id = await h.provision();
      final repo = h.repo();

      for (var i = 0; i < 5; i++) {
        await expectLater(
          repo.login(userId: id, pin: _wrongPin),
          throwsA(isA<InvalidCredentialsFailure>()),
        );
      }

      await expectLater(
        repo.login(userId: id, pin: _pin),
        throwsA(
          isA<AccountLockedFailure>().having(
            (f) => f.retryAfter,
            'retryAfter',
            const Duration(seconds: 60),
          ),
        ),
      );
      expect(h.hasPersistedSession, isFalse);

      h.now = h.now.add(const Duration(seconds: 60));
      expect(await repo.login(userId: id, pin: _pin), isNotNull);
    });

    test('one user\'s lockout does not affect another user', () async {
      final locked = await h.provision(id: 'locked');
      final other = await h.provision(id: 'other');
      final repo = h.repo();

      for (var i = 0; i < 5; i++) {
        await expectLater(
          repo.login(userId: locked, pin: _wrongPin),
          throwsA(isA<InvalidCredentialsFailure>()),
        );
      }

      expect(await repo.login(userId: other, pin: _pin), isNotNull);
    });

    test('a successful login resets the failure count', () async {
      final id = await h.provision();
      final repo = h.repo();

      for (var i = 0; i < 4; i++) {
        await expectLater(
          repo.login(userId: id, pin: _wrongPin),
          throwsA(isA<InvalidCredentialsFailure>()),
        );
      }
      await repo.login(userId: id, pin: _pin);
      await expectLater(
        repo.login(userId: id, pin: _wrongPin),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
    });
  });
}
