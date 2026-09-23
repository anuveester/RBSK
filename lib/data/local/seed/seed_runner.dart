import 'package:drift/drift.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/enums.dart';

import 'disease_master_seed_data.dart';
import 'financial_year_seed_data.dart';
import 'referral_destination_seed_data.dart';
import 'staff_seed_data.dart';

/// Idempotent reference-data seeding for the four Phase 1.3 domains:
/// financial years, staff/team, Disease Master, and referral configuration.
///
/// **Idempotent, not automatic.** Calling [seedAll] more than once never
/// duplicates a row — every insert uses [InsertMode.insertOrIgnore] against
/// stable, deterministic primary keys (docs/25_PHASE_1_3_PLAN.md §6: seed
/// data intentionally does not use random UUIDs). This class is not wired
/// into app startup anywhere in this phase — nothing calls it automatically
/// on every boot (Phase 1.3 instruction §5); it exists to be invoked
/// explicitly, by a test or by a later phase's own deliberate init flow.
///
/// **What this does NOT do:** seed `awc_checklist_items` (deferred to the AWC
/// full-form phase), seed FY 2026-27 (no source plan analyzed for it yet),
/// or seed any staff contact number (never present in the source data files
/// this class reads from — see staff_seed_data.dart).
class SeedRunner {
  SeedRunner(this._db);

  final AppDatabase _db;

  Future<void> seedAll() async {
    await _db.transaction(() async {
      await _seedFinancialYears();
      await _seedStaff();
      await _seedDiseaseMaster();
      await _seedReferralConfiguration();
    });
  }

  Future<void> _seedFinancialYears() async {
    for (final row in financialYearSeedData) {
      await _db
          .into(_db.financialYears)
          .insert(
            FinancialYearsCompanion.insert(
              id: row.id,
              label: row.label,
              startDate: row.startDate,
              endDate: row.endDate,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<void> _seedStaff() async {
    for (final row in staffSeedData) {
      await _db
          .into(_db.staff)
          .insert(
            StaffCompanion.insert(
              id: row.id,
              fullName: row.fullName,
              designation: Value(row.designation),
              qualification: Value(row.qualification),
              // .phone is deliberately never set — stays NULL.
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    for (final row in staffAssignmentSeedData) {
      await _db
          .into(_db.staffAssignments)
          .insert(
            StaffAssignmentsCompanion.insert(
              id: row.id,
              staffId: row.staffId,
              roleInTeam: row.roleInTeam,
              startDate: row.startDate,
              teamLabel: const Value('Team - B'),
              financialYearId: Value(row.financialYearId),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<void> _seedDiseaseMaster() async {
    for (final row in diseaseMasterSeedData) {
      await _db
          .into(_db.diseaseMaster)
          .insert(
            DiseaseMasterCompanion.insert(
              id: row.id,
              officialCode: Value(row.officialCode),
              name: row.name,
              category: row.category,
              applicableTo: const Value(ApplicableTo.BOTH),
              sourceReference: const Value(diseaseMasterSourceReference),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<void> _seedReferralConfiguration() async {
    for (final row in referralDestinationSeedData) {
      await _db
          .into(_db.referralDestinations)
          .insert(
            ReferralDestinationsCompanion.insert(
              id: row.id,
              code: row.code,
              label: row.label,
              description: Value(row.description),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    for (final row in referralDestinationContextSeedData) {
      await _db
          .into(_db.referralDestinationContexts)
          .insert(
            ReferralDestinationContextsCompanion.insert(
              id: row.id,
              referralDestinationId: row.destinationId,
              context: row.context,
              findingCategory: Value(row.category),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }
}
