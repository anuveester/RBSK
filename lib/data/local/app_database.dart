import 'package:drift/drift.dart';

import 'enums.dart';
import 'tables/audit_tables.dart';
import 'tables/awc_screening_tables.dart';
import 'tables/disease_master_tables.dart';
import 'tables/reference_identity_tables.dart';
import 'tables/referral_configuration_tables.dart';
import 'tables/register_photo_tables.dart';
import 'tables/school_awc_tables.dart';
import 'tables/school_screening_tables.dart';
import 'tables/screening_session_tables.dart';
import 'tables/treatment_tables.dart';
import 'tables/visit_planning_tables.dart';

part 'app_database.g.dart';

/// The RBSK Referred Line local database — the frozen v1.0 schema
/// (docs/04_DATABASE_ARCHITECTURE.md), FROZEN for Phase 1.2, implemented
/// verbatim as 28 tables. No table, column, constraint, or index here departs
/// from that document except where SQLite has no equivalent construct
/// (documented inline on each affected table) — see
/// docs/24_PHASE_1_2_REPORT.md §Schema mapping for the full account.
///
/// This class is opened only through [openEncryptedDatabase]
/// (database_connection.dart) — never constructed directly from UI code, per
/// Phase 1.2 instruction §4 ("centralized database lifecycle management").
@DriftDatabase(
  tables: [
    // §2.1 Reference / Identity
    FinancialYears,
    Staff,
    StaffAssignments,
    Users,
    Devices,
    // §2.2 School / AWC Master
    Schools,
    Awcs,
    PlanImports,
    // §2.3 Visit Planning
    VisitPlans,
    Holidays,
    VisitStatusHistory,
    // §2.4 Disease Master
    DiseaseMaster,
    DiseaseAliases,
    // §2.5 Screening Session Context
    ScreeningSessions,
    // §2.6 School Screening
    SchoolScreenings,
    SchoolScreeningFindings,
    // §2.7 AWC Screening (full structured form)
    AwcScreenings,
    AwcScreeningFindings,
    AwcChecklistItems,
    AwcScreeningChecklistResponses,
    // §2.8 Referral Configuration
    ReferralDestinations,
    ReferralDestinationContexts,
    // §2.9 Referral / Treatment Follow-up
    TreatmentRecords,
    // §2.10 Register Photos & OCR
    RegisterPhotos,
    RegisterPhotoDerivatives,
    OcrJobs,
    OcrResults,
    // §2.11 Audit & Sync Support
    AuditLog,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Schema version 1 = the frozen v1.0 schema, in full, as a single initial
  /// migration. Future schema changes get their own numbered version and a
  /// `MigrationStrategy` step — never a destructive recreate
  /// (Phase 1.2 instruction §5).
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    // No onUpgrade steps yet: schema version 1 is the first shipped version.
    // The next schema change adds a numbered `if (from < 2) { ... }` step
    // here rather than replacing this strategy.
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
