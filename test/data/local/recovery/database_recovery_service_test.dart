import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/security/crypto_utils.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/recovery/database_recovery_service.dart';
import 'package:referredline/data/local/recovery/recovery_package.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../../support/phone_fixture.dart';
import '../test_database.dart';

// Synthetic test PINs only.
const _pin = '846102';
const _newPin = '290374';
const _timeout = Timeout(Duration(minutes: 3));

bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}

void main() {
  late Phone a;
  late Phone b;

  // Phone A as a real phone would be: an Admin, some data, a backup key.
  late String adminId;
  late SecretCode backupKey;
  late File package;

  setUp(() async {
    a = Phone('a');
    b = Phone('b');

    final db = await a.open();
    final issued = await a.auth(db).setupBootstrapAdmin(
      displayName: 'Synthetic Admin',
      pin: _pin,
    );
    adminId = issued.session.userId;
    await db
        .into(db.financialYears)
        .insert(
          FinancialYearsCompanion.insert(
            id: 'fy-1',
            label: 'FY-MARKER-2025',
            startDate: DateTime.utc(2025, 4, 1),
            endDate: DateTime.utc(2026, 3, 31),
          ),
        );
    backupKey = await a.service().createBackupKey(
      auth: a.auth(db),
      currentPin: _pin,
      audit: DatabaseSecurityAuditLog(db),
    );
    package = await a.service().createPackage(
      db,
      auth: a.auth(db),
      currentPin: _pin,
      audit: DatabaseSecurityAuditLog(db),
    );
    await db.close();
  });

  tearDown(() {
    a.delete();
    b.delete();
  });

  group('H. export', () {
    test('produces an encrypted package: no plaintext database content, no '
        'plaintext database key, no backup key; the snapshot is cleaned up',
        () async {
      final bytes = package.readAsBytesSync();
      final dbKey = a.dbKeys.values[databaseKeyStorageName]!;

      expect(latin1.decode(bytes), isNot(contains('SQLite format 3')));
      expect(latin1.decode(bytes), isNot(contains('FY-MARKER-2025')));
      expect(latin1.decode(bytes), isNot(contains('Synthetic Admin')));
      expect(latin1.decode(bytes), isNot(contains(dbKey)));
      expect(_contains(bytes, hexToBytes(dbKey)), isFalse);
      expect(latin1.decode(bytes), isNot(contains(backupKey.canonical)));
      expect(
        Directory('${a.dir.path}/work')
            .listSync()
            .where((f) => f.path.endsWith('.snapshot')),
        isEmpty,
      );
    }, timeout: _timeout);

    test('the phone keeps working after export, and export is audited',
        () async {
      final db = await a.open();
      final rows = await db.select(db.financialYears).get();
      final audit = await db.select(db.auditLog).get();
      await db.close();

      expect(rows.single.label, 'FY-MARKER-2025');
      expect(
        audit.map((r) => (jsonDecode(r.newValues!) as Map)['event']),
        containsAll([
          SecurityEventType.backupKeyCreated.name,
          SecurityEventType.backupExportCreated.name,
        ]),
      );
    }, timeout: _timeout);

    test('a database that is not encrypted is never exported', () async {
      final c = Phone('plain');
      addTearDown(c.delete);
      Directory(c.dbDir).createSync(recursive: true);
      // A plain (unencrypted) SQLite file where the database should be.
      final plain = sqlite3.sqlite3.open(c.dbFile.path);
      plain.execute('CREATE TABLE t (x TEXT); INSERT INTO t VALUES (\'PLAIN\');');
      plain.close();
      await c.backupKeys.write(BackupKeyMaterial.derive(backupKey));
      final db = openTestDatabase();
      addTearDown(db.close);
      await c.auth(db).setupBootstrapAdmin(displayName: 'Admin C', pin: _pin);

      await expectLater(
        c.service().createPackage(
          db,
          auth: c.auth(db),
          currentPin: _pin,
          audit: DatabaseSecurityAuditLog(db),
        ),
        throwsA(isA<PlaintextDatabaseException>()),
      );
      expect(
        Directory('${c.dir.path}/work').listSync(),
        isEmpty,
        reason: 'no package or snapshot left behind',
      );
    }, timeout: _timeout);

    test('export without a backup key set up is refused', () async {
      final c = Phone('c');
      addTearDown(c.delete);
      final db = await c.open();
      addTearDown(db.close);
      await c.auth(db).setupBootstrapAdmin(displayName: 'Admin C', pin: _pin);
      await expectLater(
        c.service().createPackage(
          db,
          auth: c.auth(db),
          currentPin: _pin,
          audit: DatabaseSecurityAuditLog(db),
        ),
        throwsA(isA<NoBackupKeyException>()),
      );
    }, timeout: _timeout);
  });

  group('I. import on a new phone', () {
    test('restores the same data; the new phone\'s own database and key are '
        'kept aside, not deleted; Admin access is then set with the backup '
        'key', () async {
      // Phone B was switched on once (first-run database and key exist).
      final fresh = await b.open();
      await fresh.select(fresh.users).get(); // first launch creates the file
      await fresh.close();
      final bOriginalDb = b.dbFile.readAsBytesSync();
      final bOriginalKey = b.dbKeys.values[databaseKeyStorageName]!;

      final verified = await b.service().verify(
        package,
        backupKey.formatted,
        context: RestoreContext.newDevice,
      );
      final outcome = await b.service().install(verified, confirmedByUser: true);

      // Nothing destroyed.
      final preserved = File('${b.dbDir}/${outcome.preservedDatabaseFileName}');
      expect(preserved.readAsBytesSync(), bOriginalDb);
      expect(
        b.dbKeys.values.entries
            .where((e) => e.key.startsWith('$databaseKeyStorageName.preserved.'))
            .map((e) => e.value),
        [bOriginalKey],
      );

      // Same data, opened with the recovered key.
      final db = await b.open();
      addTearDown(db.close);
      expect((await db.select(db.financialYears).get()).single.label, 'FY-MARKER-2025');
      expect((await db.select(db.users).get()).single.id, adminId);

      // Credentials never travel in a package: no Admin can log in yet…
      final auth = b.auth(db);
      expect(await auth.hasAdminAbleToLogIn(), isFalse);
      // …until Admin access is restored with the Backup Recovery Key.
      final restored = await auth.restoreAdminAccess(
        backupKey: backupKey.formatted,
        adminUserId: adminId,
        newPin: _newPin,
      );
      expect(restored.recoveryCode, startsWith('AR-'));
      expect((await auth.login(userId: adminId, pin: _newPin)).userId, adminId);
      expect(await auth.hasAdminAbleToLogIn(), isTrue);

      // The new phone can make backups with the same backup key.
      expect((await b.backupKeys.read())!.matches(backupKey), isTrue);
    }, timeout: _timeout);

    test('import requires explicit confirmation', () async {
      final verified = await b.service().verify(
        package,
        backupKey.formatted,
        context: RestoreContext.newDevice,
      );
      await expectLater(
        b.service().install(verified, confirmedByUser: false),
        throwsStateError,
      );
      expect(b.dbFile.existsSync(), isFalse);
      expect(b.dbKeys.values, isEmpty);
      await b.service().discard(verified);
      expect(File('${b.dbFile.path}.restore-staged').existsSync(), isFalse);
    }, timeout: _timeout);

    test('a tampered package is rejected before anything on the phone '
        'changes, and the rejection is audited', () async {
      final fresh = await b.open();
      await fresh.select(fresh.users).get(); // first launch creates the file
      await fresh.close();
      final before = b.dbFile.readAsBytesSync();
      final keyBefore = Map.of(b.dbKeys.values);

      final bytes = package.readAsBytesSync();
      bytes[bytes.length - 500] ^= 0xff;
      package.writeAsBytesSync(bytes);

      await expectLater(
        b.service().verify(package, backupKey.formatted, context: RestoreContext.newDevice),
        throwsA(
          isA<RecoveryPackageException>().having(
            (e) => e.reason,
            'reason',
            RecoveryPackageError.databaseIntegrityFailed,
          ),
        ),
      );
      expect(b.dbFile.readAsBytesSync(), before);
      expect(b.dbKeys.values, keyBefore);
      expect(File('${b.dbFile.path}.restore-staged').existsSync(), isFalse);
      final journal = b.journalFile.readAsStringSync();
      expect(journal, contains(SecurityEventType.backupImportRejected.name));
    }, timeout: _timeout);

    test('the wrong backup key is identified and nothing changes', () async {
      await expectLater(
        b.service().verify(
          package,
          SecretCode.generate(SecretCodeKind.backupRecovery).formatted,
          context: RestoreContext.newDevice,
        ),
        throwsA(
          isA<RecoveryPackageException>().having(
            (e) => e.reason,
            'reason',
            RecoveryPackageError.differentBackupKey,
          ),
        ),
      );
      expect(b.dbFile.existsSync(), isFalse);
      expect(b.dbKeys.values, isEmpty);
    }, timeout: _timeout);

    test('a file that is not a package is rejected', () async {
      final junk = File('${b.dir.path}/junk.rbskrp')
        ..writeAsBytesSync(secureRandomBytes(4096));
      await expectLater(
        b.service().verify(junk, backupKey.formatted, context: RestoreContext.newDevice),
        throwsA(isA<RecoveryPackageException>()),
      );
    }, timeout: _timeout);

    test('restoring Admin access is refused while an Admin can log in, and a '
        'wrong backup key is rejected', () async {
      final verified = await b.service().verify(
        package,
        backupKey.formatted,
        context: RestoreContext.newDevice,
      );
      await b.service().install(verified, confirmedByUser: true);
      final db = await b.open();
      addTearDown(db.close);
      final auth = b.auth(db);

      await expectLater(
        auth.restoreAdminAccess(
          backupKey: SecretCode.generate(SecretCodeKind.backupRecovery).formatted,
          adminUserId: adminId,
          newPin: _newPin,
        ),
        throwsA(isA<InvalidBackupKeyFailure>()),
      );
      await auth.restoreAdminAccess(
        backupKey: backupKey.formatted,
        adminUserId: adminId,
        newPin: _newPin,
      );
      await expectLater(
        auth.restoreAdminAccess(
          backupKey: backupKey.formatted,
          adminUserId: adminId,
          newPin: '111111',
        ),
        throwsA(isA<AdminAccessRestoreNotAllowedFailure>()),
      );
    }, timeout: _timeout);
  });

  group('database recovery on the same phone (key unavailable)', () {
    test('a phone that lost its database key opens its data again from a '
        'package; the locked file is kept', () async {
      a.dbKeys.values.clear(); // the key is gone
      final lockedBytes = a.dbFile.readAsBytesSync();
      await expectLater(
        a.open(),
        throwsA(isA<DatabaseKeyUnavailableException>()),
      );

      final verified = await a.service().verify(
        package,
        backupKey.formatted,
        context: RestoreContext.keyUnavailable,
      );
      final outcome = await a.service().install(verified, confirmedByUser: true);

      expect(
        File('${a.dbDir}/${outcome.preservedDatabaseFileName}').readAsBytesSync(),
        lockedBytes,
      );
      final db = await a.open();
      await DatabaseSecurityAuditLog(db).flushPending(a.journal);
      final labels = (await db.select(db.financialYears).get()).map((r) => r.label);
      final events = (await db.select(db.auditLog).get())
          .map((r) => (jsonDecode(r.newValues!) as Map)['event'])
          .toList();
      await db.close();

      expect(labels, ['FY-MARKER-2025']);
      expect(events, containsAll([
        SecurityEventType.databaseRecoveryAttempted.name,
        SecurityEventType.databaseRecoverySucceeded.name,
      ]));
      expect(a.journalFile.existsSync(), isFalse, reason: 'journal flushed');
    }, timeout: _timeout);
  });

  test('K. the journal and audit log never contain the backup key, the '
      'database key or a PIN', () async {
    final verified = await b.service().verify(
      package,
      backupKey.formatted,
      context: RestoreContext.newDevice,
    );
    await b.service().install(verified, confirmedByUser: true);
    final journal = b.journalFile.readAsStringSync();
    final db = await b.open();
    await DatabaseSecurityAuditLog(db).flushPending(b.journal);
    final audit = jsonEncode([
      for (final r in await db.select(db.auditLog).get()) r.toJson(),
    ]);
    await db.close();

    final dbKey = b.dbKeys.values[databaseKeyStorageName]!;
    for (final text in [journal, audit]) {
      expect(text, isNot(contains(backupKey.canonical)));
      expect(text, isNot(contains(backupKey.formatted)));
      expect(text, isNot(contains(dbKey)));
      expect(text, isNot(contains(_pin)));
      expect(text, isNot(contains(b.dir.path)));
    }
  }, timeout: _timeout);
}
