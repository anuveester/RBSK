import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/security/security_audit.dart';

import 'backup_key_store.dart';
import 'recovery_package.dart';

/// The steps of installing a restored database, in order.
enum RestoreStep {
  /// Remember the stored database key and backup-key material.
  saveRollbackPoint,

  /// Write the marker that makes an interrupted restore detectable.
  writeMarker,

  /// Rename the current database aside (it is kept, never deleted).
  preserveCurrentDatabase,

  /// Rename the verified, staged database into place.
  moveRestoredDatabase,

  /// Store the restored database's key.
  installDatabaseKey,

  /// Store the restored Backup Recovery Key material.
  installBackupKey,

  /// Check that the stored key opens the database now in place.
  verifyInstalled,

  /// Mark the restore complete.
  commit,

  /// Remove the marker and rollback points (the restore already counts).
  finish,
}

/// What start-up found and did about an earlier restore.
enum InterruptedRestoreOutcome {
  /// No restore was in progress.
  none,

  /// A restore was in progress and has been undone: the phone is back to the
  /// data and key it had before.
  rolledBack,

  /// The restore had finished; only its bookkeeping was left.
  completed,
}

/// Test-only: thrown by a step hook to stop a restore as if the phone had
/// lost power at that point. No rollback runs, exactly as after a real
/// crash; the next start-up must resolve it. Production code never throws
/// it (there is no step hook outside tests).
class SimulatedPowerLoss implements Exception {
  const SimulatedPowerLoss();
}

/// Installs a verified restore as one all-or-nothing change, and undoes a
/// restore that a crash interrupted.
///
/// A marker file next to the database records what is in progress (file
/// names and phase only — no secrets). Until the restore is committed, any
/// failure — in this run, or a crash found at the next start — is undone:
/// the database that was in use is put back where it was, and the database
/// key and backup-key material are set back to what they were. A failed
/// restore therefore never leaves the phone without its previous, usable
/// data.
class RestoreTransaction {
  RestoreTransaction({
    required this._keyManager,
    required this._backupKeys,
    required Future<File> Function() databaseFileLocator,
    required this._audit,
    DateTime Function()? clock,
    // Test-only step hook (see [SimulatedPowerLoss]); null in the app.
    this._beforeStep,
  }) : _databaseFile = databaseFileLocator,
       _clock = clock ?? DateTime.now;

  final DatabaseKeyManager _keyManager;
  final BackupKeyStore _backupKeys;
  final Future<File> Function() _databaseFile;
  final SecurityEventSink _audit;
  final DateTime Function() _clock;
  final void Function(RestoreStep step)? _beforeStep;

  static File markerFor(File database) =>
      File('${database.path}.restore-marker');

  /// Installs [staged] (already verified to open with [databaseKey]) as the
  /// database. Returns the file name the previous database was kept under,
  /// or null if there was none. On failure everything is rolled back and
  /// the error is rethrown. If even the rollback fails, the marker stays and
  /// start-up completes the rollback before the database is opened.
  Future<String?> install({
    required File staged,
    required String databaseKey,
    required BackupKeyMaterial backupKeyMaterial,
  }) async {
    final dbFile = await _databaseFile();
    final marker = markerFor(dbFile);
    if (await marker.exists()) {
      // An earlier restore was never resolved; do that first.
      await resolveInterrupted();
    }

    final hadDatabase = await dbFile.exists();
    final preserved = hadDatabase
        ? File('${dbFile.path}.preserved-${_clock().toUtc().microsecondsSinceEpoch}')
        : null;
    final state = _MarkerState(
      phase: _Phase.installing,
      preservedDatabase: preserved == null ? null : p.basename(preserved.path),
    );

    _step(RestoreStep.saveRollbackPoint);
    // Nothing has changed yet; a failure here needs no undo.
    await _keyManager.saveRollbackPoint();
    await _backupKeys.saveRollbackPoint();

    var markerWritten = false;
    try {
      _step(RestoreStep.writeMarker);
      await _writeMarker(marker, state);
      markerWritten = true;

      if (preserved != null) {
        _step(RestoreStep.preserveCurrentDatabase);
        await dbFile.rename(preserved.path);
        final journal = File('${dbFile.path}-journal');
        if (await journal.exists()) {
          await journal.rename('${preserved.path}-journal');
        }
      }

      _step(RestoreStep.moveRestoredDatabase);
      await staged.rename(dbFile.path);

      _step(RestoreStep.installDatabaseKey);
      await _keyManager.installRecoveredKey(databaseKey);

      _step(RestoreStep.installBackupKey);
      await _backupKeys.write(backupKeyMaterial);

      _step(RestoreStep.verifyInstalled);
      final stored = await _keyManager.readCurrentKey();
      if (stored != databaseKey || !keyOpensDatabase(dbFile, databaseKey)) {
        throw const DatabaseKeyUnavailableException(
          DatabaseKeyUnavailableReason.keyCouldNotBeSaved,
        );
      }

      _step(RestoreStep.commit);
      await _writeMarker(marker, state.committed());
    } on SimulatedPowerLoss {
      rethrow;
    } catch (e) {
      try {
        if (markerWritten) {
          await _rollBack(dbFile, state, reason: _reasonOf(e));
        } else {
          await _finish(marker);
        }
      } catch (_) {
        // The marker is still there: start-up finishes the rollback.
      }
      rethrow;
    }

    // Committed. Only bookkeeping is left; if it fails, start-up finishes it.
    _step(RestoreStep.finish);
    try {
      await _finish(marker);
    } catch (_) {
      // Resolved as "completed" at the next start.
    }
    return state.preservedDatabase;
  }

  /// Run at start-up before the database is opened. Finishes the
  /// bookkeeping of a committed restore, or undoes one that was interrupted.
  /// Throws if the undo cannot be completed (the marker is then kept, and
  /// the database must not be opened).
  Future<InterruptedRestoreOutcome> resolveInterrupted() async {
    final dbFile = await _databaseFile();
    final marker = markerFor(dbFile);
    if (!await marker.exists()) {
      // A leftover temporary marker means the first marker write never
      // completed, so nothing had been changed yet.
      final tmp = File('${marker.path}.tmp');
      if (await tmp.exists()) {
        await tmp.delete();
      }
      return InterruptedRestoreOutcome.none;
    }
    final state = await _readMarker(marker);
    if (state != null && state.phase == _Phase.committed) {
      await _finish(marker);
      await _audit.record(
        SecurityEvent(
          SecurityEventType.interruptedRestoreResolved,
          details: {'outcome': 'completed'},
        ),
      );
      return InterruptedRestoreOutcome.completed;
    }
    await _rollBack(
      dbFile,
      state ?? const _MarkerState(phase: _Phase.installing),
      reason: 'interrupted',
      markerReadable: state != null,
    );
    await _audit.record(
      SecurityEvent(
        SecurityEventType.interruptedRestoreResolved,
        details: {'outcome': 'rolledBack'},
      ),
    );
    return InterruptedRestoreOutcome.rolledBack;
  }

  /// Puts the previous database and keys back. Safe to run more than once,
  /// and from any point in [install]: it looks at which files exist.
  ///
  /// If the marker could not be read ([markerReadable] false), no database
  /// file is removed: which file is which is then unknown, so everything is
  /// kept and only the keys are set back.
  Future<void> _rollBack(
    File dbFile,
    _MarkerState state, {
    required String reason,
    bool markerReadable = true,
  }) async {
    final preservedName = state.preservedDatabase;
    final preserved = preservedName == null
        ? null
        : File(p.join(dbFile.parent.path, preservedName));
    final staged = File('${dbFile.path}.restore-staged');

    if (preserved != null && await preserved.exists()) {
      // The previous database was moved aside. Whatever is at the live
      // location now is the restored copy (it is also in the package).
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      final liveJournal = File('${dbFile.path}-journal');
      if (await liveJournal.exists()) {
        await liveJournal.delete();
      }
      await preserved.rename(dbFile.path);
      final preservedJournal = File('${preserved.path}-journal');
      if (await preservedJournal.exists()) {
        await preservedJournal.rename(liveJournal.path);
      }
    } else if (markerReadable &&
        preserved == null &&
        await dbFile.exists() &&
        !await staged.exists()) {
      // There was no database before and the staged copy has already been
      // moved into place: the file there is the restored copy.
      await dbFile.delete();
    }
    // Otherwise the previous database was never moved: nothing to undo.

    if (await staged.exists()) {
      await staged.delete();
    }

    await _keyManager.rollBackToSavedPoint();
    await _backupKeys.rollBackToSavedPoint();
    await _finish(markerFor(dbFile));
    await _audit.record(
      SecurityEvent(
        SecurityEventType.restoreRolledBack,
        details: {'reason': reason},
      ),
    );
  }

  Future<void> _finish(File marker) async {
    await _keyManager.clearRollbackPoint();
    await _backupKeys.clearRollbackPoint();
    for (final file in [File('${marker.path}.tmp'), marker]) {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  void _step(RestoreStep step) => _beforeStep?.call(step);

  /// Written to a temporary file and renamed, so the marker is always either
  /// the old or the new content, never half-written.
  static Future<void> _writeMarker(File marker, _MarkerState state) async {
    final tmp = File('${marker.path}.tmp');
    await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
    await tmp.rename(marker.path);
  }

  static Future<_MarkerState?> _readMarker(File marker) async {
    try {
      final json = jsonDecode(await marker.readAsString());
      return json is Map<String, dynamic> ? _MarkerState.fromJson(json) : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static String _reasonOf(Object e) => switch (e) {
    DatabaseKeyUnavailableException(:final reason) => reason.name,
    SecureStorageUnavailableException() => 'secureStorageUnavailable',
    FileSystemException() => 'fileSystemError',
    _ => 'unexpectedError',
  };
}

enum _Phase { installing, committed }

/// The marker's content. File names and the phase only: no keys, no paths
/// outside the database folder, nothing about the data.
class _MarkerState {
  const _MarkerState({required this.phase, this.preservedDatabase});

  final _Phase phase;
  final String? preservedDatabase;

  _MarkerState committed() =>
      _MarkerState(phase: _Phase.committed, preservedDatabase: preservedDatabase);

  Map<String, Object?> toJson() => {
    'version': 1,
    'phase': phase.name,
    'preservedDatabase': preservedDatabase,
  };

  static _MarkerState? fromJson(Map<String, dynamic> json) {
    final phase = _Phase.values.where((v) => v.name == json['phase']).firstOrNull;
    final preserved = json['preservedDatabase'];
    if (phase == null || (preserved != null && preserved is! String)) {
      return null;
    }
    // Only a bare file name is accepted, so a damaged marker can never
    // point the rollback at another location.
    if (preserved is String && p.basename(preserved) != preserved) {
      return null;
    }
    return _MarkerState(phase: phase, preservedDatabase: preserved as String?);
  }
}
