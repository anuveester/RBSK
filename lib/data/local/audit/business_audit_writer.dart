import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:referredline/core/utils/id_generator.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/enums.dart';

/// Writes one `audit_log` row per business INSERT/UPDATE
/// (docs/04_DATABASE_ARCHITECTURE.md §5; docs/35_PHASE_1_5_PLAN.md §10).
///
/// Call it **inside** the transaction that makes the change, so the change
/// and its audit row are saved together or not at all.
///
/// `actor_user_id` is always null: the app has no authentication yet, and
/// no identity is invented. Real attribution arrives with the rebuilt
/// authentication. Rows use the business table's own name (`schools`,
/// `awcs`), never `security_event`, so they stay apart from security events.
class BusinessAuditWriter {
  const BusinessAuditWriter();

  /// [values]: every business column of the new row (snake_case names).
  Future<void> recordInsert(
    AppDatabase db, {
    required String table,
    required String recordId,
    required Map<String, Object?> values,
  }) => _write(
    db,
    table: table,
    recordId: recordId,
    action: AuditAction.INSERT,
    newValues: values,
  );

  /// [oldValues] and [newValues]: only the columns that changed.
  Future<void> recordUpdate(
    AppDatabase db, {
    required String table,
    required String recordId,
    required Map<String, Object?> oldValues,
    required Map<String, Object?> newValues,
  }) => _write(
    db,
    table: table,
    recordId: recordId,
    action: AuditAction.UPDATE,
    changedFields: newValues.keys.toList(),
    oldValues: oldValues,
    newValues: newValues,
  );

  /// A soft delete (`is_deleted` false → true), plus any other columns that
  /// changed with it (e.g. a released code) in [otherOld]/[otherNew].
  Future<void> recordSoftDelete(
    AppDatabase db, {
    required String table,
    required String recordId,
    Map<String, Object?> otherOld = const {},
    Map<String, Object?> otherNew = const {},
  }) {
    final newValues = {'is_deleted': true, ...otherNew};
    return _write(
      db,
      table: table,
      recordId: recordId,
      action: AuditAction.SOFT_DELETE,
      changedFields: newValues.keys.toList(),
      oldValues: {'is_deleted': false, ...otherOld},
      newValues: newValues,
    );
  }

  Future<void> _write(
    AppDatabase db, {
    required String table,
    required String recordId,
    required AuditAction action,
    required Map<String, Object?> newValues,
    List<String>? changedFields,
    Map<String, Object?>? oldValues,
  }) async {
    await db
        .into(db.auditLog)
        .insert(
          AuditLogCompanion.insert(
            id: generateUuidV4(),
            businessTableName: table,
            recordId: recordId,
            action: action,
            changedFields: Value(
              changedFields == null ? null : jsonEncode(changedFields),
            ),
            oldValues: Value(oldValues == null ? null : jsonEncode(oldValues)),
            newValues: Value(jsonEncode(newValues)),
            actorUserId: const Value(null),
            occurredAt: Value(DateTime.now().toUtc()),
          ),
        );
  }
}
