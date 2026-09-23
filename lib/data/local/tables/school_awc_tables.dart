import 'package:drift/drift.dart';

import 'reference_identity_tables.dart';

/// docs/04_DATABASE_ARCHITECTURE.md §2.2.
/// Uniqueness on `official_school_code` is enforced only among non-blank
/// values — multiple blank codes are valid and expected. [CONFIRMED]
///
/// The frozen doc's `idx_schools_name_trgm` (Postgres GIN/pg_trgm) has no
/// SQLite equivalent and is intentionally not created here; it applies only
/// to the cloud Postgres schema in a later phase. Name search on-device uses
/// a plain LIKE query, which is adequate at this data volume.
@TableIndex.sql(
  'CREATE UNIQUE INDEX uq_schools_code ON schools(official_school_code) '
  "WHERE official_school_code IS NOT NULL AND official_school_code <> ''",
)
@TableIndex.sql('CREATE INDEX idx_schools_geo ON schools(district, block)')
class Schools extends Table {
  @override
  String get tableName => 'schools';

  TextColumn get id => text()();
  // BLANK STAYS BLANK, never invented. [USER-DECIDED]
  TextColumn get officialSchoolCode => text().nullable()();
  TextColumn get name => text()();
  TextColumn get institutionType => text().nullable()(); // PS, UPS, COM
  TextColumn get district => text().nullable()();
  TextColumn get block => text().nullable()();
  TextColumn get panchayatVillage => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get dataQualityNotes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
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

/// docs/04_DATABASE_ARCHITECTURE.md §2.2.
///
/// AWC identity strategy [USER-DECIDED]: database identity is the internal
/// UUID. `official_awc_code` is a nullable business identifier that stays
/// NULL until a genuine government code is supplied — no uniqueness violation
/// is possible while every row is NULL, and none will be invented to create
/// one. `source_plan_awc_code` is the small integer from the Micro Plan —
/// deliberately NOT unique-constrained; the same value maps to different real
/// AWCs across months in 15+ documented cases
/// (docs/16_PHASE0_DATABASE_REVIEW.md §2), so it is retained only as a
/// non-authoritative reference value.
///
/// (As with `schools`, the frozen doc's `idx_awcs_name_trgm` is Postgres-only
/// and is not created in this local SQLite schema.)
@TableIndex.sql(
  'CREATE UNIQUE INDEX uq_awcs_official_code ON awcs(official_awc_code) '
  "WHERE official_awc_code IS NOT NULL AND official_awc_code <> ''",
)
@TableIndex.sql('CREATE INDEX idx_awcs_geo ON awcs(district, block)')
class Awcs extends Table {
  @override
  String get tableName => 'awcs';

  TextColumn get id => text()();
  TextColumn get officialAwcCode => text().nullable()();
  // NO unique index on this column — deliberately. [USER-DECIDED]
  TextColumn get sourcePlanAwcCode => text().nullable()();
  TextColumn get name => text()();
  IntColumn get subcentreNo => integer().nullable()();
  TextColumn get panchayatVillage => text().nullable()();
  TextColumn get block => text().nullable()();
  TextColumn get district => text().nullable()();
  TextColumn get dataQualityNotes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
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

/// docs/04_DATABASE_ARCHITECTURE.md §2.2
class PlanImports extends Table {
  @override
  String get tableName => 'plan_imports';

  TextColumn get id => text()();
  TextColumn get financialYearId => text().references(FinancialYears, #id)();
  TextColumn get sourceFilename => text()();
  TextColumn get importedBy => text().references(Users, #id)();
  DateTimeColumn get importedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
  IntColumn get rowCount => integer().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
