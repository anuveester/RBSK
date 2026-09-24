import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/database_connection.dart';

import '../../support/in_memory_secure_key_store.dart';

const _realDisk = Timeout(Duration(minutes: 2));

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('rbsk_failsafe_'));
  tearDown(() => dir.deleteSync(recursive: true));

  File dbFile() => File('${dir.path}/$databaseFileName');

  Future<AppDatabase> open(DatabaseKeyManager manager) async => AppDatabase(
    await openEncryptedDatabase(
      keyManager: manager,
      overrideDirectoryPath: dir.path,
      overrideTempDirectoryPath: dir.path,
    ),
  );

  /// Creates a database with one row, as a real phone would have it.
  Future<InMemorySecureKeyStore> createExistingDatabase() async {
    final store = InMemorySecureKeyStore();
    final db = await open(DatabaseKeyManager(store: store));
    await db
        .into(db.financialYears)
        .insert(
          FinancialYearsCompanion.insert(
            id: 'fy-1',
            label: '2025-26',
            startDate: DateTime.utc(2025, 4, 1),
            endDate: DateTime.utc(2026, 3, 31),
          ),
        );
    await db.close();
    return store;
  }

  Matcher unavailable(DatabaseKeyUnavailableReason reason) => throwsA(
    isA<DatabaseKeyUnavailableException>().having(
      (e) => e.reason,
      'reason',
      reason,
    ),
  );

  test('A. first installation: no database, no key — a key is created and '
      'the database opens', () async {
    final store = InMemorySecureKeyStore();
    final db = await open(DatabaseKeyManager(store: store));
    await db.select(db.financialYears).get();
    await db.close();

    expect(isWellFormedDatabaseKey(store.values[databaseKeyStorageName]), isTrue);
    expect(dbFile().existsSync(), isTrue);
  }, timeout: _realDisk);

  test('B. existing database + missing key: no new key, database not '
      'deleted or changed, recovery-required error', () async {
    await createExistingDatabase();
    final before = dbFile().readAsBytesSync();
    final emptyStore = InMemorySecureKeyStore();

    await expectLater(
      open(DatabaseKeyManager(store: emptyStore)),
      unavailable(DatabaseKeyUnavailableReason.keyMissingForExistingDatabase),
    );

    expect(emptyStore.values, isEmpty, reason: 'no replacement key generated');
    expect(emptyStore.writeCount, 0);
    expect(dbFile().readAsBytesSync(), before, reason: 'database untouched');
  }, timeout: _realDisk);

  test('C. existing database + secure storage that cannot be decrypted: no '
      'deletion, no new key, no data destruction', () async {
    final store = await createExistingDatabase();
    final before = dbFile().readAsBytesSync();
    final keyBefore = store.values[databaseKeyStorageName];
    store.failReads = true;

    await expectLater(
      open(DatabaseKeyManager(store: store)),
      unavailable(DatabaseKeyUnavailableReason.secureStorageUnreadable),
    );

    expect(store.writeCount, 1, reason: 'only the original first-run write');
    expect(store.values[databaseKeyStorageName], keyBefore);
    expect(dbFile().readAsBytesSync(), before);

    // Once storage reads again, the same data opens — nothing was lost.
    store.failReads = false;
    final db = await open(DatabaseKeyManager(store: store));
    expect(await db.select(db.financialYears).get(), hasLength(1));
    await db.close();
  }, timeout: _realDisk);

  test('C2. a missing key is never resolved as first launch even when the '
      'storage also fails on write', () async {
    await createExistingDatabase();
    final store = InMemorySecureKeyStore()..failWritesWhere = (_) => true;

    await expectLater(
      open(DatabaseKeyManager(store: store)),
      unavailable(DatabaseKeyUnavailableReason.keyMissingForExistingDatabase),
    );
    expect(dbFile().existsSync(), isTrue);
  }, timeout: _realDisk);

  test('a stored key that does not open the database is reported, not '
      'replaced', () async {
    await createExistingDatabase();
    final before = dbFile().readAsBytesSync();
    final store = InMemorySecureKeyStore();
    final wrong = generatePassphrase();
    store.values[databaseKeyStorageName] = wrong;

    await expectLater(
      open(DatabaseKeyManager(store: store)),
      unavailable(DatabaseKeyUnavailableReason.keyDoesNotOpenDatabase),
    );
    expect(store.values[databaseKeyStorageName], wrong);
    expect(dbFile().readAsBytesSync(), before);
  }, timeout: _realDisk);

  test('a first-run key that cannot be saved stops the open: no database is '
      'created with an unsaved key', () async {
    final store = InMemorySecureKeyStore()..failWritesWhere = (_) => true;

    await expectLater(
      open(DatabaseKeyManager(store: store)),
      unavailable(DatabaseKeyUnavailableReason.keyCouldNotBeSaved),
    );
    expect(dbFile().existsSync(), isFalse);
  });

  test('a key kept in the old (Phase 1.2–1.4) location is carried into the '
      'isolated store, and the old copy is kept', () async {
    final legacy = await createExistingDatabase();
    final key = legacy.values[databaseKeyStorageName]!;
    final isolated = InMemorySecureKeyStore();

    final db = await open(DatabaseKeyManager(store: isolated, legacyStore: legacy));
    expect(await db.select(db.financialYears).get(), hasLength(1));
    await db.close();

    expect(isolated.values[databaseKeyStorageName], key);
    expect(legacy.values[databaseKeyStorageName], key, reason: 'not removed');
  }, timeout: _realDisk);

  test('installing a recovered key keeps the previous key under another name',
      () async {
    final store = InMemorySecureKeyStore();
    final manager = DatabaseKeyManager(store: store);
    final original = await manager.resolveKey(databaseFileExists: false);
    final recovered = generatePassphrase();

    await manager.installRecoveredKey(recovered);

    expect(store.values[databaseKeyStorageName], recovered);
    final preserved = store.values.entries
        .where((e) => e.key.startsWith('$databaseKeyStorageName.preserved.'))
        .map((e) => e.value);
    expect(preserved, [original]);
  });

  test('overlapping first-launch resolutions agree on one key', () async {
    final store = InMemorySecureKeyStore();
    final keys = await Future.wait([
      for (var i = 0; i < 5; i++)
        DatabaseKeyManager(store: store).resolveKey(databaseFileExists: false),
    ]);

    expect(keys.toSet(), hasLength(1));
    expect(store.values[databaseKeyStorageName], keys.first);
    expect(
      store.values.keys.where((k) => k.contains('.preserved.')),
      isEmpty,
      reason: 'no competing key was ever generated',
    );
  });

  test('a malformed recovered key is refused and nothing is written', () async {
    final store = InMemorySecureKeyStore();
    final manager = DatabaseKeyManager(store: store);

    await expectLater(manager.installRecoveredKey('not-a-key'), throwsArgumentError);
    expect(store.values, isEmpty);
  });

  test('error text never contains key material', () async {
    await createExistingDatabase();
    final store = InMemorySecureKeyStore();
    final wrong = generatePassphrase();
    store.values[databaseKeyStorageName] = wrong;
    try {
      await open(DatabaseKeyManager(store: store));
      fail('expected an exception');
    } on DatabaseKeyUnavailableException catch (e) {
      expect(e.toString(), isNot(contains(wrong)));
    }
  }, timeout: _realDisk);
}
