import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
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
/// mechanism, same cipher — and actively maintained. Nothing about the
/// encryption REQUIREMENT changes; only the specific package implementing it
/// does, because the one named in Phase 0 no longer exists as a working
/// option.
const _dbFileName = 'rbsk_referred_line.sqlite';
const _secureStorageKeyName = 'rbsk_db_encryption_key_v1';

/// Thin abstraction over "a place that securely persists one string", so
/// [DatabaseKeyManager] is unit-testable without platform channels. The only
/// production implementation is [FlutterSecureStorageKeyStore]
/// (Android Keystore-backed); tests substitute an in-memory fake.
abstract interface class SecureKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class FlutterSecureStorageKeyStore implements SecureKeyStore {
  const FlutterSecureStorageKeyStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Reads the database passphrase from secure storage, generating and
/// persisting a new one on first launch. Never hardcoded, never logged,
/// never stored in plain text alongside the database file.
class DatabaseKeyManager {
  DatabaseKeyManager({SecureKeyStore? store})
    : _store = store ?? const FlutterSecureStorageKeyStore();

  final SecureKeyStore _store;

  Future<String> getOrCreateKey() async {
    final existing = await _store.read(_secureStorageKeyName);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated = generatePassphrase();
    await _store.write(_secureStorageKeyName, generated);
    return generated;
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

/// Opens the encrypted local database. Centralizes the only place the
/// database file path, encryption key, and cipher verification are decided —
/// per Phase 1.2 instruction §4, nothing else in the app should open a
/// database connection directly.
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

  final directoryPath =
      overrideDirectoryPath ??
      (await getApplicationDocumentsDirectory()).path;
  final dbFile = File(p.join(directoryPath, _dbFileName));

  final passphrase = await (keyManager ?? DatabaseKeyManager()).getOrCreateKey();
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
