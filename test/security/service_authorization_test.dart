import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/auth/admin_recovery_code_store.dart';
import 'package:referredline/data/local/auth/credential_hasher.dart';
import 'package:referredline/data/local/auth/login_lockout_tracker.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/local/recovery/backup_key_store.dart';
import 'package:referredline/data/local/recovery/database_recovery_service.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:referredline/data/repositories/local_auth_repository.dart';

import '../support/phone_fixture.dart';

// Synthetic test PINs only.
const _pin = '615093';
const _otherPin = '284751';
const _wrongPin = '000001';
const _timeout = Timeout(Duration(minutes: 3));

/// Every privileged operation is called directly — the way a bug or a
/// future screen could — rather than through the UI, to prove the service
/// layer itself enforces "active Admin, logged in, PIN re-entered".
void main() {
  late Phone phone;
  late AppDatabase db;
  late String adminId;
  late String adminCode;

  LocalAuthRepository auth() => phone.auth(db);

  Future<void> addUser(String id, AppRole role, String pin) async {
    await db
        .into(db.users)
        .insert(UsersCompanion.insert(id: id, displayName: id, role: role));
    phone.appKeys.values[credentialVerifierStorageKey(id)] =
        deriveCredentialVerifier(pin, policy: fastKdf);
  }

  Future<void> setActive(String id, {required bool active}) =>
      (db.update(db.users)..where((t) => t.id.equals(id))).write(
        UsersCompanion(isActive: Value(active)),
      );

  Future<List<Map<String, dynamic>>> events() async => [
    for (final r in await db.select(db.auditLog).get())
      {
        ...jsonDecode(r.newValues!) as Map<String, dynamic>,
        'actor': r.actorUserId,
      },
  ];

  Future<int> count(SecurityEventType type) async =>
      (await events()).where((e) => e['event'] == type.name).length;

  List<File> packagesIn(Phone p) {
    final work = Directory('${p.dir.path}/work');
    return work.existsSync()
        ? work.listSync().whereType<File>().toList()
        : const [];
  }

  setUp(() async {
    phone = Phone('authz');
    db = await phone.open();
    final issued = await auth().setupBootstrapAdmin(
      displayName: 'Synthetic Admin',
      pin: _pin,
    );
    adminId = issued.session.userId;
    adminCode = issued.recoveryCode!;
    await addUser('mo', AppRole.MEDICAL_OFFICER, _otherPin);
    await addUser('tm', AppRole.TEAM_MEMBER, _otherPin);
    await addUser('admin-2', AppRole.ADMIN, _otherPin);
  });

  tearDown(() async {
    await db.close();
    phone.delete();
  });

  /// The ways a caller can lack authority. Each arranges the persisted
  /// session, and returns the PIN the caller would pass and the failure the
  /// service must answer with.
  final unauthorized = <String, Future<(String, Type)> Function()>{
    'nobody logged in': () async {
      await auth().logout();
      return (_pin, NoActiveSessionFailure);
    },
    'a Medical Officer': () async {
      await auth().logout();
      await auth().login(userId: 'mo', pin: _otherPin);
      return (_otherPin, NotAuthorizedFailure);
    },
    'a Team Member': () async {
      await auth().logout();
      await auth().login(userId: 'tm', pin: _otherPin);
      return (_otherPin, NotAuthorizedFailure);
    },
    'a deactivated Admin whose session is still stored': () async {
      await setActive(adminId, active: false);
      return (_pin, NoActiveSessionFailure);
    },
    'an Admin demoted after logging in (stale role in the session)': () async {
      await (db.update(db.users)..where((t) => t.id.equals(adminId))).write(
        const UsersCompanion(role: Value(AppRole.MEDICAL_OFFICER)),
      );
      return (_pin, NotAuthorizedFailure);
    },
    'the Admin with a wrong PIN': () async => (_wrongPin, InvalidCredentialsFailure),
  };

  group('export (createPackage) checks authority itself', () {
    setUp(() async {
      await phone.service().createBackupKey(
        auth: auth(),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
    });

    for (final MapEntry(key: who, value: arrange) in unauthorized.entries) {
      test('refused for $who: no package is written, the refusal is audited',
          () async {
        final (pin, failure) = await arrange();
        final exportsBefore = await count(SecurityEventType.backupExportCreated);

        await expectLater(
          phone.service().createPackage(
            db,
            auth: auth(),
            currentPin: pin,
            audit: DatabaseSecurityAuditLog(db),
          ),
          throwsA(isA<Failure>().having((f) => f.runtimeType, 'type', failure)),
        );

        expect(packagesIn(phone), isEmpty);
        expect(await count(SecurityEventType.backupExportCreated), exportsBefore);
        final denied = (await events()).where(
          (e) => e['event'] == SecurityEventType.privilegedActionDenied.name,
        );
        expect(denied.last['operation'], 'exportBackup');
      }, timeout: _timeout);
    }

    test('allowed for the logged-in Admin with the right PIN; the audit names '
        'the session user as the actor', () async {
      final package = await phone.service().createPackage(
        db,
        auth: auth(),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
      expect(package.existsSync(), isTrue);
      final created = (await events()).lastWhere(
        (e) => e['event'] == SecurityEventType.backupExportCreated.name,
      );
      expect(created['actor'], adminId);
    }, timeout: _timeout);

    test('no space for the package: export fails at once (it does not hang), '
        'leaves nothing behind, and the failure is audited', () async {
      final service = DatabaseRecoveryService(
        keyManager: phone.keyManager,
        backupKeys: phone.backupKeys,
        databaseFileLocator: () async => phone.dbFile,
        workDirectory: () async => Directory('${phone.dir.path}/work'),
        preOpenAudit: phone.journal,
        clock: () => DateTime.utc(2026, 9, 24, 12),
      );
      // Stand-in for a full disk: the package file cannot be created.
      Directory(
        '${phone.dir.path}/work/rbsk-recovery-20260924-120000.rbskrp',
      ).createSync(recursive: true);

      await expectLater(
        service.createPackage(
          db,
          auth: auth(),
          currentPin: _pin,
          audit: DatabaseSecurityAuditLog(db),
        ),
        throwsA(isA<FileSystemException>()),
      ).timeout(const Duration(seconds: 30));
      expect(packagesIn(phone), isEmpty, reason: 'no snapshot, no package');
      expect(await count(SecurityEventType.backupExportFailed), 1);
    }, timeout: _timeout);

    test('repeated wrong PINs lock the Admin out of export (and login) like '
        'any PIN check', () async {
      for (var i = 0; i < LoginLockoutTracker.maxAttempts; i++) {
        await expectLater(
          phone.service().createPackage(
            db,
            auth: auth(),
            currentPin: _wrongPin,
            audit: DatabaseSecurityAuditLog(db),
          ),
          throwsA(isA<InvalidCredentialsFailure>()),
        );
      }
      await expectLater(
        phone.service().createPackage(
          db,
          auth: auth(),
          currentPin: _pin,
          audit: DatabaseSecurityAuditLog(db),
        ),
        throwsA(isA<AccountLockedFailure>()),
      );
      expect(packagesIn(phone), isEmpty);
    }, timeout: _timeout);
  });

  group('creating the Backup Recovery Key checks authority itself', () {
    for (final MapEntry(key: who, value: arrange) in unauthorized.entries) {
      test('refused for $who: nothing is stored', () async {
        final (pin, failure) = await arrange();

        await expectLater(
          phone.service().createBackupKey(
            auth: auth(),
            currentPin: pin,
            audit: DatabaseSecurityAuditLog(db),
          ),
          throwsA(isA<Failure>().having((f) => f.runtimeType, 'type', failure)),
        );
        expect(phone.appKeys.values[BackupKeyStore.storageKey], isNull);
        expect(await count(SecurityEventType.backupKeyCreated), 0);
      }, timeout: _timeout);
    }

    test('an existing key is not replaced by an unauthorized caller', () async {
      await phone.service().createBackupKey(
        auth: auth(),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
      final stored = phone.appKeys.values[BackupKeyStore.storageKey];
      await auth().logout();
      await auth().login(userId: 'mo', pin: _otherPin);

      await expectLater(
        phone.service().createBackupKey(
          auth: auth(),
          currentPin: _otherPin,
          audit: DatabaseSecurityAuditLog(db),
        ),
        throwsA(isA<NotAuthorizedFailure>()),
      );
      expect(phone.appKeys.values[BackupKeyStore.storageKey], stored);
    }, timeout: _timeout);
  });

  group('replacing the Admin Recovery Code is bound to the session', () {
    for (final MapEntry(key: who, value: arrange) in unauthorized.entries) {
      test('refused for $who: the existing code keeps working', () async {
        final (pin, failure) = await arrange();
        final before = phone.appKeys.values[AdminRecoveryCodeStore.storageKey];

        await expectLater(
          auth().createNewRecoveryCode(currentPin: pin),
          throwsA(isA<Failure>().having((f) => f.runtimeType, 'type', failure)),
        );
        expect(phone.appKeys.values[AdminRecoveryCodeStore.storageKey], before);
      }, timeout: _timeout);
    }

    test('a second Admin replaces the code for themselves, never for '
        'someone else', () async {
      await auth().logout();
      await auth().login(userId: 'admin-2', pin: _otherPin);
      await auth().createNewRecoveryCode(currentPin: _otherPin);
      final record = await AdminRecoveryCodeStore(phone.appKeys).read();
      expect(record!.userId, 'admin-2');
    }, timeout: _timeout);
  });

  group('confirming the recovery code as written down', () {
    final notOwner = <String, Future<void> Function()>{
      'nobody logged in': () => auth().logout(),
      'a Medical Officer': () async {
        await auth().logout();
        await auth().login(userId: 'mo', pin: _otherPin);
      },
      'a deactivated Admin': () => setActive(adminId, active: false),
      'a different Admin': () async {
        await auth().logout();
        await auth().login(userId: 'admin-2', pin: _otherPin);
      },
    };
    for (final MapEntry(key: who, value: arrange) in notOwner.entries) {
      test('is refused for $who', () async {
        await arrange();
        await expectLater(
          auth().confirmRecoveryCodeRecorded(),
          throwsA(isA<Failure>()),
        );
        expect((await auth().adminRecoveryStatus()).acknowledged, isFalse);
      }, timeout: _timeout);
    }

    test('works for the code\'s own Admin', () async {
      await auth().confirmRecoveryCodeRecorded();
      expect((await auth().adminRecoveryStatus()).acknowledged, isTrue);
    }, timeout: _timeout);
  });

  group('import (restore) never replaces data that is in use', () {
    late SecretCode backupKey;
    late File package;

    setUp(() async {
      backupKey = await phone.service().createBackupKey(
        auth: auth(),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
      package = await phone.service().createPackage(
        db,
        auth: auth(),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
      final kept = File('${phone.dir.path}/kept.rbskrp');
      await package.copy(kept.path);
      package = kept;
    });

    test('verify is refused on a phone whose database opens and has '
        'accounts, without any login; nothing changes', () async {
      await db.close();
      final before = phone.dbFile.readAsBytesSync();
      final keysBefore = Map.of(phone.dbKeys.values);

      await expectLater(
        phone.service().verify(
          package,
          backupKey.formatted,
          context: RestoreContext.newDevice,
        ),
        throwsA(isA<DatabaseInUseException>()),
      );
      expect(phone.dbFile.readAsBytesSync(), before);
      expect(phone.dbKeys.values, keysBefore);
      expect(File('${phone.dbFile.path}.restore-staged').existsSync(), isFalse);
      expect(phone.journalFile.readAsStringSync(), contains('databaseInUse'));
      db = await phone.open();
    }, timeout: _timeout);

    test('install re-checks: a phone set up after verify is not replaced',
        () async {
      final b = Phone('b');
      addTearDown(b.delete);
      final fresh = await b.open();
      await fresh.select(fresh.users).get(); // first launch creates the file
      final verified = await b.service().verify(
        package,
        backupKey.formatted,
        context: RestoreContext.newDevice,
      );
      // Meanwhile someone completes first-run setup on phone B.
      await b.auth(fresh).setupBootstrapAdmin(displayName: 'B Admin', pin: _pin);
      await fresh.close();
      final before = b.dbFile.readAsBytesSync();

      await expectLater(
        b.service().install(verified, confirmedByUser: true),
        throwsA(isA<DatabaseInUseException>()),
      );
      expect(b.dbFile.readAsBytesSync(), before);
      expect(File('${b.dbFile.path}.restore-staged').existsSync(), isFalse);
      final reopened = await b.open();
      expect((await reopened.select(reopened.users).get()).single.displayName, 'B Admin');
      await reopened.close();
    }, timeout: _timeout);

    test('a phone whose data is locked (key lost) can still be restored',
        () async {
      await db.close();
      phone.dbKeys.values.clear();
      final verified = await phone.service().verify(
        package,
        backupKey.formatted,
        context: RestoreContext.keyUnavailable,
      );
      await phone.service().install(verified, confirmedByUser: true);
      db = await phone.open();
      expect((await db.select(db.users).get()).map((u) => u.id), contains(adminId));
    }, timeout: _timeout);
  });

  group('the two recovery secrets stay separate', () {
    test('the Admin Recovery Code cannot open a recovery package', () async {
      final backupKey = await phone.service().createBackupKey(
        auth: auth(),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
      expect(backupKey.canonical, isNot(SecretCode.parse(
        adminCode, SecretCodeKind.adminRecovery).canonical));
      final package = await phone.service().createPackage(
        db,
        auth: auth(),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
      final b = Phone('b');
      addTearDown(b.delete);

      await expectLater(
        b.service().verify(package, adminCode, context: RestoreContext.newDevice),
        throwsA(
          isA<SecretCodeFormatException>().having(
            (e) => e.problem,
            'problem',
            SecretCodeProblem.wrongKind,
          ),
        ),
      );
      expect(File('${b.dbFile.path}.restore-staged').existsSync(), isFalse);
    }, timeout: _timeout);

    test('the Backup Recovery Key cannot reset a PIN, and is not even '
        'counted as a recovery-code attempt', () async {
      final backupKey = await phone.service().createBackupKey(
        auth: auth(),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
      for (var i = 0; i <= LoginLockoutTracker.maxAttempts; i++) {
        await expectLater(
          auth().resetPinWithRecoveryCode(
            recoveryCode: backupKey.formatted,
            newPin: _otherPin,
          ),
          throwsA(isA<RecoveryCodeTypingFailure>()),
        );
      }
      // Not locked out: the real code still works.
      await auth().resetPinWithRecoveryCode(
        recoveryCode: adminCode,
        newPin: _otherPin,
      );
    }, timeout: _timeout);

    test('the Backup Recovery Key cannot set an Admin PIN while an Admin can '
        'log in', () async {
      final backupKey = await phone.service().createBackupKey(
        auth: auth(),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
      await expectLater(
        auth().restoreAdminAccess(
          backupKey: backupKey.formatted,
          adminUserId: adminId,
          newPin: _otherPin,
        ),
        throwsA(isA<AdminAccessRestoreNotAllowedFailure>()),
      );
      await auth().login(userId: adminId, pin: _pin);
    }, timeout: _timeout);

    test('the Admin Recovery Code cannot stand in for the Backup Recovery Key '
        'when restoring Admin access', () async {
      await phone.service().createBackupKey(
        auth: auth(),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
      // No Admin PIN on the phone (as right after a restore).
      for (final id in [adminId, 'admin-2']) {
        phone.appKeys.values.remove(credentialVerifierStorageKey(id));
      }
      await expectLater(
        auth().restoreAdminAccess(
          backupKey: adminCode,
          adminUserId: adminId,
          newPin: _otherPin,
        ),
        throwsA(isA<RecoveryCodeTypingFailure>()),
      );
    }, timeout: _timeout);

    test('they are stored under different names, and neither verifies as '
        'the other', () async {
      final backupKey = await phone.service().createBackupKey(
        auth: auth(),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
      expect(AdminRecoveryCodeStore.storageKey, isNot(BackupKeyStore.storageKey));
      final record = await AdminRecoveryCodeStore(phone.appKeys).read();
      expect(verifyCredential(backupKey.canonical, record!.verifier), isFalse);
      final material = await BackupKeyStore(phone.appKeys).read();
      expect(
        material!.matches(
          SecretCode.parse(adminCode, SecretCodeKind.adminRecovery),
        ),
        isFalse,
      );
    }, timeout: _timeout);
  });
}
