import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:pointycastle/digests/sha256.dart';
import 'package:referredline/core/security/crypto_utils.dart';
import 'package:referredline/core/utils/id_generator.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/enums.dart';

/// Security-relevant operations recorded in the audit trail.
enum SecurityEventType {
  backupKeyCreated,
  backupExportCreated,
  backupExportFailed,
  backupImportAttempted,
  backupImportSucceeded,
  backupImportRejected,
  databaseRecoveryAttempted,
  databaseRecoverySucceeded,
  databaseRecoveryFailed,
  databaseKeyUnavailable,

  /// A restore that failed part-way was undone; the previous data is back.
  restoreRolledBack,

  /// A restore interrupted by a crash or power loss was finished or undone
  /// at the next start.
  interruptedRestoreResolved,
}

/// The only keys allowed in [SecurityEvent.details]. Anything else is
/// dropped before it can be written, so a future caller cannot put a
/// secret, a path or health data into the audit trail by accident.
const Set<String> securityEventDetailKeys = {
  'backupKeyId',
  'context',
  'databaseBytes',
  'outcome',
  'packageId',
  'preservedDatabaseFile',
  'reason',
};

final RegExp _safeDetailValue = RegExp(r'^[A-Za-z0-9._:-]{1,80}$');

/// Keeps only allowlisted keys whose values are short, plain tokens (no
/// slashes, spaces or other characters that a path or free text needs).
Map<String, String> _sanitizeDetails(Map<String, String>? details) => {
  for (final e in (details ?? const <String, String>{}).entries)
    if (securityEventDetailKeys.contains(e.key) &&
        _safeDetailValue.hasMatch(e.value))
      e.key: e.value,
};

/// One security event.
///
/// [details] holds **only** non-secret, machine-readable values: reason
/// codes, record ids, counts, package ids. Never a PIN, a recovery code, a
/// key, a salt, a verifier, a file path, or any child/health data. This is
/// enforced: see [securityEventDetailKeys].
///
/// [id] is fixed when the event is created and becomes the `audit_log` row
/// id, so writing the same event twice (e.g. replaying the journal after a
/// crash) stores it once.
class SecurityEvent {
  SecurityEvent(
    this.type, {
    this.subjectUserId,
    this.actorUserId,
    Map<String, String>? details,
    DateTime? occurredAt,
    String? id,
  }) : id = id ?? generateUuidV4(),
       details = Map.unmodifiable(_sanitizeDetails(details)),
       occurredAt = (occurredAt ?? DateTime.now()).toUtc();

  final String id;
  final SecurityEventType type;

  /// The user the event is about (e.g. whose PIN was reset).
  final String? subjectUserId;

  /// The authenticated user who performed it, if any.
  final String? actorUserId;

  final Map<String, String> details;
  final DateTime occurredAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'event': type.name,
    'subjectUserId': subjectUserId,
    'actorUserId': actorUserId,
    'details': details,
    'occurredAt': occurredAt.toIso8601String(),
  };

  /// [fallbackId] identifies an event journaled without an id, so it too is
  /// stored only once however often it is replayed.
  static SecurityEvent? fromJson(
    Map<String, dynamic> json, {
    required String fallbackId,
  }) {
    final type = SecurityEventType.values
        .where((t) => t.name == json['event'])
        .firstOrNull;
    final occurredAt = DateTime.tryParse('${json['occurredAt']}');
    final details = json['details'];
    if (type == null || occurredAt == null || details is! Map) {
      return null;
    }
    final id = json['id'];
    return SecurityEvent(
      type,
      subjectUserId: json['subjectUserId'] as String?,
      actorUserId: json['actorUserId'] as String?,
      details: {for (final e in details.entries) '${e.key}': '${e.value}'},
      occurredAt: occurredAt,
      id: id is String && id.isNotEmpty ? id : fallbackId,
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
/// `id` = the event's own id, `table_name = 'security_event'`,
/// `action = INSERT` (a security-event record is inserted), `record_id` =
/// the affected user (or the event id), `new_values` = the event type, time
/// and non-secret details.
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
  /// On any failure the journal is kept for the next attempt. Replaying a
  /// journal again (e.g. after a crash between the insert and the clear)
  /// adds nothing, because rows are keyed by [SecurityEvent.id].
  Future<void> flushPending(PendingSecurityEventJournal journal) async {
    try {
      await journal.drain(
        (events) => _db.transaction(() async {
          for (final event in events) {
            await _insert(event);
          }
        }),
      );
    } catch (_) {
      // Leave the journal in place.
    }
  }

  Future<void> _insert(SecurityEvent event) async {
    final id = event.id;
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
          mode: InsertMode.insertOrIgnore,
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

  // Appends and drains are serialized (across instances, which share the
  // file), so an event recorded while the journal is being flushed is never
  // cleared together with the flushed ones.
  static Future<void> _tail = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<void> record(SecurityEvent event) => _serialized(() async {
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
  });

  Future<List<SecurityEvent>> readAll() => _serialized(_readAll);

  /// Hands every journaled event to [store], and clears the journal only if
  /// [store] completes. Nothing can be appended in between.
  Future<void> drain(Future<void> Function(List<SecurityEvent>) store) =>
      _serialized(() async {
        final events = await _readAll();
        if (events.isEmpty) {
          return;
        }
        await store(events);
        await _clear();
      });

  Future<void> clear() => _serialized(_clear);

  Future<List<SecurityEvent>> _readAll() async {
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
          fallbackId: _idFromLine(line),
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

  Future<void> _clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }

  static String _idFromLine(String line) =>
      'journal-${bytesToHex(SHA256Digest().process(Uint8List.fromList(utf8.encode(line)))).substring(0, 32)}';
}
