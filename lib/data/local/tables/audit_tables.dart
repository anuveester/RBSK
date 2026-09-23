import 'package:drift/drift.dart';

import '../enums.dart';
import 'reference_identity_tables.dart';

/// docs/04_DATABASE_ARCHITECTURE.md §2.11.
/// Append-only, generic across all business tables via `table_name` +
/// `record_id`. `changed_fields`/`old_values`/`new_values` are JSON-encoded
/// text. Writing to this table on every INSERT/UPDATE/SOFT_DELETE is a
/// repository-layer responsibility in a later phase — Phase 1.2 implements
/// only the storage structure.
@TableIndex.sql(
  'CREATE INDEX idx_audit_log_record ON audit_log(table_name, record_id)',
)
@TableIndex.sql('CREATE INDEX idx_audit_log_time ON audit_log(occurred_at)')
class AuditLog extends Table {
  @override
  String get tableName => 'audit_log';

  TextColumn get id => text()();
  TextColumn get businessTableName => text().named('table_name')();
  TextColumn get recordId => text()();
  TextColumn get action => textEnum<AuditAction>()();
  TextColumn get changedFields => text().nullable()(); // JSON-encoded
  TextColumn get oldValues => text().nullable()(); // JSON-encoded
  TextColumn get newValues => text().nullable()(); // JSON-encoded
  TextColumn get actorUserId => text().nullable().references(Users, #id)();
  TextColumn get actorDeviceId =>
      text().nullable().references(Devices, #id)();
  DateTimeColumn get occurredAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}
