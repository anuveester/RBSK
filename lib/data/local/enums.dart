// ignore_for_file: constant_identifier_names
//
// Dart enums mirroring every Postgres ENUM type in the frozen schema
// (docs/04_DATABASE_ARCHITECTURE.md §2). Member names are kept identical to the
// frozen doc's enum values (not renamed to lowerCamelCase) because `textEnum<T>()`
// columns (see tables/*.dart) store `T.name` verbatim as the SQLite TEXT value —
// keeping the names identical means the on-disk value matches the frozen spec
// exactly, and matches the eventual Postgres enum values one-for-one.

/// §2.1 `app_role`
enum AppRole { ADMIN, MEDICAL_OFFICER, TEAM_MEMBER }

/// §2.3 `location_type`
enum LocationType { SCHOOL, AWC }

/// §2.3 `visit_status`
enum VisitStatus { PLANNED, IN_PROGRESS, COMPLETED, MISSED, RESCHEDULED }

/// §2.3 `missed_reason`
enum MissedReason {
  SCHOOL_CLOSED,
  HOLIDAY,
  TEAM_UNAVAILABLE,
  OFFICIAL_DUTY,
  WEATHER,
  OTHER,
}

/// §2.4 `disease_category`
enum DiseaseCategory {
  DEFECTS_AT_BIRTH,
  DEFICIENCIES,
  DISEASES,
  DEVELOPMENTAL_DELAY_DISABILITY,
  OTHERS,
}

/// §2.4 `applicable_to`
enum ApplicableTo { SCHOOL, AWC, BOTH }

/// §2.5 `session_status`
enum SessionStatus { ACTIVE, CLOSED }

/// §2.6 `gender`
enum Gender { MALE, FEMALE, OTHER }

/// §2.7 `anthro_classification`
enum AnthroClassification {
  NORMAL,
  LT_MINUS_2SD,
  LT_MINUS_3SD,
  GT_PLUS_2SD,
}

/// §2.7 `muac_classification`
enum MuacClassification { RED, YELLOW, GREEN }

/// §2.7 `checklist_section`
enum ChecklistSection {
  A_DEFECTS_AT_BIRTH,
  B_DEFICIENCY,
  C_DISEASE,
  D_DEVELOPMENTAL_DELAY,
  D_AUTISM,
  D_SCREENING_2_5_TO_6Y,
}

/// §2.7 `checklist_response_type`
enum ChecklistResponseType {
  BOOLEAN,
  YES_NO,
  SINGLE_SELECT,
  MULTI_SELECT,
  NUMERIC,
  TEXT,
}

/// §2.7 `refer_polarity`
enum ReferPolarity { REFER_IF_YES, REFER_IF_NO, INFORMATIONAL }

/// §2.9 `attended_status`
enum AttendedStatus { YES, NO }

/// §2.9 `treatment_status`
enum TreatmentStatus { DONE, NOT_DONE }

/// §2.10 `upload_status`
enum UploadStatus { LOCAL_ONLY, UPLOADING, UPLOADED, UPLOAD_ERROR }

/// §2.10 `ocr_job_status`
enum OcrJobStatus { QUEUED, PROCESSING, COMPLETED, FAILED }

/// §2.10 `derivative_kind`
enum DerivativeKind {
  DESKEWED,
  ROTATED,
  CONTRAST_NORMALIZED,
  CROPPED,
  THUMBNAIL,
  OTHER,
}

/// §2.10 `verification_status`
enum VerificationStatus { UNREVIEWED, IN_REVIEW, CONFIRMED, REJECTED }

/// §2.11 `audit_action`
enum AuditAction { INSERT, UPDATE, SOFT_DELETE, RESTORE }
