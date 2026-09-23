import 'package:drift/drift.dart';

import '../enums.dart';
import 'disease_master_tables.dart';
import 'referral_configuration_tables.dart';
import 'register_photo_tables.dart';
import 'screening_session_tables.dart';
import 'visit_planning_tables.dart';

/// docs/04_DATABASE_ARCHITECTURE.md §2.7 (full structured form — Option B,
/// Phase 0.6 approval condition B). Core record; findings and the full
/// checklist catalogue/responses are separate tables below so the form can
/// grow with the source Job Aid without schema churn.
///
/// Classification columns are USER-SELECTED from the Job Aid's own reference
/// charts — those charts were not supplied, so the app never auto-computes
/// an SD band. `aadhaar_number` stays [TBD] per Phase 0.6 approval condition
/// 3: present because the Job Aid has the field, never required or seeded.
@TableIndex.sql(
  'CREATE UNIQUE INDEX uq_awc_screening_serial '
  'ON awc_screenings(visit_plan_id, serial_no)',
)
@TableIndex.sql(
  'CREATE INDEX idx_awc_screenings_visit ON awc_screenings(visit_plan_id)',
)
@TableIndex.sql(
  'CREATE INDEX idx_awc_screenings_date ON awc_screenings(screening_date)',
)
class AwcScreenings extends Table {
  @override
  String get tableName => 'awc_screenings';

  TextColumn get id => text()();
  TextColumn get visitPlanId => text().references(VisitPlans, #id)();
  TextColumn get screeningSessionId =>
      text().nullable().references(ScreeningSessions, #id)();
  IntColumn get serialNo => integer()();
  DateTimeColumn get screeningDate => dateTime()();

  // Preliminary Particulars (Job Aid p.1) [SOURCE-DERIVED]
  TextColumn get childName => text()();
  DateTimeColumn get dob => dateTime().nullable()();
  IntColumn get ageMonths => integer().nullable()();
  TextColumn get gender => textEnum<Gender>()();
  TextColumn get fatherGuardianName => text().nullable()();
  TextColumn get motherName => text().nullable()();
  TextColumn get contactNumber => text().nullable()();
  TextColumn get mctsNo => text().nullable()(); // 16-digit on form
  TextColumn get uniqueIdNo => text().nullable()(); // 16-digit on form
  TextColumn get aadhaarNumber => text().nullable()(); // [TBD]
  TextColumn get ashaName => text().nullable()();
  TextColumn get ashaContactNo => text().nullable()();
  TextColumn get ashaId => text().nullable()();
  TextColumn get mobileHealthTeamId => text().nullable()();
  TextColumn get awcNameSnapshot => text().nullable()();
  TextColumn get districtBlockSnapshot => text().nullable()();

  // Anthropometry + official classifications (Job Aid p.1) [SOURCE-DERIVED]
  RealColumn get weightKg => real().nullable()();
  RealColumn get heightLengthCm => real().nullable()();
  RealColumn get headCircumferenceCm => real().nullable()();
  RealColumn get muacCm => real().nullable()(); // conditional, UI-enforced
  TextColumn get weightForAgeClassification =>
      textEnum<AnthroClassification>().nullable()();
  TextColumn get weightForLengthClassification =>
      textEnum<AnthroClassification>().nullable()();
  TextColumn get heightForAgeClassification =>
      textEnum<AnthroClassification>().nullable()();
  TextColumn get headCircumferenceClassification =>
      textEnum<AnthroClassification>().nullable()();
  TextColumn get muacClassification =>
      textEnum<MuacClassification>().nullable()();

  // Sign-off block (Job Aid p.4) [SOURCE-DERIVED]
  TextColumn get doctorMhtName => text().nullable()();
  DateTimeColumn get visitDate => dateTime().nullable()();
  BoolColumn get dataEnteredInRegister => boolean().nullable()();
  TextColumn get registerEnteredBy => text().nullable()();
  TextColumn get registerPageRef => text().nullable()();

  TextColumn get remarks => text().nullable()();
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
    'CHECK (age_months IS NULL OR (age_months BETWEEN 0 AND 83))',
  ];
}

/// docs/04_DATABASE_ARCHITECTURE.md §2.7
@TableIndex.sql(
  'CREATE INDEX idx_asf_screening '
  'ON awc_screening_findings(awc_screening_id)',
)
@TableIndex.sql(
  'CREATE INDEX idx_asf_disease ON awc_screening_findings(disease_id)',
)
class AwcScreeningFindings extends Table {
  @override
  String get tableName => 'awc_screening_findings';

  TextColumn get id => text()();
  TextColumn get awcScreeningId => text().references(AwcScreenings, #id)();
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

/// docs/04_DATABASE_ARCHITECTURE.md §2.7 "Checklist item catalogue".
///
/// Versioned catalogue of Job Aid items: adding/correcting items later means
/// new rows under a new `version`, never edits to historical ones, so past
/// responses keep their original meaning. `option_list` is JSON-encoded text
/// (SQLite has no native jsonb type — see docs/24_PHASE_1_2_REPORT.md for the
/// jsonb-to-TEXT mapping used throughout this schema).
///
/// No rows are seeded in Phase 1.2 for items absent/illegible in the supplied
/// Job Aid pages (B6, B7, D10.3.1, D10.3.2, codes 31–38) — Phase 1.2
/// instruction §12 / Phase 0.6 approval condition 2.
@TableIndex.sql(
  'CREATE UNIQUE INDEX uq_awc_checklist_item '
  'ON awc_checklist_items(version, item_code)',
)
@TableIndex.sql(
  'CREATE INDEX idx_awc_checklist_section '
  'ON awc_checklist_items(version, section, display_order)',
)
class AwcChecklistItems extends Table {
  @override
  String get tableName => 'awc_checklist_items';

  TextColumn get id => text()();
  TextColumn get version => text()(); // e.g. 'JOBAID-0-6Y-2026-09'
  TextColumn get section => textEnum<ChecklistSection>()();
  TextColumn get itemCode => text()(); // 'A1', 'C7.1.1', 'D5.3' — verbatim
  TextColumn get parentItemCode => text().nullable()();
  TextColumn get label => text()(); // official wording, verbatim
  TextColumn get responseType => textEnum<ChecklistResponseType>()();
  TextColumn get optionList => text().nullable()(); // JSON-encoded list
  TextColumn get polarity => textEnum<ReferPolarity>()();
  TextColumn get domainTag => text().nullable()(); // GM/FM/V/C/H/Sp/S
  IntColumn get ageBandMinMonths => integer().nullable()();
  IntColumn get ageBandMaxMonths => integer().nullable()();
  IntColumn get displayOrder => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get sourceReference => text().nullable()();
  BoolColumn get isUncertain =>
      boolean().withDefault(const Constant(false))();
  TextColumn get uncertaintyNote => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}

/// docs/04_DATABASE_ARCHITECTURE.md §2.7 "responses". Records what the
/// clinician observed; it does NOT compute a diagnosis or auto-derive a
/// finding — see the same section's note on why checklist→finding inference
/// is [NOT YET IMPLEMENTED].
@TableIndex.sql(
  'CREATE UNIQUE INDEX uq_awc_response '
  'ON awc_screening_checklist_responses(awc_screening_id, checklist_item_id)',
)
@TableIndex.sql(
  'CREATE INDEX idx_awc_response_screening '
  'ON awc_screening_checklist_responses(awc_screening_id)',
)
class AwcScreeningChecklistResponses extends Table {
  @override
  String get tableName => 'awc_screening_checklist_responses';

  TextColumn get id => text()();
  TextColumn get awcScreeningId => text().references(AwcScreenings, #id)();
  TextColumn get checklistItemId =>
      text().references(AwcChecklistItems, #id)();
  TextColumn get itemCodeSnapshot => text()(); // survives catalogue versioning
  BoolColumn get responseBoolean => boolean().nullable()();
  TextColumn get responseText => text().nullable()();
  RealColumn get responseNumeric => real().nullable()();
  TextColumn get responseOptions => text().nullable()(); // JSON-encoded list
  BoolColumn get notApplicable =>
      boolean().withDefault(const Constant(false))();
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
