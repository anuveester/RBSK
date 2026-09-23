import 'package:drift/drift.dart';

import '../enums.dart';

/// docs/04_DATABASE_ARCHITECTURE.md §2.4.
///
/// Seed data: the 29 codified findings transcribed in
/// docs/14_JOB_AID_FIELD_MAPPING.md §7 (Job Aid codes 1–44, with the source's
/// own gaps). Codes 31–38 and items B6/B7 are [TBD] — absent from the
/// supplied Job Aid pages — and simply have no rows; they are never invented.
///
/// The frozen doc's `idx_disease_master_name_trgm` (Postgres GIN/pg_trgm) has
/// no SQLite equivalent and is not created here — see the equivalent note on
/// `schools`/`awcs` in school_awc_tables.dart.
@TableIndex.sql(
  'CREATE INDEX idx_disease_master_category ON disease_master(category)',
)
class DiseaseMaster extends Table {
  @override
  String get tableName => 'disease_master';

  TextColumn get id => text()();
  TextColumn get officialCode => text().nullable()(); // Job Aid code, verbatim
  TextColumn get name => text()(); // official Job Aid wording, verbatim
  TextColumn get category => textEnum<DiseaseCategory>()();
  TextColumn get applicableTo =>
      textEnum<ApplicableTo>().withDefault(const Constant('BOTH'))();
  TextColumn get description => text().nullable()();
  TextColumn get sourceReference => text().nullable()();
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

/// docs/04_DATABASE_ARCHITECTURE.md §2.4.
/// Maps handwritten register shorthand (e.g. 'Vit A', 'S.I', 'Carries') to
/// official findings so a future OCR review step can SUGGEST a match. Never
/// an automatic mapping — `is_confirmed` stays false until a human confirms
/// it. Per Phase 0.6 approval condition 2, the meaning of `S.I` is NOT
/// seeded or assumed anywhere in this phase; only structure is implemented.
@TableIndex.sql(
  'CREATE INDEX idx_disease_aliases_text '
  'ON disease_aliases(lower(alias_text))',
)
class DiseaseAliases extends Table {
  @override
  String get tableName => 'disease_aliases';

  TextColumn get id => text()();
  TextColumn get diseaseId => text().references(DiseaseMaster, #id)();
  TextColumn get aliasText => text()();
  TextColumn get sourceNote => text().nullable()();
  BoolColumn get isConfirmed =>
      boolean().withDefault(const Constant(false))();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}
