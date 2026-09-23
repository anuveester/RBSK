import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/enums.dart';

/// An in-memory, unencrypted database for schema/CRUD tests. Tests must not
/// depend on the production database (Phase 1.2 instruction §6) — this never
/// touches disk, never touches secure storage, and is thrown away after each
/// test. Encryption itself is verified separately in
/// database_connection_test.dart, which does open real encrypted files.
AppDatabase openTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

/// Minimal valid row builders shared across tests, so each test only
/// specifies the field(s) it actually cares about. No child, parent, or
/// contact-number values here are real — see Phase 1.2 instruction §13.
class Seeds {
  Seeds(this.db);

  final AppDatabase db;

  Future<String> financialYear({String id = 'fy-2025-26'}) async {
    await db
        .into(db.financialYears)
        .insert(
          FinancialYearsCompanion.insert(
            id: id,
            label: '2025-26',
            startDate: DateTime.utc(2025, 4, 1),
            endDate: DateTime.utc(2026, 3, 31),
          ),
        );
    return id;
  }

  Future<String> user({String id = 'user-1', AppRole role = AppRole.ADMIN}) async {
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: id,
            displayName: 'Test User',
            role: role,
          ),
        );
    return id;
  }

  Future<String> school({
    String id = 'school-1',
    String? officialSchoolCode,
    String name = 'Test Primary School',
  }) async {
    await db
        .into(db.schools)
        .insert(
          SchoolsCompanion.insert(
            id: id,
            name: name,
            officialSchoolCode: Value(officialSchoolCode),
          ),
        );
    return id;
  }

  Future<String> awc({
    String id = 'awc-1',
    String? officialAwcCode,
    String? sourcePlanAwcCode,
    String name = 'Test AWC',
  }) async {
    await db
        .into(db.awcs)
        .insert(
          AwcsCompanion.insert(
            id: id,
            name: name,
            officialAwcCode: Value(officialAwcCode),
            sourcePlanAwcCode: Value(sourcePlanAwcCode),
          ),
        );
    return id;
  }

  Future<String> visitPlanForSchool({
    String id = 'visit-1',
    required String financialYearId,
    required String schoolId,
    DateTime? plannedDate,
  }) async {
    final date = plannedDate ?? DateTime.utc(2026, 4, 1);
    await db
        .into(db.visitPlans)
        .insert(
          VisitPlansCompanion.insert(
            id: id,
            financialYearId: financialYearId,
            locationType: LocationType.SCHOOL,
            originalPlannedDate: date,
            plannedDate: date,
            schoolId: Value(schoolId),
          ),
        );
    return id;
  }

  Future<String> visitPlanForAwc({
    String id = 'visit-awc-1',
    required String financialYearId,
    required String awcId,
    DateTime? plannedDate,
  }) async {
    final date = plannedDate ?? DateTime.utc(2026, 4, 1);
    await db
        .into(db.visitPlans)
        .insert(
          VisitPlansCompanion.insert(
            id: id,
            financialYearId: financialYearId,
            locationType: LocationType.AWC,
            originalPlannedDate: date,
            plannedDate: date,
            awcId: Value(awcId),
          ),
        );
    return id;
  }

  Future<String> diseaseMasterRow({
    String id = 'disease-1',
    String name = 'Vitamin A Deficiency',
    DiseaseCategory category = DiseaseCategory.DEFICIENCIES,
    String? officialCode = '11',
  }) async {
    await db
        .into(db.diseaseMaster)
        .insert(
          DiseaseMasterCompanion.insert(
            id: id,
            name: name,
            category: category,
            officialCode: Value(officialCode),
          ),
        );
    return id;
  }

  Future<String> referralDestination({
    required String id,
    required String code,
    String? label,
  }) async {
    await db
        .into(db.referralDestinations)
        .insert(
          ReferralDestinationsCompanion.insert(
            id: id,
            code: code,
            label: label ?? code,
          ),
        );
    return id;
  }
}
