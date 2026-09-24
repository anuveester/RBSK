import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// In-memory stand-in for Android Keystore-backed storage, so
/// [DatabaseKeyManager] is testable without a platform channel.
class _InMemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

void main() {
  group('generatePassphrase', () {
    test('produces 256 bits (64 hex characters)', () {
      expect(generatePassphrase().length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(generatePassphrase()), isTrue);
    });

    test('is not deterministic — repeated calls differ', () {
      final values = List.generate(20, (_) => generatePassphrase());
      expect(values.toSet().length, 20, reason: 'no two calls should collide');
    });
  });

  group('escapeForSqlLiteral', () {
    test('doubles embedded single quotes', () {
      expect(escapeForSqlLiteral("it's"), "it''s");
    });

    test('leaves a quote-free string untouched', () {
      expect(escapeForSqlLiteral('abc123'), 'abc123');
    });

    test(
      'a malicious value embeds as ONE inert string literal, not '
      'executable SQL — behavioral proof, not a substring check',
      () {
        const malicious = "x'; DROP TABLE schools; --";
        final db = sqlite3.sqlite3.openInMemory();
        addTearDown(db.close);
        db.execute('CREATE TABLE schools (id INTEGER)');
        db.execute('INSERT INTO schools VALUES (1)');

        final escaped = escapeForSqlLiteral(malicious);
        // If escaping failed, this statement would either throw a syntax
        // error (unterminated string) or silently execute the DROP TABLE.
        final result =
            db.select("SELECT '$escaped' AS value");

        // The table must still exist and the literal must round-trip
        // byte-for-byte as a single opaque value.
        expect(result.single['value'], malicious);
        expect(
          db.select('SELECT count(*) AS c FROM schools').single['c'],
          1,
        );
      },
    );
  });

  group('DatabaseKeyManager', () {
    // API changed at security hardening: getOrCreateKey() became
    // resolveKey(databaseFileExists:) so a missing key is never mistaken
    // for a first launch. These are the original assertions, for the
    // first-run case (no database file yet).
    test('generates a key on first use and persists it', () async {
      final store = _InMemorySecureKeyStore();
      final manager = DatabaseKeyManager(store: store);

      final key = await manager.resolveKey(databaseFileExists: false);

      expect(key, isNotEmpty);
      expect(await store.read('rbsk_db_encryption_key_v1'), key);
    });

    test('returns the SAME key on every subsequent call', () async {
      final store = _InMemorySecureKeyStore();
      final manager = DatabaseKeyManager(store: store);

      final first = await manager.resolveKey(databaseFileExists: false);
      final second = await manager.resolveKey(databaseFileExists: true);
      final third = await manager.resolveKey(databaseFileExists: true);

      expect(second, first);
      expect(third, first);
    });

    test('two independent stores get two different keys', () async {
      final managerA = DatabaseKeyManager(store: _InMemorySecureKeyStore());
      final managerB = DatabaseKeyManager(store: _InMemorySecureKeyStore());

      expect(
        await managerA.resolveKey(databaseFileExists: false),
        isNot(await managerB.resolveKey(databaseFileExists: false)),
      );
    });
  });

  // Real-disk tests: each encrypted open creates all 28 tables on disk, so
  // runtime depends on disk/antivirus activity rather than the code. The
  // wrong-key test was observed at 1–9s on a12227d and 0–24s on the Phase
  // 1.4 branch, with its code path unchanged, and exceeded the default 30s
  // once under a full parallel run. Timeout only — assertions unchanged.
  const realDiskTimeout = Timeout(Duration(minutes: 2));

  group('openEncryptedDatabase — real encrypted file on disk', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('rbsk_db_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
      'data written with the correct key round-trips after reopening',
      () async {
        final store = _InMemorySecureKeyStore();

        final executor1 = await openEncryptedDatabase(
          keyManager: DatabaseKeyManager(store: store),
          overrideDirectoryPath: tempDir.path,
          overrideTempDirectoryPath: tempDir.path,
        );
        final db1 = AppDatabase(executor1);
        await db1.into(db1.financialYears).insert(
              FinancialYearsCompanion.insert(
                id: 'fy-1',
                label: '2025-26',
                startDate: DateTime.utc(2025, 4, 1),
                endDate: DateTime.utc(2026, 3, 31),
              ),
            );
        await db1.close();

        // Reopen the SAME file with the SAME (persisted) key.
        final executor2 = await openEncryptedDatabase(
          keyManager: DatabaseKeyManager(store: store),
          overrideDirectoryPath: tempDir.path,
          overrideTempDirectoryPath: tempDir.path,
        );
        final db2 = AppDatabase(executor2);
        final rows = await db2.select(db2.financialYears).get();
        await db2.close();

        expect(rows, hasLength(1));
        expect(rows.single.label, '2025-26');
      },
      timeout: realDiskTimeout,
    );

    test(
      'the same file CANNOT be read back with the wrong key — proves '
      'encryption is actually active, not a no-op',
      () async {
        final correctKeyStore = _InMemorySecureKeyStore();
        final executor1 = await openEncryptedDatabase(
          keyManager: DatabaseKeyManager(store: correctKeyStore),
          overrideDirectoryPath: tempDir.path,
          overrideTempDirectoryPath: tempDir.path,
        );
        final db1 = AppDatabase(executor1);
        await db1.into(db1.financialYears).insert(
              FinancialYearsCompanion.insert(
                id: 'fy-1',
                label: '2025-26',
                startDate: DateTime.utc(2025, 4, 1),
                endDate: DateTime.utc(2026, 3, 31),
              ),
            );
        await db1.close();

        final file = File('${tempDir.path}/rbsk_referred_line.sqlite');
        final before = file.readAsBytesSync();
        // The raw file is not plaintext SQLite: no standard header, and the
        // stored label is not readable in it.
        expect(String.fromCharCodes(before.sublist(0, 15)), isNot('SQLite format 3'));
        expect(String.fromCharCodes(before), isNot(contains('2025-26')));

        // A key manager holding an UNRELATED key — a different device or a
        // corrupted store. Since security hardening the wrong key is caught
        // before the database is used at all (it used to fail on the first
        // query), and nothing is created or replaced.
        final wrongKeyStore = _InMemorySecureKeyStore();
        await wrongKeyStore.write('rbsk_db_encryption_key_v1', generatePassphrase());
        final wrongKey = await wrongKeyStore.read('rbsk_db_encryption_key_v1');

        await expectLater(
          openEncryptedDatabase(
            keyManager: DatabaseKeyManager(store: wrongKeyStore),
            overrideDirectoryPath: tempDir.path,
            overrideTempDirectoryPath: tempDir.path,
          ),
          throwsA(
            isA<DatabaseKeyUnavailableException>().having(
              (e) => e.reason,
              'reason',
              DatabaseKeyUnavailableReason.keyDoesNotOpenDatabase,
            ),
          ),
        );
        expect(keyOpensDatabase(file, wrongKey!), isFalse);
        expect(file.readAsBytesSync(), before, reason: 'file untouched');
        expect(
          await wrongKeyStore.read('rbsk_db_encryption_key_v1'),
          wrongKey,
          reason: 'no key replaced',
        );
      },
      timeout: realDiskTimeout,
    );
  });
}
