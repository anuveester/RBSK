import 'package:referredline/data/local/enums.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';

import 'test_database.dart';

/// Phase 1.2 instruction §11 / Phase 0.6 approval conditions C+D: School and
/// AWC referral destinations are configured independently through
/// referral_destination_contexts — there is no single shared enum, and one
/// context's destinations must never leak into the other's query results.
void main() {
  test(
    'School and AWC destinations stay independent: PHC/CHC, District '
    'Hospital and Higher Center for School; PHC, CHC, DH, DEIC, NRC for AWC '
    '— querying by context returns only that context\'s list',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      final phcChc = await seeds.referralDestination(
        id: 'dest-phc-chc',
        code: 'PHC_CHC',
        label: 'PHC/CHC',
      );
      final districtHospital = await seeds.referralDestination(
        id: 'dest-dh-school',
        code: 'DISTRICT_HOSPITAL',
        label: 'District Hospital',
      );
      final higherCenter = await seeds.referralDestination(
        id: 'dest-higher-center',
        code: 'HIGHER_CENTER',
        label: 'Higher Center',
      );
      final phc = await seeds.referralDestination(
        id: 'dest-phc',
        code: 'PHC',
        label: 'PHC',
      );
      final chc = await seeds.referralDestination(
        id: 'dest-chc',
        code: 'CHC',
        label: 'CHC',
      );
      final dh = await seeds.referralDestination(
        id: 'dest-dh-awc',
        code: 'DH',
        label: 'DH',
      );
      final deic = await seeds.referralDestination(
        id: 'dest-deic',
        code: 'DEIC',
        label: 'DEIC',
      );
      final nrc = await seeds.referralDestination(
        id: 'dest-nrc',
        code: 'NRC',
        label: 'NRC',
      );

      // School: all 3 apply to every category (docs/20_REFERRAL_CONFIGURATION.md §2).
      for (final destId in [phcChc, districtHospital, higherCenter]) {
        await db.into(db.referralDestinationContexts).insert(
              ReferralDestinationContextsCompanion.insert(
                id: 'ctx-school-$destId',
                referralDestinationId: destId,
                context: LocationType.SCHOOL,
              ),
            );
      }

      // AWC: category-dependent routing (docs/20_REFERRAL_CONFIGURATION.md §3).
      final awcRouting = <(String, DiseaseCategory?)>[
        (dh, DiseaseCategory.DEFECTS_AT_BIRTH),
        (deic, DiseaseCategory.DEFECTS_AT_BIRTH),
        (phc, DiseaseCategory.DEFICIENCIES),
        (chc, DiseaseCategory.DEFICIENCIES),
        (nrc, DiseaseCategory.DEFICIENCIES),
        (phc, DiseaseCategory.DISEASES),
        (chc, DiseaseCategory.DISEASES),
        (dh, DiseaseCategory.DISEASES),
        (deic, DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY),
      ];
      for (final (destId, category) in awcRouting) {
        await db.into(db.referralDestinationContexts).insert(
              ReferralDestinationContextsCompanion.insert(
                id: 'ctx-awc-$destId-${category!.name}',
                referralDestinationId: destId,
                context: LocationType.AWC,
                findingCategory: Value(category),
              ),
            );
      }

      // School query: never sees DEIC or NRC.
      final schoolDestIds = await (db.select(db.referralDestinationContexts)
            ..where((t) => t.context.equalsValue(LocationType.SCHOOL)))
          .map((r) => r.referralDestinationId)
          .get();
      final schoolCodesRows = await db.select(db.referralDestinations).get();
      final schoolCodes = schoolCodesRows.map((r) => r.code);
      expect(schoolDestIds.toSet(), {phcChc, districtHospital, higherCenter});
      // (schoolCodes sanity: all destination codes exist in the table)
      expect(schoolCodes, containsAll(['PHC_CHC', 'DISTRICT_HOSPITAL', 'HIGHER_CENTER']));

      // AWC query for Deficiency category: PHC, CHC, NRC — never DEIC.
      final deficiencyDestIds = await (db.select(db.referralDestinationContexts)
            ..where((t) =>
                t.context.equalsValue(LocationType.AWC) &
                t.findingCategory.equalsValue(DiseaseCategory.DEFICIENCIES)))
          .map((r) => r.referralDestinationId)
          .get();
      expect(deficiencyDestIds.toSet(), {phc, chc, nrc});
      expect(deficiencyDestIds, isNot(contains(deic)));

      // AWC query for Defects at Birth: DH, DEIC — never PHC/CHC/NRC.
      final defectsDestIds = await (db.select(db.referralDestinationContexts)
            ..where((t) =>
                t.context.equalsValue(LocationType.AWC) &
                t.findingCategory
                    .equalsValue(DiseaseCategory.DEFECTS_AT_BIRTH)))
          .map((r) => r.referralDestinationId)
          .get();
      expect(defectsDestIds.toSet(), {dh, deic});
    },
  );

  test(
    'a School finding and an AWC finding each resolve their referral '
    'destination through the same table without cross-contamination',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      final fyId = await seeds.financialYear();
      final schoolId = await seeds.school();
      final awcId = await seeds.awc();
      final diseaseId = await seeds.diseaseMasterRow();
      final schoolVisitId = await seeds.visitPlanForSchool(
        financialYearId: fyId,
        schoolId: schoolId,
      );
      final awcVisitId = await seeds.visitPlanForAwc(
        financialYearId: fyId,
        awcId: awcId,
      );
      final higherCenter = await seeds.referralDestination(
        id: 'dest-higher',
        code: 'HIGHER_CENTER',
      );
      final deic = await seeds.referralDestination(
        id: 'dest-deic-2',
        code: 'DEIC',
      );

      await db.into(db.schoolScreenings).insert(
            SchoolScreeningsCompanion.insert(
              id: 'ss-1',
              visitPlanId: schoolVisitId,
              serialNo: 1,
              screeningDate: DateTime.utc(2026, 4, 1),
              childName: 'School Child',
              gender: Gender.MALE,
            ),
          );
      await db.into(db.schoolScreeningFindings).insert(
            SchoolScreeningFindingsCompanion.insert(
              id: 'ssf-1',
              schoolScreeningId: 'ss-1',
              diseaseId: diseaseId,
              diseaseCategorySnapshot: DiseaseCategory.DEFICIENCIES,
              referralDestinationId: Value(higherCenter),
            ),
          );

      await db.into(db.awcScreenings).insert(
            AwcScreeningsCompanion.insert(
              id: 'as-1',
              visitPlanId: awcVisitId,
              serialNo: 1,
              screeningDate: DateTime.utc(2026, 4, 1),
              childName: 'AWC Child',
              gender: Gender.FEMALE,
            ),
          );
      await db.into(db.awcScreeningFindings).insert(
            AwcScreeningFindingsCompanion.insert(
              id: 'asf-1',
              awcScreeningId: 'as-1',
              diseaseId: diseaseId,
              diseaseCategorySnapshot: DiseaseCategory.DEFECTS_AT_BIRTH,
              referralDestinationId: Value(deic),
            ),
          );

      final schoolFinding = await (db.select(
        db.schoolScreeningFindings,
      )..where((t) => t.id.equals('ssf-1'))).getSingle();
      final awcFinding = await (db.select(
        db.awcScreeningFindings,
      )..where((t) => t.id.equals('asf-1'))).getSingle();

      expect(schoolFinding.referralDestinationId, higherCenter);
      expect(awcFinding.referralDestinationId, deic);
    },
  );
}
