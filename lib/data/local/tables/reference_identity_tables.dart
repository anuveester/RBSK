import 'package:drift/drift.dart';

import '../enums.dart';

/// docs/04_DATABASE_ARCHITECTURE.md §2.1
class FinancialYears extends Table {
  @override
  String get tableName => 'financial_years';

  TextColumn get id => text()();
  TextColumn get label => text().unique()(); // e.g. '2025-26'
  DateTimeColumn get startDate => dateTime()(); // 01 Apr
  DateTimeColumn get endDate => dateTime()(); // 31 Mar
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}

/// docs/04_DATABASE_ARCHITECTURE.md §2.1.
/// Seed data (Team-B, FY2025-26) is loaded from the source Micro Plan at seed
/// time, not hardcoded — see docs/24_PHASE_1_2_REPORT.md.
class Staff extends Table {
  @override
  String get tableName => 'staff';

  TextColumn get id => text()();
  TextColumn get fullName => text()();
  TextColumn get designation => text().nullable()();
  TextColumn get qualification => text().nullable()();
  TextColumn get phone => text().nullable()();
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

/// docs/04_DATABASE_ARCHITECTURE.md §2.1. Append-only: never edit a past row;
/// close it (end_date) and insert a new one for a transfer/replacement.
@TableIndex.sql(
  'CREATE INDEX idx_staff_assignments_staff '
  'ON staff_assignments(staff_id, start_date)',
)
@TableIndex.sql(
  'CREATE INDEX idx_staff_assignments_dates '
  'ON staff_assignments(start_date, end_date)',
)
class StaffAssignments extends Table {
  @override
  String get tableName => 'staff_assignments';

  TextColumn get id => text()();
  TextColumn get staffId => text().references(Staff, #id)();
  TextColumn get teamLabel => text().nullable()(); // e.g. 'Team - B'
  TextColumn get roleInTeam => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()(); // null = current
  TextColumn get financialYearId =>
      text().nullable().references(FinancialYears, #id)();
  TextColumn get remarks => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}

/// docs/04_DATABASE_ARCHITECTURE.md §2.1
class Users extends Table {
  @override
  String get tableName => 'users';

  TextColumn get id => text()();
  TextColumn get staffId => text().nullable().references(Staff, #id)();
  TextColumn get email => text().nullable().unique()();
  TextColumn get phone => text().nullable()();
  TextColumn get displayName => text()();
  TextColumn get role => textEnum<AppRole>()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
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

/// docs/04_DATABASE_ARCHITECTURE.md §2.1
class Devices extends Table {
  @override
  String get tableName => 'devices';

  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get deviceLabel => text().nullable()();
  TextColumn get platform => text().nullable()();
  TextColumn get appVersion => text().nullable()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}
