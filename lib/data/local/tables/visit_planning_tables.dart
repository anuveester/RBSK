import 'package:drift/drift.dart';

import '../enums.dart';
import 'reference_identity_tables.dart';
import 'school_awc_tables.dart';

/// docs/04_DATABASE_ARCHITECTURE.md §2.3.
///
/// `original_planned_date` is set once at insert and never updated by any
/// code path other than the initial insert — enforced at the repository
/// layer in a later phase; the column itself has no DB-level immutability
/// mechanism in SQLite. `planned_date` changes only via a logged reschedule
/// that writes `visit_status_history`. [CONFIRMED]
///
/// Planned/enrolment snapshot columns are stored EXACTLY as given in the
/// source Micro Plan, including rows where male+female <> total. They are
/// NEVER reconciled with or derived from actual screening counts.
/// [USER-DECIDED] [SOURCE-DERIVED]
@TableIndex.sql(
  'CREATE INDEX idx_visit_plans_fy_date '
  'ON visit_plans(financial_year_id, planned_date)',
)
@TableIndex.sql(
  'CREATE INDEX idx_visit_plans_school ON visit_plans(school_id)',
)
@TableIndex.sql('CREATE INDEX idx_visit_plans_awc ON visit_plans(awc_id)')
@TableIndex.sql(
  'CREATE INDEX idx_visit_plans_status ON visit_plans(status)',
)
class VisitPlans extends Table {
  @override
  String get tableName => 'visit_plans';

  TextColumn get id => text()();
  TextColumn get financialYearId => text().references(FinancialYears, #id)();
  TextColumn get locationType => textEnum<LocationType>()();
  TextColumn get schoolId => text().nullable().references(Schools, #id)();
  TextColumn get awcId => text().nullable().references(Awcs, #id)();
  TextColumn get planImportId =>
      text().nullable().references(PlanImports, #id)();
  DateTimeColumn get originalPlannedDate => dateTime()(); // IMMUTABLE
  DateTimeColumn get plannedDate => dateTime()();
  DateTimeColumn get actualVisitDate => dateTime().nullable()();
  TextColumn get status =>
      textEnum<VisitStatus>().withDefault(const Constant('PLANNED'))();
  BoolColumn get isSpecialVisit =>
      boolean().withDefault(const Constant(false))();
  IntColumn get plannedMaleCount => integer().nullable()();
  IntColumn get plannedFemaleCount => integer().nullable()();
  IntColumn get plannedTotalCount => integer().nullable()();
  TextColumn get contactPerson => text().nullable()();
  TextColumn get contactNumber => text().nullable()();
  TextColumn get sourceSheet => text().nullable()(); // e.g. 'APRIL25'
  IntColumn get sourceRow => integer().nullable()();
  TextColumn get dataQualityNotes => text().nullable()();
  TextColumn get remarks => text().nullable()();
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

  @override
  List<String> get customConstraints => [
    'CHECK ('
        "(location_type = 'SCHOOL' AND school_id IS NOT NULL AND awc_id IS NULL) OR "
        "(location_type = 'AWC' AND awc_id IS NOT NULL AND school_id IS NULL)"
        ')',
  ];
}

/// docs/04_DATABASE_ARCHITECTURE.md §2.3.
/// Planned holidays imported from the Micro Plan, and manually-added
/// unexpected holidays. Referenced (not required) by `visit_status_history`
/// when a visit was missed because of a holiday.
@TableIndex.sql('CREATE INDEX idx_holidays_date ON holidays(holiday_date)')
class Holidays extends Table {
  @override
  String get tableName => 'holidays';

  TextColumn get id => text()();
  TextColumn get financialYearId =>
      text().nullable().references(FinancialYears, #id)();
  DateTimeColumn get holidayDate => dateTime()();
  TextColumn get name => text()();
  TextColumn get reason => text().nullable()();
  TextColumn get remarks => text().nullable()();
  BoolColumn get isManualAddition =>
      boolean().withDefault(const Constant(false))();
  TextColumn get planImportId =>
      text().nullable().references(PlanImports, #id)();
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

/// docs/04_DATABASE_ARCHITECTURE.md §2.3.
/// Append-only lifecycle log. MISSED and RESCHEDULED screens are filtered
/// views over `visit_plans` + this table, never separate tables. [CONFIRMED]
@TableIndex.sql(
  'CREATE INDEX idx_visit_status_history_plan '
  'ON visit_status_history(visit_plan_id, changed_at)',
)
class VisitStatusHistory extends Table {
  @override
  String get tableName => 'visit_status_history';

  TextColumn get id => text()();
  TextColumn get visitPlanId => text().references(VisitPlans, #id)();
  TextColumn get fromStatus => textEnum<VisitStatus>().nullable()();
  TextColumn get toStatus => textEnum<VisitStatus>()();
  DateTimeColumn get fromDate => dateTime().nullable()();
  DateTimeColumn get toDate => dateTime().nullable()();
  TextColumn get missedReason => textEnum<MissedReason>().nullable()();
  TextColumn get reasonRemarks => text().nullable()();
  TextColumn get relatedHolidayId =>
      text().nullable().references(Holidays, #id)();
  TextColumn get changedBy => text().references(Users, #id)();
  DateTimeColumn get changedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}
