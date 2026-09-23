import 'package:drift/drift.dart';

import '../enums.dart';
import 'awc_screening_tables.dart';
import 'referral_configuration_tables.dart';
import 'school_screening_tables.dart';

/// docs/04_DATABASE_ARCHITECTURE.md §2.9.
///
/// Defaults are deliberate and NEVER auto-upgraded by the system:
/// child_attended=NO, treatment=NOT_DONE, further_referral=false.
/// [CONFIRMED] Multiple follow-up rows per child are expected and all are
/// retained — this table is never overwritten in place for a repeat visit.
@TableIndex.sql(
  'CREATE INDEX idx_treatment_school_screening '
  'ON treatment_records(school_screening_id)',
)
@TableIndex.sql(
  'CREATE INDEX idx_treatment_awc_screening '
  'ON treatment_records(awc_screening_id)',
)
@TableIndex.sql(
  'CREATE INDEX idx_treatment_date '
  'ON treatment_records(treatment_visit_date)',
)
@TableIndex.sql(
  'CREATE INDEX idx_treatment_pending '
  'ON treatment_records(child_attended, treatment)',
)
class TreatmentRecords extends Table {
  @override
  String get tableName => 'treatment_records';

  TextColumn get id => text()();
  TextColumn get schoolScreeningId =>
      text().nullable().references(SchoolScreenings, #id)();
  TextColumn get awcScreeningId =>
      text().nullable().references(AwcScreenings, #id)();
  DateTimeColumn get treatmentVisitDate => dateTime()();
  TextColumn get childAttended =>
      textEnum<AttendedStatus>().withDefault(const Constant('NO'))();
  TextColumn get treatment =>
      textEnum<TreatmentStatus>().withDefault(const Constant('NOT_DONE'))();
  BoolColumn get furtherReferral =>
      boolean().withDefault(const Constant(false))();
  TextColumn get furtherReferralDestinationId =>
      text().nullable().references(ReferralDestinations, #id)();
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
        '(school_screening_id IS NOT NULL AND awc_screening_id IS NULL) OR '
        '(awc_screening_id IS NOT NULL AND school_screening_id IS NULL)'
        ')',
    'CHECK ('
        '(further_referral = 0 AND further_referral_destination_id IS NULL) OR '
        '(further_referral = 1 AND further_referral_destination_id IS NOT NULL)'
        ')',
  ];
}
