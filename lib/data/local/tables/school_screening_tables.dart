import 'package:drift/drift.dart';

import '../enums.dart';
import 'disease_master_tables.dart';
import 'referral_configuration_tables.dart';
import 'register_photo_tables.dart';
import 'screening_session_tables.dart';
import 'visit_planning_tables.dart';

/// docs/04_DATABASE_ARCHITECTURE.md §2.6.
///
/// Normal children are first-class records [USER-DECIDED]: every screened
/// child gets a row here regardless of outcome. A normal child simply has
/// ZERO `SchoolScreeningFindings` rows — there is no "normal" flag, and no
/// fake NORMAL/NONE/NO_DISEASE sentinel value is ever written (Phase 0.6
/// approval condition 7 / Phase 1.2 instruction §9).
///
/// `class_label` is nullable because the real physical register
/// (docs/18_REGISTER_SAMPLE_ANALYSIS.md) has no Class column at all —
/// OCR-imported rows may lack it even though app-entered rows always carry
/// session context. This is unchanged from the frozen schema (Phase 0.6
/// approval condition 6: the paper sample's gaps do not drive schema change;
/// this nullability was already a frozen v1.0 decision, not a new one).
@TableIndex.sql(
  'CREATE UNIQUE INDEX uq_school_screening_serial '
  'ON school_screenings(visit_plan_id, serial_no)',
)
@TableIndex.sql(
  'CREATE INDEX idx_school_screenings_visit '
  'ON school_screenings(visit_plan_id)',
)
@TableIndex.sql(
  'CREATE INDEX idx_school_screenings_class '
  'ON school_screenings(visit_plan_id, class_label)',
)
@TableIndex.sql(
  'CREATE INDEX idx_school_screenings_date '
  'ON school_screenings(screening_date)',
)
class SchoolScreenings extends Table {
  @override
  String get tableName => 'school_screenings';

  TextColumn get id => text()();
  TextColumn get visitPlanId => text().references(VisitPlans, #id)();
  TextColumn get screeningSessionId =>
      text().nullable().references(ScreeningSessions, #id)();
  IntColumn get serialNo => integer()(); // app-assigned, scoped per visit_plan
  TextColumn get classLabel => text().nullable()();
  DateTimeColumn get screeningDate => dateTime()();
  TextColumn get childName => text()();
  IntColumn get ageYears => integer().nullable()();
  IntColumn get ageMonths => integer().nullable()();
  TextColumn get gender => textEnum<Gender>()();
  TextColumn get motherName => text().nullable()();
  TextColumn get fatherName => text().nullable()();
  TextColumn get remarks => text().nullable()(); // register's trailing column
  TextColumn get sourcePhotoId =>
      text().nullable().references(RegisterPhotos, #id)();
  TextColumn get ocrResultId =>
      text().nullable().references(OcrResults, #id)();
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
    'CHECK (age_years IS NULL OR (age_years BETWEEN 0 AND 20))',
    'CHECK (age_months IS NULL OR (age_months BETWEEN 0 AND 240))',
  ];
}

/// docs/04_DATABASE_ARCHITECTURE.md §2.6.
/// `referral_destination_id` is nullable because a finding may be recorded
/// before the referral decision is made; the UI requires it for School
/// findings at that point, matching register practice.
@TableIndex.sql(
  'CREATE INDEX idx_ssf_screening '
  'ON school_screening_findings(school_screening_id)',
)
@TableIndex.sql(
  'CREATE INDEX idx_ssf_disease '
  'ON school_screening_findings(disease_id)',
)
class SchoolScreeningFindings extends Table {
  @override
  String get tableName => 'school_screening_findings';

  TextColumn get id => text()();
  TextColumn get schoolScreeningId =>
      text().references(SchoolScreenings, #id)();
  TextColumn get diseaseId => text().references(DiseaseMaster, #id)();
  TextColumn get diseaseCategorySnapshot => textEnum<DiseaseCategory>()();
  TextColumn get referralDestinationId =>
      text().nullable().references(ReferralDestinations, #id)();
  TextColumn get referralRemarks => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}
