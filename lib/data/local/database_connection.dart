import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Encryption / key-management for the local database
/// (docs/08_SECURITY_ARCHITECTURE.md §Data at rest, docs/24_PHASE_1_2_REPORT.md
/// §Encryption approach).
///
/// The `sqlcipher_flutter_libs` package named in that document is end-of-life
/// (see docs/24_PHASE_1_2_REPORT.md §Deviations). This implements the current
/// Drift-recommended replacement instead: the `sqlite3` package's native
/// SQLite3MultipleCiphers build (selected via the `hooks.user_defines` block
/// in pubspec.yaml), which is SQLCipher-compatible — same `PRAGMA key`
/// mechanism, same cipher — and actively maintained.
const String databaseFileName = 'rbsk_referred_line.sqlite';
const String databaseKeyStorageName = 'rbsk_db_encryption_key_v1';

/// Thin abstraction over "a place that securely persists strings", so key
/// handling is unit-testable without platform channels. The only
/// production implementation is [FlutterSecureStorageKeyStore]
/// (Android Keystore-backed); tests substitute an in-memory fake.
///
/// Implementations must throw [SecureStorageUnavailableException] when the
/// platform store cannot be read or written — never return `null` for a
/// value that exists but can't be decrypted.
abstract interface class SecureKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// The platform secure store could not be read or written. Carries no key
/// names' values and no secret material.
class SecureStorageUnavailableException implements Exception {
  const SecureStorageUnavailableException(this.operation);

  final String operation;

  @override
  String toString() => 'SecureStorageUnavailableException($operation)';
}

class FlutterSecureStorageKeyStore implements SecureKeyStore {
  const FlutterSecureStorageKeyStore._(this._storage);

  /// The default-namespace store: the Backup Recovery Key material (derived,
  /// never the key itself) and restore rollback points, plus the database
  /// key as earlier builds stored it, which [DatabaseKeyManager] only reads
  /// to carry it forward.
  ///
  /// `resetOnError: false` is deliberate. The library's default (`true`)
  /// deletes every entry it cannot decrypt (`deleteAllDataAndKeys`), which
  /// could silently destroy a key. An unreadable store surfaces as
  /// [SecureStorageUnavailableException] instead.
  const FlutterSecureStorageKeyStore.general()
    : this._(
        const FlutterSecureStorage(
          aOptions: AndroidOptions(resetOnError: false),
        ),
      );

  /// The database encryption key only. `storageNamespace` gives it its own
  /// SharedPreferences files and its own Android Keystore alias, so nothing
  /// done to the general store — by this app or by the library's error
  /// handling — can reach it. `resetOnError: false` for the same reason as
  /// above.
  const FlutterSecureStorageKeyStore.databaseKey()
    : this._(
        const FlutterSecureStorage(
          aOptions: AndroidOptions(
            resetOnError: false,
            storageNamespace: 'rbsk_database_key',
          ),
        ),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException {
      throw const SecureStorageUnavailableException('read');
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException {
      throw const SecureStorageUnavailableException('write');
    }
  }
}

/// Why the database key could not be used. Deliberately coarse: none of these
/// carry key material.
enum DatabaseKeyUnavailableReason {
  /// The secure store holding the key could not be read.
  secureStorageUnreadable,

  /// An encrypted database exists, but no key is stored for it.
  keyMissingForExistingDatabase,

  /// A key is stored, but it does not open the existing database.
  keyDoesNotOpenDatabase,

  /// A new or recovered key could not be saved and read back.
  keyCouldNotBeSaved,
}

/// The existing encrypted database cannot be opened. The database file and
/// every stored key are left exactly as they were: nothing was deleted or
/// replaced. A restore from a recovery package is the way back.
class DatabaseKeyUnavailableException implements Exception {
  const DatabaseKeyUnavailableException(this.reason);

  final DatabaseKeyUnavailableReason reason;

  @override
  String toString() => 'DatabaseKeyUnavailableException(${reason.name})';
}

final RegExp _keyFormat = RegExp(r'^[0-9a-f]{64}$');

bool isWellFormedDatabaseKey(String? value) =>
    value != null && _keyFormat.hasMatch(value);

/// Resolves the database encryption key without ever destroying one.
///
/// A key is generated **only** when no database file exists (a genuine first
/// run). A missing or unreadable key for an existing database is an explicit
/// [DatabaseKeyUnavailableException] — never treated as a first launch, never
/// answered by generating a replacement key.
class DatabaseKeyManager {
  DatabaseKeyManager({SecureKeyStore? store, SecureKeyStore? legacyStore})
    : _store = store ?? const FlutterSecureStorageKeyStore.databaseKey(),
      _legacyStore =
          legacyStore ??
          (store == null ? const FlutterSecureStorageKeyStore.general() : null);

  final SecureKeyStore _store;

  /// Where earlier builds stored the key (the default-namespace store). Read
  /// only, to carry an existing key forward; never written or cleared.
  final SecureKeyStore? _legacyStore;

  /// Serializes key resolution within the process: two overlapping opens on
  /// a first launch must agree on one key, not each generate their own.
  static Future<void> _serial = Future<void>.value();

  Future<String> resolveKey({required bool databaseFileExists}) {
    final result = _serial.then(
      (_) => _resolveKey(databaseFileExists: databaseFileExists),
    );
    _serial = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<String> _resolveKey({required bool databaseFileExists}) async {
    final existing = await _readKey();
    if (existing != null) {
      return existing;
    }
    if (databaseFileExists) {
      throw const DatabaseKeyUnavailableException(
        DatabaseKeyUnavailableReason.keyMissingForExistingDatabase,
      );
    }
    final generated = generatePassphrase();
    await _writeVerified(generated);
    return generated;
  }

  /// Installs a key taken from a verified recovery package. A different key
  /// already stored is preserved under a separate name, never discarded.
  Future<void> installRecoveredKey(String key) async {
    if (!isWellFormedDatabaseKey(key)) {
      throw ArgumentError('Recovered key has an unexpected format.');
    }
    await _writeVerified(key);
  }

  /// The key that opens the current database, if one is stored. Reads only:
  /// never generates, migrates or writes a key. Throws
  /// [DatabaseKeyUnavailableException] if the store can't be read.
  Future<String?> readCurrentKey() async {
    try {
      final current = await _store.read(databaseKeyStorageName);
      if (isWellFormedDatabaseKey(current)) {
        return current;
      }
      final legacy = await _legacyStore?.read(databaseKeyStorageName);
      return isWellFormedDatabaseKey(legacy) ? legacy : null;
    } on SecureStorageUnavailableException {
      throw const DatabaseKeyUnavailableException(
        DatabaseKeyUnavailableReason.secureStorageUnreadable,
      );
    }
  }

  static const String _rollbackSlot = '$databaseKeyStorageName.restore-rollback';
  static const String _noKey = '-';

  /// Before a restore: remembers exactly what is stored now (including
  /// "nothing"), so [rollBackToSavedPoint] can put it back.
  Future<void> saveRollbackPoint() async {
    try {
      final current = await _store.read(databaseKeyStorageName);
      final value = (current == null || current.isEmpty) ? _noKey : current;
      await _store.write(_rollbackSlot, value);
      if (await _store.read(_rollbackSlot) != value) {
        throw const DatabaseKeyUnavailableException(
          DatabaseKeyUnavailableReason.keyCouldNotBeSaved,
        );
      }
    } on SecureStorageUnavailableException {
      throw const DatabaseKeyUnavailableException(
        DatabaseKeyUnavailableReason.keyCouldNotBeSaved,
      );
    }
  }

  /// Undoes a restore's key change. The restored key is not discarded: it
  /// is preserved like any other replaced key. Does nothing if no rollback
  /// point was saved.
  Future<void> rollBackToSavedPoint() async {
    final String? saved;
    final String? current;
    try {
      saved = await _store.read(_rollbackSlot);
      current = await _store.read(databaseKeyStorageName);
    } on SecureStorageUnavailableException {
      throw const DatabaseKeyUnavailableException(
        DatabaseKeyUnavailableReason.secureStorageUnreadable,
      );
    }
    if (saved == null || saved.isEmpty) {
      return;
    }
    final previous = saved == _noKey ? '' : saved;
    if ((current ?? '') == previous) {
      return; // The key was never changed.
    }
    await _writeVerified(previous);
  }

  /// After a restore has been committed or rolled back.
  Future<void> clearRollbackPoint() async {
    try {
      await _store.write(_rollbackSlot, '');
    } on SecureStorageUnavailableException {
      // Harmless leftover: it is overwritten before the next restore.
    }
  }

  Future<String?> _readKey() async {
    try {
      final current = await _store.read(databaseKeyStorageName);
      if (isWellFormedDatabaseKey(current)) {
        return current;
      }
      final legacyStore = _legacyStore;
      if (legacyStore == null) {
        return null;
      }
      final legacy = await legacyStore.read(databaseKeyStorageName);
      if (!isWellFormedDatabaseKey(legacy)) {
        return null;
      }
      await _writeVerified(legacy!);
      return legacy;
    } on SecureStorageUnavailableException {
      throw const DatabaseKeyUnavailableException(
        DatabaseKeyUnavailableReason.secureStorageUnreadable,
      );
    }
  }

  Future<void> _writeVerified(String key) async {
    try {
      final previous = await _store.read(databaseKeyStorageName);
      if (previous != null && previous.isNotEmpty && previous != key) {
        final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
        await _store.write('$databaseKeyStorageName.preserved.$stamp', previous);
      }
      await _store.write(databaseKeyStorageName, key);
      if (await _store.read(databaseKeyStorageName) != key) {
        throw const DatabaseKeyUnavailableException(
          DatabaseKeyUnavailableReason.keyCouldNotBeSaved,
        );
      }
    } on SecureStorageUnavailableException {
      throw const DatabaseKeyUnavailableException(
        DatabaseKeyUnavailableReason.keyCouldNotBeSaved,
      );
    }
  }
}

/// 256 bits of cryptographically secure randomness, hex-encoded. Generated
/// with `Random.secure()`, which on Android is backed by the platform's
/// secure RNG — never `Random()` (not cryptographically secure) and never a
/// fixed/derived value. Exposed at file level (not private) so its output
/// characteristics can be unit-tested directly.
String generatePassphrase() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// SQL-escapes a value for safe interpolation into a `PRAGMA key = '...'`
/// statement. PRAGMA statements cannot be parameterized with `?` bind
/// variables in sqlite3, so this is the standard, documented approach
/// (doubling embedded single quotes) rather than an invented workaround.
String escapeForSqlLiteral(String value) => value.replaceAll("'", "''");

/// Asserts the opened database is actually using an encrypted build.
/// `PRAGMA cipher` only returns a row when the multi-cipher SQLite build is
/// active; on a plain SQLite build it returns nothing, which would mean
/// `PRAGMA key` silently had no effect. Checked with `assert` (debug-only),
/// matching Drift's own documented pattern for this check.
bool debugCheckHasCipher(sqlite3.Database database) {
  return database.select('PRAGMA cipher;').isNotEmpty;
}

/// Sets sqlite3's temp-file directory. Required on Android: the platform's
/// default temp directory isn't writable by sqlite3, and some operations
/// (VACUUM, large sorts, the `PRAGMA key` rekey path) need a working temp
/// location or fail. Documented Drift/sqlite3 requirement, not an invented
/// workaround. Safe to call more than once; idempotent.
///
/// [overrideTempDirectoryPath] is for tests only — production code should
/// call this with no arguments so it resolves the path via path_provider.
Future<void> configureSqlite3TempDirectory({
  String? overrideTempDirectoryPath,
}) async {
  final path =
      overrideTempDirectoryPath ?? (await getTemporaryDirectory()).path;
  sqlite3.sqlite3.tempDirectory = path;
}

/// The database file's location. [overrideDirectoryPath] is for tests.
Future<File> databaseFile({String? overrideDirectoryPath}) async {
  final directoryPath =
      overrideDirectoryPath ?? (await getApplicationDocumentsDirectory()).path;
  return File(p.join(directoryPath, databaseFileName));
}

/// True if [passphrase] decrypts the database at [file]. Opens read-only and
/// changes nothing; any failure (wrong key, not a database) returns false.
bool keyOpensDatabase(File file, String passphrase) {
  final db = sqlite3.sqlite3.open(file.path, mode: sqlite3.OpenMode.readOnly);
  try {
    db.execute("PRAGMA key = '${escapeForSqlLiteral(passphrase)}';");
    db.select('SELECT count(*) FROM sqlite_master');
    return true;
  } on sqlite3.SqliteException {
    return false;
  } finally {
    db.close();
  }
}

/// Opens the encrypted local database. Centralizes the only place the
/// database file path, encryption key, and cipher verification are decided —
/// per Phase 1.2 instruction §4, nothing else in the app should open a
/// database connection directly.
///
/// Throws [DatabaseKeyUnavailableException] — without creating, replacing, or
/// deleting anything — if a database exists but its key is missing,
/// unreadable, or wrong.
///
/// [overrideDirectoryPath], [overrideTempDirectoryPath] and [keyManager]
/// exist for tests only (a temp-directory database with a throwaway key, and
/// no dependency on path_provider's platform channel) — production code
/// should call this with no arguments.
Future<QueryExecutor> openEncryptedDatabase({
  DatabaseKeyManager? keyManager,
  String? overrideDirectoryPath,
  String? overrideTempDirectoryPath,
}) async {
  await configureSqlite3TempDirectory(
    overrideTempDirectoryPath: overrideTempDirectoryPath,
  );

  final dbFile = await databaseFile(overrideDirectoryPath: overrideDirectoryPath);
  final exists = await dbFile.exists();

  final passphrase = await (keyManager ?? DatabaseKeyManager()).resolveKey(
    databaseFileExists: exists,
  );
  if (exists && !keyOpensDatabase(dbFile, passphrase)) {
    throw const DatabaseKeyUnavailableException(
      DatabaseKeyUnavailableReason.keyDoesNotOpenDatabase,
    );
  }
  final escapedPassphrase = escapeForSqlLiteral(passphrase);

  return NativeDatabase.createInBackground(
    dbFile,
    setup: (rawDb) {
      rawDb.execute("PRAGMA key = '$escapedPassphrase';");
      assert(
        debugCheckHasCipher(rawDb),
        'Database opened without an active cipher — encryption is not in '
        'effect. This must never happen outside a deliberately-unencrypted '
        'test database.',
      );
    },
  );
}
