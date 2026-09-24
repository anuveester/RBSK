import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/security/crypto_utils.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/recovery/database_recovery_service.dart';
import 'package:referredline/data/local/recovery/recovery_package.dart';
import 'package:referredline/data/local/seed/seed_runner.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../../support/phone_fixture.dart';
import '../test_database.dart';

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

/// Creates the schema on [phone] (a first launch) and returns the key.
Future<String> _firstLaunch(Phone phone) async {
  final db = await phone.open();
  await db.select(db.financialYears).get(); // creates the file and schema
  await db.close();
  return phone.dbKeys.values[databaseKeyStorageName]!;
}

/// Inserts one placeholder row into [table] with raw SQL, filling every
/// NOT NULL column that has no default. Foreign keys and CHECK constraints
/// are off, so any single table can be given a row on its own.
void _insertPlaceholderRow(File file, String key, String table) {
  final db = sqlite3.sqlite3.open(file.path);
  try {
    db.execute("PRAGMA key = '${escapeForSqlLiteral(key)}';");
    db.execute('PRAGMA foreign_keys = OFF;');
    db.execute('PRAGMA ignore_check_constraints = ON;');
    final names = <String>[];
    final values = <Object?>[];
    for (final col in db.select('PRAGMA table_info("$table")')) {
      final required = col['notnull'] == 1 && col['dflt_value'] == null;
      if (!required && col['pk'] == 0) {
        continue;
      }
      final type = '${col['type']}'.toUpperCase();
      names.add('"${col['name']}"');
      values.add(
        type.contains('INT')
            ? 1
            : type.contains('REAL')
            ? 1.0
            : 'placeholder-${col['name']}',
      );
    }
    db.execute(
      'INSERT INTO "$table" (${names.join(', ')}) '
      'VALUES (${List.filled(names.length, '?').join(', ')})',
      values,
    );
  } finally {
    db.close();
  }
}

void main() {
  late Phone a;
  late Phone b;
  late SecretCode backupKey;
  late File package;

  // Phone A as a real phone would be: reference data, some business data
  // (a school), and a Backup Recovery Key.
  setUp(() async {
    a = Phone('a');
    b = Phone('b');

    final db = await a.open();
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
    await Seeds(db).school(name: 'SCHOOL-MARKER');
    backupKey = await a.service().createBackupKey(
      audit: DatabaseSecurityAuditLog(db),
    );
    final made = await a.service().createPackage(
      db,
      audit: DatabaseSecurityAuditLog(db),
    );
    await db.close();
    package = await made.copy('${a.dir.path}/package.rbskrp');
  });

  tearDown(() {
    a.delete();
    b.delete();
  });

  group('export', () {
    test('produces an encrypted package: no plaintext database content, no '
        'plaintext database key, no backup key; nothing left in the work '
        'folder but the package', () async {
      final bytes = package.readAsBytesSync();
      final text = latin1.decode(bytes);
      final dbKey = a.dbKeys.values[databaseKeyStorageName]!;

      expect(text, isNot(contains('SQLite format 3')));
      expect(text, isNot(contains('FY-MARKER-2025')));
      expect(text, isNot(contains('SCHOOL-MARKER')));
      expect(text, isNot(contains(dbKey)));
      expect(_contains(bytes, hexToBytes(dbKey)), isFalse);
      expect(text, isNot(contains(backupKey.canonical)));
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
      final schools = await db.select(db.schools).get();
      final audit = await db.select(db.auditLog).get();
      await db.close();

      expect(schools.single.name, 'SCHOOL-MARKER');
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
      final plain = sqlite3.sqlite3.open(c.dbFile.path);
      plain.execute("CREATE TABLE t (x TEXT); INSERT INTO t VALUES ('PLAIN');");
      plain.close();
      await c.backupKeys.write(BackupKeyMaterial.derive(backupKey));
      final db = openTestDatabase();
      addTearDown(db.close);

      await expectLater(
        c.service().createPackage(db, audit: DatabaseSecurityAuditLog(db)),
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
      await expectLater(
        c.service().createPackage(db, audit: DatabaseSecurityAuditLog(db)),
        throwsA(isA<NoBackupKeyException>()),
      );
    }, timeout: _timeout);

    test('no space for the package: export fails at once (it does not hang) '
        'and leaves nothing behind', () async {
      final db = await a.open();
      addTearDown(db.close);
      // Stand-in for a full disk: the package file cannot be created.
      Directory(
        '${a.dir.path}/work/rbsk-recovery-20260924-120000.rbskrp',
      ).createSync(recursive: true);

      await expectLater(
        a
            .service(clock: () => DateTime.utc(2026, 9, 24, 12))
            .createPackage(db, audit: DatabaseSecurityAuditLog(db)),
        throwsA(isA<FileSystemException>()),
      ).timeout(const Duration(seconds: 30));
      expect(
        Directory('${a.dir.path}/work')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.snapshot')),
        isEmpty,
      );
    }, timeout: _timeout);
  });

  group('import on a new phone', () {
    test('restores the same data; the new phone\'s own database and key are '
        'kept aside, not deleted; the backup key material comes along',
        () async {
      await _firstLaunch(b);
      final bOriginalDb = b.dbFile.readAsBytesSync();
      final bOriginalKey = b.dbKeys.values[databaseKeyStorageName]!;

      final verified = await b.service().verify(
        package,
        backupKey.formatted,
        context: RestoreContext.newDevice,
      );
      final outcome = await b.service().install(verified, confirmedByUser: true);

      final preserved = File('${b.dbDir}/${outcome.preservedDatabaseFileName}');
      expect(preserved.readAsBytesSync(), bOriginalDb);
      expect(
        b.dbKeys.values.entries
            .where((e) => e.key.startsWith('$databaseKeyStorageName.preserved.'))
            .map((e) => e.value),
        [bOriginalKey],
      );

      final db = await b.open();
      addTearDown(db.close);
      expect((await db.select(db.schools).get()).single.name, 'SCHOOL-MARKER');
      expect(
        (await db.select(db.financialYears).get()).single.label,
        'FY-MARKER-2025',
      );
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
      await _firstLaunch(b);
      final before = b.dbFile.readAsBytesSync();
      final keyBefore = Map.of(b.dbKeys.values);

      final bytes = package.readAsBytesSync();
      bytes[bytes.length - 500] ^= 0xff;
      package.writeAsBytesSync(bytes);

      await expectLater(
        b.service().verify(
          package,
          backupKey.formatted,
          context: RestoreContext.newDevice,
        ),
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
      expect(
        b.journalFile.readAsStringSync(),
        contains(SecurityEventType.backupImportRejected.name),
      );
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
        b.service().verify(
          junk,
          backupKey.formatted,
          context: RestoreContext.newDevice,
        ),
        throwsA(isA<RecoveryPackageException>()),
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
      final schools = (await db.select(db.schools).get()).map((r) => r.name);
      final events = (await db.select(db.auditLog).get())
          .map((r) => (jsonDecode(r.newValues!) as Map)['event'])
          .toList();
      await db.close();

      expect(schools, ['SCHOOL-MARKER']);
      expect(
        events,
        containsAll([
          SecurityEventType.databaseRecoveryAttempted.name,
          SecurityEventType.databaseRecoverySucceeded.name,
        ]),
      );
      expect(a.journalFile.existsSync(), isFalse, reason: 'journal flushed');
    }, timeout: _timeout);
  });

  group('restore safety rule: business data in use', () {
    test('the rule classifies every table of the frozen schema exactly once',
        () {
      final db = openTestDatabase();
      addTearDown(db.close);
      final schema = db.allTables.map((t) => t.actualTableName).toSet();
      final blocking = restoreBlockingTables.toSet();
      final nonBlocking = restoreNonBlockingTables.toSet();

      expect(schema, hasLength(28));
      expect(blocking, hasLength(17));
      expect(nonBlocking, hasLength(11));
      expect(blocking.intersection(nonBlocking), isEmpty);
      expect(blocking.union(nonBlocking), schema);
    });

    for (final table in [
      ...restoreBlockingTables,
      ...restoreNonBlockingTables,
    ]) {
      final blocks = restoreBlockingTables.contains(table);
      test('one row only in "$table" ${blocks ? 'blocks' : 'does not block'} '
          'a restore', () async {
        final c = Phone('rule');
        addTearDown(c.delete);
        final key = await _firstLaunch(c);
        _insertPlaceholderRow(c.dbFile, key, table);
        final before = c.dbFile.readAsBytesSync();

        final attempt = c.service().verify(
          package,
          backupKey.formatted,
          context: RestoreContext.newDevice,
        );
        if (blocks) {
          await expectLater(attempt, throwsA(isA<DatabaseInUseException>()));
          expect(c.dbFile.readAsBytesSync(), before);
          expect(File('${c.dbFile.path}.restore-staged').existsSync(), isFalse);
          expect(c.journalFile.readAsStringSync(), contains('databaseInUse'));
        } else {
          await c.service().discard(await attempt);
        }
      }, timeout: _timeout);
    }

    test('a soft-deleted business row still blocks a restore', () async {
      final c = Phone('deleted');
      addTearDown(c.delete);
      final db = await c.open();
      await Seeds(db).school();
      await (db.update(db.schools)..where((t) => t.id.equals('school-1')))
          .write(const SchoolsCompanion(isDeleted: Value(true)));
      await db.close();

      await expectLater(
        c.service().verify(
          package,
          backupKey.formatted,
          context: RestoreContext.newDevice,
        ),
        throwsA(isA<DatabaseInUseException>()),
      );
    }, timeout: _timeout);

    test('a phone set up with all reference data, a user and audit rows (no '
        'business data) can still be restored', () async {
      final c = Phone('seeded');
      addTearDown(c.delete);
      final db = await c.open();
      await SeedRunner(db).seedAll();
      await Seeds(db).user();
      await DatabaseSecurityAuditLog(db).record(
        SecurityEvent(SecurityEventType.backupKeyCreated),
      );
      await db.close();

      final verified = await c.service().verify(
        package,
        backupKey.formatted,
        context: RestoreContext.newDevice,
      );
      await c.service().install(verified, confirmedByUser: true);
      final restored = await c.open();
      addTearDown(restored.close);
      expect(
        (await restored.select(restored.schools).get()).single.name,
        'SCHOOL-MARKER',
      );
    }, timeout: _timeout);

    test('install checks again: business data added after verify blocks the '
        'install, and nothing is replaced', () async {
      await _firstLaunch(b);
      final verified = await b.service().verify(
        package,
        backupKey.formatted,
        context: RestoreContext.newDevice,
      );
      final db = await b.open();
      await Seeds(db).school(name: 'B-SCHOOL');
      await db.close();
      final before = b.dbFile.readAsBytesSync();

      await expectLater(
        b.service().install(verified, confirmedByUser: true),
        throwsA(isA<DatabaseInUseException>()),
      );
      expect(b.dbFile.readAsBytesSync(), before);
      expect(File('${b.dbFile.path}.restore-staged').existsSync(), isFalse);
      final reopened = await b.open();
      expect(
        (await reopened.select(reopened.schools).get()).single.name,
        'B-SCHOOL',
      );
      await reopened.close();
    }, timeout: _timeout);

    test('locked data (key lost) may be restored even though it holds '
        'business data', () async {
      a.dbKeys.values.clear();
      final verified = await a.service().verify(
        package,
        backupKey.formatted,
        context: RestoreContext.keyUnavailable,
      );
      await a.service().install(verified, confirmedByUser: true);
      final db = await a.open();
      addTearDown(db.close);
      expect((await db.select(db.schools).get()).single.name, 'SCHOOL-MARKER');
    }, timeout: _timeout);
  });

  test('the journal and audit log never contain the backup key, the '
      'database key or a file path', () async {
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
      expect(text, isNot(contains(b.dir.path)));
    }
  }, timeout: _timeout);
}
