import 'package:drift/drift.dart';

import '../enums.dart';
import 'awc_screening_tables.dart';
import 'reference_identity_tables.dart';
import 'school_screening_tables.dart';
import 'screening_session_tables.dart';
import 'visit_planning_tables.dart';

/// docs/04_DATABASE_ARCHITECTURE.md §2.10.
///
/// Originals are preserved untouched; processed images are separate rows in
/// `RegisterPhotoDerivatives`; OCR output and human corrections are stored
/// separately with an explicit verification status. [USER-DECIDED]
/// Soft-delete only — the original is never purged. `quality_flags` is
/// JSON-encoded text (blur/glare/skew heuristics from capture-time check).
///
/// Phase 1.2 implements only these structures; camera capture, image
/// processing and OCR itself are explicitly out of scope (Phase 1.2
/// instruction §10).
@TableIndex.sql(
  'CREATE INDEX idx_register_photos_visit '
  'ON register_photos(visit_plan_id, sequence_no)',
)
class RegisterPhotos extends Table {
  @override
  String get tableName => 'register_photos';

  TextColumn get id => text()();
  TextColumn get visitPlanId => text().references(VisitPlans, #id)();
  TextColumn get screeningSessionId =>
      text().nullable().references(ScreeningSessions, #id)();
  TextColumn get classLabel => text().nullable()();
  TextColumn get pageLabel => text().nullable()(); // e.g. 'April 2026' heading
  IntColumn get sequenceNo => integer().nullable()();
  TextColumn get localFilePath => text().nullable()();
  TextColumn get storagePath => text().nullable()();
  TextColumn get checksum => text().nullable()();
  TextColumn get capturedBy => text().references(Users, #id)();
  DateTimeColumn get capturedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
  TextColumn get deviceId => text().nullable().references(Devices, #id)();
  TextColumn get uploadStatus =>
      textEnum<UploadStatus>().withDefault(const Constant('LOCAL_ONLY'))();
  TextColumn get qualityFlags => text().nullable()(); // JSON-encoded
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}

/// docs/04_DATABASE_ARCHITECTURE.md §2.10.
/// Preprocessing output NEVER overwrites the original — each variant is its
/// own row, with reproducible `parameters` (rotation angle, crop box, etc.,
/// JSON-encoded).
@TableIndex.sql(
  'CREATE INDEX idx_photo_derivatives '
  'ON register_photo_derivatives(register_photo_id)',
)
class RegisterPhotoDerivatives extends Table {
  @override
  String get tableName => 'register_photo_derivatives';

  TextColumn get id => text()();
  TextColumn get registerPhotoId => text().references(RegisterPhotos, #id)();
  TextColumn get kind => textEnum<DerivativeKind>()();
  TextColumn get storagePath => text().nullable()();
  TextColumn get localFilePath => text().nullable()();
  TextColumn get parameters => text().nullable()(); // JSON-encoded
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}

/// docs/04_DATABASE_ARCHITECTURE.md §2.10
@TableIndex.sql('CREATE INDEX idx_ocr_jobs_photo ON ocr_jobs(register_photo_id)')
@TableIndex.sql('CREATE INDEX idx_ocr_jobs_status ON ocr_jobs(status)')
class OcrJobs extends Table {
  @override
  String get tableName => 'ocr_jobs';

  TextColumn get id => text()();
  TextColumn get registerPhotoId => text().references(RegisterPhotos, #id)();
  TextColumn get status =>
      textEnum<OcrJobStatus>().withDefault(const Constant('QUEUED'))();
  TextColumn get engineName => text().nullable()();
  TextColumn get engineVersion => text().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}

/// docs/04_DATABASE_ARCHITECTURE.md §2.10.
///
/// Append-only: one row per detected register row. HARD RULE [CONFIRMED]: a
/// screening record is created from an OCR result only when
/// `verification_status = 'CONFIRMED'` by a human — enforced at the
/// repository layer in a later phase (OCR itself is out of scope for
/// Phase 1.2). Raw `extracted_fields` are never overwritten by
/// `corrected_fields` — the two are always stored separately.
@TableIndex.sql('CREATE INDEX idx_ocr_results_job ON ocr_results(ocr_job_id)')
@TableIndex.sql(
  'CREATE INDEX idx_ocr_results_status '
  'ON ocr_results(verification_status)',
)
class OcrResults extends Table {
  @override
  String get tableName => 'ocr_results';

  TextColumn get id => text()();
  TextColumn get ocrJobId => text().references(OcrJobs, #id)();
  IntColumn get rowIndex => integer()();
  TextColumn get sourceRegion => text().nullable()(); // JSON-encoded bbox
  TextColumn get extractedFields => text()(); // JSON-encoded, never edited
  TextColumn get confidenceScores => text().nullable()(); // JSON-encoded
  TextColumn get correctedFields => text().nullable()(); // JSON-encoded
  TextColumn get verificationStatus => textEnum<VerificationStatus>()
      .withDefault(const Constant('UNREVIEWED'))();
  TextColumn get duplicateCandidateOf => text().nullable()();
  TextColumn get reviewedBy => text().nullable().references(Users, #id)();
  DateTimeColumn get reviewedAt => dateTime().nullable()();
  TextColumn get linkedSchoolScreeningId =>
      text().nullable().references(SchoolScreenings, #id)();
  TextColumn get linkedAwcScreeningId =>
      text().nullable().references(AwcScreenings, #id)();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column> get primaryKey => {id};
}
