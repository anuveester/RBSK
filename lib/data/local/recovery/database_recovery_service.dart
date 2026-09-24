import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/core/utils/id_generator.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:referredline/domain/repositories/auth_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'backup_key_store.dart';
import 'recovery_package.dart';
import 'restore_transaction.dart';

/// The Backup Recovery Key is not set up on this phone yet.
class NoBackupKeyException implements Exception {
  const NoBackupKeyException();
}

/// The database file is not encrypted, so it must not be exported.
class PlaintextDatabaseException implements Exception {
  const PlaintextDatabaseException();
}

/// The database on this phone opens and has accounts: it is in use, so a
/// restore (which needs no login) must not replace it. Restoring is only for
/// a phone with no accounts yet, or one whose data is locked.
class DatabaseInUseException implements Exception {
  const DatabaseInUseException();
}

/// Why a restore is happening; decides which audit events are written.
enum RestoreContext {
  /// First-run on a (new or reset) phone.
  newDevice,

  /// The database key on this phone is unavailable.
  keyUnavailable,
}

/// A package that passed every check and whose database is staged next to
/// the live location, not yet installed.
class VerifiedRestore {
  VerifiedRestore._(this._stagedDatabase, this._package, this.context);

  final File _stagedDatabase;
  final OpenedRecoveryPackage _package;
  final RestoreContext context;
  bool _consumed = false;

  RecoveryPackageSummary get summary => _package.summary;

  @override
  String toString() => 'VerifiedRestore(${_package.packageId}, redacted)';
}

/// What happened to data that was on the phone before a restore.
class RestoreOutcome {
  const RestoreOutcome({required this.preservedDatabaseFileName});

  /// The previous database, renamed and kept (never deleted), or null if
  /// there was none.
  final String? preservedDatabaseFileName;
}

/// Controlled encrypted backup and database recovery (docs/30 R5).
///
/// - **Export** snapshots the database file *as stored* (still encrypted)
///   while holding a read lock, and wraps it in a recovery package. Only a
///   logged-in Admin who re-enters their PIN can export or set the Backup
///   Recovery Key; this service checks that itself through [AuthRepository]
///   and never trusts a user id passed in by a caller.
/// - **Import** verifies the package completely (authenticity, integrity,
///   and that its key opens its database) before touching anything, and
///   installs only after explicit confirmation, as one all-or-nothing
///   change ([RestoreTransaction]). It is refused while the database on the
///   phone is in use ([DatabaseInUseException]). The database and key
///   already on the phone are renamed and kept, never deleted or
///   overwritten.
///
/// Neither operation logs or returns secret material.
class DatabaseRecoveryService {
  DatabaseRecoveryService({
    required this._keyManager,
    required this._backupKeys,
    required Future<File> Function() databaseFileLocator,
    required this._workDirectory,
    required this._preOpenAudit,
    DateTime Function()? clock,
    @visibleForTesting this._beforeRestoreStep,
  }) : _databaseFile = databaseFileLocator,
       _clock = clock ?? DateTime.now;

  final DatabaseKeyManager _keyManager;
  final BackupKeyStore _backupKeys;
  final Future<File> Function() _databaseFile;
  final Future<Directory> Function() _workDirectory;
  final SecurityEventSink _preOpenAudit;
  final DateTime Function() _clock;
  final void Function(RestoreStep step)? _beforeRestoreStep;

  late final RestoreTransaction _transaction = RestoreTransaction(
    keyManager: _keyManager,
    backupKeys: _backupKeys,
    databaseFileLocator: _databaseFile,
    audit: _preOpenAudit,
    clock: _clock,
    beforeStep: _beforeRestoreStep,
  );

  // --- Backup key -----------------------------------------------------------

  Future<BackupKeyMaterial?> currentBackupKey() => _backupKeys.read();

  /// Creates and stores a new Backup Recovery Key, returning it for one-time
  /// display. Only the derived material is stored. Requires the logged-in
  /// Admin's current PIN ([AuthRepository.reauthenticateAdmin]).
  Future<SecretCode> createBackupKey({
    required AuthRepository auth,
    required String currentPin,
    required SecurityEventSink audit,
  }) async {
    final session = await auth.reauthenticateAdmin(
      pin: currentPin,
      operation: 'createBackupKey',
    );
    final actorUserId = session.userId;
    final code = SecretCode.generate(SecretCodeKind.backupRecovery);
    final material = BackupKeyMaterial.derive(code, createdAt: _clock());
    await _backupKeys.write(material);
    await audit.record(
      SecurityEvent(
        SecurityEventType.backupKeyCreated,
        actorUserId: actorUserId,
        details: {'backupKeyId': material.keyId},
      ),
    );
    return code;
  }

  // --- Export ---------------------------------------------------------------

  /// Writes an encrypted recovery package of [db] into the work directory
  /// and returns it. The caller hands it to the user (save/share) and then
  /// calls [discardExport]. Requires the logged-in Admin's current PIN
  /// ([AuthRepository.reauthenticateAdmin]).
  Future<File> createPackage(
    AppDatabase db, {
    required AuthRepository auth,
    required String currentPin,
    required SecurityEventSink audit,
  }) async {
    final session = await auth.reauthenticateAdmin(
      pin: currentPin,
      operation: 'exportBackup',
    );
    final actorUserId = session.userId;
    final material = await _backupKeys.read();
    if (material == null) {
      throw const NoBackupKeyException();
    }
    final dbFile = await _databaseFile();
    final work = await _workDirectory();
    await work.create(recursive: true);
    await _removeOldExports(work);
    final now = _clock().toUtc();
    final packageId = generateUuidV4();
    final snapshot = File(p.join(work.path, 'export-$packageId.snapshot'));
    final output = File(p.join(work.path, _packageFileName(now)));

    try {
      await db.transaction(() async {
        // Holding the transaction (with its read lock) keeps the file
        // unchanged while it is copied. The app never enables WAL; refuse
        // rather than copy an incomplete file if that ever changes.
        final mode = await db.customSelect('PRAGMA journal_mode').getSingle();
        if ('${mode.data.values.first}'.toLowerCase() == 'wal') {
          throw StateError('WAL journal mode is not supported for export.');
        }
        await db.customSelect('SELECT count(*) FROM sqlite_master').get();
        await dbFile.copy(snapshot.path);
      });
      // Safety net: never export a database that is not encrypted (a plain
      // SQLite file starts with this header; an encrypted one does not).
      if (await _isPlaintextSqlite(snapshot)) {
        throw const PlaintextDatabaseException();
      }

      final key = await _keyManager.resolveKey(databaseFileExists: true);
      await writeRecoveryPackage(
        databaseSnapshot: snapshot,
        databaseKey: key,
        key: material,
        output: output,
        packageId: packageId,
        createdAt: now,
        schemaVersion: db.schemaVersion,
      );
      await audit.record(
        SecurityEvent(
          SecurityEventType.backupExportCreated,
          actorUserId: actorUserId,
          details: {
            'packageId': packageId,
            'backupKeyId': material.keyId,
            'databaseBytes': '${await snapshot.length()}',
          },
        ),
      );
      return output;
    } catch (e) {
      if (await output.exists()) {
        await output.delete();
      }
      await audit.record(
        SecurityEvent(
          SecurityEventType.backupExportFailed,
          actorUserId: actorUserId,
          details: {'reason': _reasonOf(e)},
        ),
      );
      rethrow;
    } finally {
      if (await snapshot.exists()) {
        await snapshot.delete();
      }
    }
  }

  /// Removes the app's own copy of an exported package after it has been
  /// handed to the user.
  Future<void> discardExport(File package) async {
    if (await package.exists()) {
      await package.delete();
    }
  }

  /// Exports and snapshots left behind by an export that was interrupted
  /// (e.g. the app was closed while the save dialog was open).
  static Future<void> _removeOldExports(Directory work) async {
    await for (final entity in work.list()) {
      final name = p.basename(entity.path);
      if (entity is File &&
          ((name.startsWith('export-') && name.endsWith('.snapshot')) ||
              (name.startsWith('rbsk-recovery-') && name.endsWith('.rbskrp')))) {
        await entity.delete();
      }
    }
  }

  /// Removes everything a recovery operation may have left behind: the work
  /// folder (package copies, snapshots) and a staged database from an
  /// unfinished import. Run once at start-up, when no operation can be in
  /// progress. Leaves a staged database alone while a restore marker exists
  /// (the restore must be resolved first). Never touches the database.
  Future<void> removeLeftoverFiles() async {
    try {
      final work = await _workDirectory();
      if (await work.exists()) {
        await work.delete(recursive: true);
      }
      final dbFile = await _databaseFile();
      final staged = File('${dbFile.path}.restore-staged');
      if (!await RestoreTransaction.markerFor(dbFile).exists() &&
          await staged.exists()) {
        await staged.delete();
      }
    } on FileSystemException {
      // Best effort; tried again at the next start.
    }
  }

  /// See [RestoreTransaction.resolveInterrupted].
  Future<InterruptedRestoreOutcome> resolveInterruptedRestore() =>
      _transaction.resolveInterrupted();

  // --- Import ---------------------------------------------------------------

  Future<RecoveryPackageSummary> inspect(File package) =>
      readRecoveryPackageSummary(package);

  /// Verifies [package] with [backupKeyText] and stages its database. Throws
  /// [SecretCodeFormatException] for a mistyped key,
  /// [DatabaseInUseException] if the data on this phone is in use, or
  /// [RecoveryPackageException] for anything wrong with the package. Nothing
  /// on the phone changes.
  Future<VerifiedRestore> verify(
    File package,
    String backupKeyText, {
    required RestoreContext context,
  }) async {
    final code = SecretCode.parse(backupKeyText, SecretCodeKind.backupRecovery);
    await _preOpenAudit.record(
      SecurityEvent(_attemptedEvent(context), details: {'context': context.name}),
    );
    await _refuseIfDatabaseInUse(context);

    final dbFile = await _databaseFile();
    await dbFile.parent.create(recursive: true);
    final staged = File('${dbFile.path}.restore-staged');
    if (await staged.exists()) {
      await staged.delete();
    }

    try {
      final opened = await openRecoveryPackage(
        package,
        code,
        databaseOutput: staged,
      );
      if (!keyOpensDatabase(staged, opened.databaseKey) ||
          !_schemaVersionSupported(staged, opened.databaseKey)) {
        throw const RecoveryPackageException(
          RecoveryPackageError.databaseDoesNotOpen,
        );
      }
      return VerifiedRestore._(staged, opened, context);
    } on RecoveryPackageException catch (e) {
      if (await staged.exists()) {
        await staged.delete();
      }
      await _preOpenAudit.record(
        SecurityEvent(
          _rejectedEvent(context),
          details: {'context': context.name, 'reason': e.reason.name},
        ),
      );
      rethrow;
    }
  }

  /// Installs a verified package. Requires [confirmedByUser]: the UI must
  /// have shown what will happen and the user must have agreed.
  ///
  /// All or nothing ([RestoreTransaction]): if any step fails, the database
  /// and keys that were in use are put back before this throws, and a crash
  /// part-way is undone at the next start. The previous database is kept
  /// under another name, never deleted.
  Future<RestoreOutcome> install(
    VerifiedRestore restore, {
    required bool confirmedByUser,
  }) async {
    if (!confirmedByUser) {
      throw StateError('Restore must be confirmed by the user.');
    }
    if (restore._consumed) {
      throw StateError('This restore has already been installed.');
    }
    restore._consumed = true;

    final String? preservedName;
    try {
      // Checked again here: the phone may have been set up since verify().
      await _refuseIfDatabaseInUse(restore.context);
      preservedName = await _transaction.install(
        staged: restore._stagedDatabase,
        databaseKey: restore._package.databaseKey,
        backupKeyMaterial: restore._package.backupKeyMaterial,
      );
    } on SimulatedPowerLoss {
      rethrow;
    } catch (e) {
      if (await restore._stagedDatabase.exists()) {
        await restore._stagedDatabase.delete();
      }
      await _preOpenAudit.record(
        SecurityEvent(
          _failedEvent(restore.context),
          details: {'context': restore.context.name, 'reason': _reasonOf(e)},
        ),
      );
      rethrow;
    }

    await _preOpenAudit.record(
      SecurityEvent(
        _succeededEvent(restore.context),
        details: {
          'context': restore.context.name,
          'packageId': restore._package.packageId,
          'backupKeyId': restore._package.backupKeyMaterial.keyId,
          'preservedDatabaseFile': ?preservedName,
        },
      ),
    );
    return RestoreOutcome(preservedDatabaseFileName: preservedName);
  }

  /// A restore needs no login, so it must never replace data that is in use:
  /// a database that opens with the stored key and has at least one account.
  /// A missing, unreadable or wrong key means the data is locked, which is
  /// exactly when a restore is allowed.
  Future<void> _refuseIfDatabaseInUse(RestoreContext context) async {
    final dbFile = await _databaseFile();
    if (!await dbFile.exists()) {
      return;
    }
    final String? key;
    try {
      key = await _keyManager.readCurrentKey();
    } on DatabaseKeyUnavailableException {
      return;
    }
    if (key == null || !keyOpensDatabase(dbFile, key)) {
      return;
    }
    if (_hasAccounts(dbFile, key)) {
      await _preOpenAudit.record(
        SecurityEvent(
          _rejectedEvent(context),
          details: {'context': context.name, 'reason': 'databaseInUse'},
        ),
      );
      throw const DatabaseInUseException();
    }
  }

  /// Fails closed: anything but "no users table yet" or a zero count is
  /// treated as having accounts.
  static bool _hasAccounts(File file, String key) {
    final db = sqlite3.sqlite3.open(file.path, mode: sqlite3.OpenMode.readOnly);
    try {
      db.execute("PRAGMA key = '${escapeForSqlLiteral(key)}';");
      final hasTable = db
          .select(
            'SELECT count(*) FROM sqlite_master '
            "WHERE type = 'table' AND name = 'users'",
          )
          .single
          .values
          .first;
      if (hasTable == 0) {
        return false;
      }
      return db.select('SELECT count(*) FROM users').single.values.first != 0;
    } on sqlite3.SqliteException {
      return true;
    } finally {
      db.close();
    }
  }

  /// Removes a staged (verified but not installed) database.
  Future<void> discard(VerifiedRestore restore) async {
    if (!restore._consumed && await restore._stagedDatabase.exists()) {
      await restore._stagedDatabase.delete();
    }
  }

  bool _schemaVersionSupported(File file, String key) {
    final db = sqlite3.sqlite3.open(file.path, mode: sqlite3.OpenMode.readOnly);
    try {
      db.execute("PRAGMA key = '${escapeForSqlLiteral(key)}';");
      final version = db.select('PRAGMA user_version').single.values.first;
      return version is int && version >= 1 && version <= _supportedSchemaVersion;
    } on sqlite3.SqliteException {
      return false;
    } finally {
      db.close();
    }
  }

  static const int _supportedSchemaVersion = 1;

  static Future<bool> _isPlaintextSqlite(File file) async {
    const header = 'SQLite format 3\u0000';
    final raf = await file.open();
    try {
      final start = await raf.read(header.length);
      return String.fromCharCodes(start) == header;
    } finally {
      await raf.close();
    }
  }

  static String _packageFileName(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'rbsk-recovery-${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}.rbskrp';
  }

  static String _reasonOf(Object e) => switch (e) {
    RecoveryPackageException(:final reason) => reason.name,
    DatabaseKeyUnavailableException(:final reason) => reason.name,
    NoBackupKeyException() => 'noBackupKey',
    PlaintextDatabaseException() => 'databaseNotEncrypted',
    DatabaseInUseException() => 'databaseInUse',
    SecureStorageUnavailableException() => 'secureStorageUnavailable',
    FileSystemException() => 'fileSystemError',
    _ => 'unexpectedError',
  };

  static SecurityEventType _attemptedEvent(RestoreContext c) =>
      c == RestoreContext.keyUnavailable
      ? SecurityEventType.databaseRecoveryAttempted
      : SecurityEventType.backupImportAttempted;

  static SecurityEventType _rejectedEvent(RestoreContext c) =>
      c == RestoreContext.keyUnavailable
      ? SecurityEventType.databaseRecoveryFailed
      : SecurityEventType.backupImportRejected;

  static SecurityEventType _failedEvent(RestoreContext c) => _rejectedEvent(c);

  static SecurityEventType _succeededEvent(RestoreContext c) =>
      c == RestoreContext.keyUnavailable
      ? SecurityEventType.databaseRecoverySucceeded
      : SecurityEventType.backupImportSucceeded;
}
