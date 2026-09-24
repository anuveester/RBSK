import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:referredline/core/utils/id_generator.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/enums.dart';

/// Security-relevant operations recorded in the audit trail.
enum SecurityEventType {
  adminRecoveryCodeCreated,
  adminRecoveryCodeConfirmed,
  pinResetWithRecoveryCodeSucceeded,
  pinResetWithRecoveryCodeRejected,
  pinVerifierUpgraded,
  backupKeyCreated,
  backupExportCreated,
  backupExportFailed,
  backupImportAttempted,
  backupImportSucceeded,
  backupImportRejected,
  databaseRecoveryAttempted,
  databaseRecoverySucceeded,
  databaseRecoveryFailed,
  adminAccessRestoredWithBackupKey,
  adminAccessRestoreRejected,
  databaseKeyUnavailable,
  secureStorageFailure,
}

/// One security event.
///
/// [details] holds **only** non-secret, machine-readable values: reason
/// codes, record ids, counts, package ids. Never a PIN, a recovery code, a
/// key, a salt, a verifier, a file path, or any child/health data.
class SecurityEvent {
  SecurityEvent(
    this.type, {
    this.subjectUserId,
    this.actorUserId,
    Map<String, String>? details,
    DateTime? occurredAt,
  }) : details = Map.unmodifiable(details ?? const {}),
       occurredAt = (occurredAt ?? DateTime.now()).toUtc();

  final SecurityEventType type;

  /// The user the event is about (e.g. whose PIN was reset).
  final String? subjectUserId;

  /// The authenticated user who performed it, if any.
  final String? actorUserId;

  final Map<String, String> details;
  final DateTime occurredAt;

  Map<String, Object?> toJson() => {
    'event': type.name,
    'subjectUserId': subjectUserId,
    'actorUserId': actorUserId,
    'details': details,
    'occurredAt': occurredAt.toIso8601String(),
  };

  static SecurityEvent? fromJson(Map<String, dynamic> json) {
    final type = SecurityEventType.values
        .where((t) => t.name == json['event'])
        .firstOrNull;
    final occurredAt = DateTime.tryParse('${json['occurredAt']}');
    final details = json['details'];
    if (type == null || occurredAt == null || details is! Map) {
      return null;
    }
    return SecurityEvent(
      type,
      subjectUserId: json['subjectUserId'] as String?,
      actorUserId: json['actorUserId'] as String?,
      details: {for (final e in details.entries) '${e.key}': '${e.value}'},
      occurredAt: occurredAt,
    );
  }
}

abstract interface class SecurityEventSink {
  /// Best effort: never throws, so a failing audit write cannot break the
  /// security operation being audited.
  Future<void> record(SecurityEvent event);
}

/// The `audit_log` table name used for security events.
const String securityEventTableName = 'security_event';

/// Writes security events into the existing `audit_log` table
/// (docs/04 §2.11) — no second audit store. Mapping, with no schema change:
/// `table_name = 'security_event'`, `action = INSERT` (a security-event record
/// is inserted), `record_id` = the affected user (or the event's own id),
/// `new_values` = the event type, time and non-secret details.
///
/// If the database write fails, the event falls back to [fallback] so it is
/// not lost.
class DatabaseSecurityAuditLog implements SecurityEventSink {
  DatabaseSecurityAuditLog(this._db, {this._fallback});

  final AppDatabase _db;
  final PendingSecurityEventJournal? _fallback;

  @override
  Future<void> record(SecurityEvent event) async {
    try {
      await _insert(event);
    } catch (_) {
      await _fallback?.record(event);
    }
  }

  /// Moves every journaled event into `audit_log`, then clears the journal.
  /// On any failure the journal is kept for the next attempt.
  Future<void> flushPending(PendingSecurityEventJournal journal) async {
    try {
      final events = await journal.readAll();
      if (events.isEmpty) {
        return;
      }
      await _db.transaction(() async {
        for (final event in events) {
          await _insert(event);
        }
      });
      await journal.clear();
    } catch (_) {
      // Leave the journal in place.
    }
  }

  Future<void> _insert(SecurityEvent event) async {
    final id = generateUuidV4();
    // actor_user_id has a foreign key to users; only set it when that user
    // exists in this database (e.g. events journaled before a restore).
    final actor = event.actorUserId;
    final actorExists =
        actor != null &&
        await (_db.select(
          _db.users,
        )..where((t) => t.id.equals(actor))).getSingleOrNull() !=
            null;
    await _db
        .into(_db.auditLog)
        .insert(
          AuditLogCompanion.insert(
            id: id,
            businessTableName: securityEventTableName,
            recordId: event.subjectUserId ?? id,
            action: AuditAction.INSERT,
            newValues: Value(
              jsonEncode({
                'event': event.type.name,
                'occurredAt': event.occurredAt.toIso8601String(),
                if (actor != null && !actorExists) 'actorUserIdUnverified': actor,
                ...event.details,
              }),
            ),
            actorUserId: Value(actorExists ? actor : null),
            occurredAt: Value(event.occurredAt),
          ),
        );
  }
}

/// Holds security events that happen while the encrypted database cannot be
/// opened (e.g. the database key is unavailable, or a recovery package is
/// being imported). One JSON object per line, in app-private storage, with
/// the same no-secrets rule as [SecurityEvent.details]. Flushed into
/// `audit_log` by [DatabaseSecurityAuditLog.flushPending] on the next
/// successful open.
class PendingSecurityEventJournal implements SecurityEventSink {
  PendingSecurityEventJournal(this._file);

  final Future<File> Function() _file;

  @override
  Future<void> record(SecurityEvent event) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${jsonEncode(event.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Best effort; nothing further can be done without the database.
    }
  }

  Future<List<SecurityEvent>> readAll() async {
    final file = await _file();
    if (!await file.exists()) {
      return const [];
    }
    final events = <SecurityEvent>[];
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final event = SecurityEvent.fromJson(
          jsonDecode(line) as Map<String, dynamic>,
        );
        if (event != null) {
          events.add(event);
        }
      } on FormatException {
        // Skip a damaged line rather than losing the rest.
      } on TypeError {
        // Same.
      }
    }
    return events;
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
