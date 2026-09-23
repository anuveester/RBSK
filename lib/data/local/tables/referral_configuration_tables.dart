import 'package:drift/drift.dart';

import '../enums.dart';

/// docs/04_DATABASE_ARCHITECTURE.md §2.8; full seed data and routing rules in
/// docs/20_REFERRAL_CONFIGURATION.md.
///
/// Replaces a single hard-coded referral enum. School (PHC/CHC, District
/// Hospital, Higher Center) and AWC (PHC, CHC, DH, DEIC, NRC) vocabularies are
/// configured separately via `ReferralDestinationContexts` below and are
/// NEVER merged into one shared list. [USER-DECIDED]
class ReferralDestinations extends Table {
  @override
  String get tableName => 'referral_destinations';

  TextColumn get id => text()();
  TextColumn get code => text().unique()();
  TextColumn get label => text()();
  TextColumn get description => text().nullable()();
  TextColumn get sourceReference => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
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

/// Which destinations are offered in which workflow, optionally narrowed by
/// finding category. A NULL `finding_category` means "all categories in this
/// context". docs/04_DATABASE_ARCHITECTURE.md §2.8.
///
/// The unique index below is a direct SQLite translation of the frozen
/// Postgres index `uq_ref_dest_context(...coalesce(finding_category::text,
/// '*'))` — SQLite has no `::text` cast syntax and none is needed since
/// `finding_category` is already stored as TEXT; `COALESCE` behaves
/// identically on both engines.
@TableIndex.sql(
  'CREATE UNIQUE INDEX uq_ref_dest_context ON referral_destination_contexts('
  "referral_destination_id, context, COALESCE(finding_category, '*'))",
)
@TableIndex.sql(
  'CREATE INDEX idx_ref_dest_context_lookup '
  'ON referral_destination_contexts(context, finding_category)',
)
class ReferralDestinationContexts extends Table {
  @override
  String get tableName => 'referral_destination_contexts';

  TextColumn get id => text()();
  TextColumn get referralDestinationId =>
      text().references(ReferralDestinations, #id)();
  TextColumn get context => textEnum<LocationType>()(); // 'SCHOOL' | 'AWC'
  TextColumn get findingCategory =>
      textEnum<DiseaseCategory>().nullable()(); // NULL = applies to all
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  TextColumn get sourceReference => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}
