import 'package:drift/drift.dart';

import '../enums.dart';
import 'reference_identity_tables.dart';
import 'visit_planning_tables.dart';

/// docs/04_DATABASE_ARCHITECTURE.md §2.5.
///
/// Supports "select School + Date + Class once, then enter many children".
/// The context is ALSO materialized onto each child row (school_screenings /
/// awc_screenings) so historical records stay correct even if a session is
/// later edited. [USER-DECIDED] Changing class mid-visit closes the current
/// session and opens a new one under the same `visit_plan_id`.
@TableIndex.sql(
  'CREATE INDEX idx_screening_sessions_visit '
  'ON screening_sessions(visit_plan_id, status)',
)
class ScreeningSessions extends Table {
  @override
  String get tableName => 'screening_sessions';

  TextColumn get id => text()();
  TextColumn get visitPlanId => text().references(VisitPlans, #id)();
  TextColumn get locationType => textEnum<LocationType>()();
  TextColumn get classLabel => text().nullable()(); // School only
  DateTimeColumn get sessionDate => dateTime()();
  TextColumn get status =>
      textEnum<SessionStatus>().withDefault(const Constant('ACTIVE'))();
  TextColumn get startedBy => text().references(Users, #id)();
  DateTimeColumn get startedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
  DateTimeColumn get closedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
  TextColumn get updatedBy => text().nullable()();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
  IntColumn get rowVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}
