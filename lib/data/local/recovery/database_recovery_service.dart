import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/core/utils/id_generator.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'backup_key_store.dart';
import 'recovery_package.dart';

/// The Backup Recovery Key is not set up on this phone yet.
class NoBackupKeyException implements Exception {
  const NoBackupKeyException();
}

/// The database file is not encrypted, so it must not be exported.
class PlaintextDatabaseException implements Exception {
  const PlaintextDatabaseException();
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
///   while holding a read lock, and wraps it in a recovery package.
/// - **Import** verifies the package completely (authenticity, integrity,
///   and that its key opens its database) before touching anything, and
///   installs only after explicit confirmation. The database and key already
///   on the phone are renamed and kept, never deleted or overwritten.
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
  }) : _databaseFile = databaseFileLocator,
       _clock = clock ?? DateTime.now;

  final DatabaseKeyManager _keyManager;
  final BackupKeyStore _backupKeys;
  final Future<File> Function() _databaseFile;
  final Future<Directory> Function() _workDirectory;
  final SecurityEventSink _preOpenAudit;
  final DateTime Function() _clock;

  // --- Backup key -----------------------------------------------------------

  Future<BackupKeyMaterial?> currentBackupKey() => _backupKeys.read();

  /// Creates and stores a new Backup Recovery Key, returning it for one-time
  /// display. Only the derived material is stored. Callers must check the
  /// Admin's authority first (see `LocalAuthRepository`).
  Future<SecretCode> createBackupKey({
    required String actorUserId,
    required SecurityEventSink audit,
  }) async {
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
  /// calls [discardExport].
  Future<File> createPackage(
    AppDatabase db, {
    required String actorUserId,
    required SecurityEventSink audit,
  }) async {
    final material = await _backupKeys.read();
    if (material == null) {
      throw const NoBackupKeyException();
    }
    final dbFile = await _databaseFile();
    final work = await _workDirectory();
    await work.create(recursive: true);
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

  // --- Import ---------------------------------------------------------------

  Future<RecoveryPackageSummary> inspect(File package) =>
      readRecoveryPackageSummary(package);

  /// Verifies [package] with [backupKeyText] and stages its database. Throws
  /// [SecretCodeFormatException] for a mistyped key, or
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
  /// Order is chosen so that an interruption never loses anything and can be
  /// completed by running the restore again: keep the old database, move the
  /// new one into place, then store its key (the old key is kept by
  /// [DatabaseKeyManager.installRecoveredKey]).
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

    final dbFile = await _databaseFile();
    String? preservedName;
    try {
      if (await dbFile.exists()) {
        final stamp = _clock().toUtc().microsecondsSinceEpoch;
        final preserved = File('${dbFile.path}.preserved-$stamp');
        await dbFile.rename(preserved.path);
        final journal = File('${dbFile.path}-journal');
        if (await journal.exists()) {
          await journal.rename('${preserved.path}-journal');
        }
        preservedName = p.basename(preserved.path);
      }
      await restore._stagedDatabase.rename(dbFile.path);
      await _keyManager.installRecoveredKey(restore._package.databaseKey);
      await _backupKeys.write(restore._package.backupKeyMaterial);
    } catch (e) {
      await _preOpenAudit.record(
        SecurityEvent(
          _failedEvent(restore.context),
          details: {
            'context': restore.context.name,
            'reason': _reasonOf(e),
            'preservedDatabaseFile': ?preservedName,
          },
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
