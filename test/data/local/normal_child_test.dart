import 'package:referredline/data/local/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';

import 'test_database.dart';

/// Phase 1.2 instruction §9 and Phase 0.6 approval condition 7: a screened
/// child with no disease/finding and no referral must be representable
/// without any artificial "NORMAL"/"NONE"/"NO DISEASE" sentinel value.
/// Absence of findings is the actual absence of rows in
/// school_screening_findings / awc_screening_findings — never a value.
void main() {
  test(
    'a normal school child is a first-class screening row with zero '
    'finding rows — no sentinel value is written anywhere',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      final fyId = await seeds.financialYear();
      final schoolId = await seeds.school();
      final visitId = await seeds.visitPlanForSchool(
        financialYearId: fyId,
        schoolId: schoolId,
      );

      await db.into(db.schoolScreenings).insert(
            SchoolScreeningsCompanion.insert(
              id: 'screening-normal',
              visitPlanId: visitId,
              serialNo: 1,
              screeningDate: DateTime.utc(2026, 4, 1),
              childName: 'Normal Child',
              gender: Gender.MALE,
            ),
          );

      final screening = await (db.select(
        db.schoolScreenings,
      )..where((t) => t.id.equals('screening-normal'))).getSingle();
      final findings = await (db.select(db.schoolScreeningFindings)
            ..where((t) => t.schoolScreeningId.equals('screening-normal')))
          .get();

      expect(screening.childName, 'Normal Child');
      expect(findings, isEmpty);
    },
  );

  test(
    'the schema has no disease_master row and no finding row that means '
    '"normal" — a disease_master row always denotes an actual finding',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);

      final rows = await db.select(db.diseaseMaster).get();
      final names = rows.map((r) => r.name.toUpperCase());

      for (final sentinel in ['NORMAL', 'NONE', 'NO DISEASE', 'NO FINDING']) {
        expect(
          names,
          isNot(contains(sentinel)),
          reason: 'disease_master must never gain a sentinel "no finding" row',
        );
      }
    },
  );

  test(
    'a child WITH a finding is distinguishable purely by having >=1 finding '
    'row, alongside a normal child with the same base fields',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      final fyId = await seeds.financialYear();
      final schoolId = await seeds.school();
      final visitId = await seeds.visitPlanForSchool(
        financialYearId: fyId,
        schoolId: schoolId,
      );
      final diseaseId = await seeds.diseaseMasterRow();

      await db.into(db.schoolScreenings).insert(
            SchoolScreeningsCompanion.insert(
              id: 'screening-normal-2',
              visitPlanId: visitId,
              serialNo: 1,
              screeningDate: DateTime.utc(2026, 4, 1),
              childName: 'Normal Child',
              gender: Gender.MALE,
            ),
          );
      await db.into(db.schoolScreenings).insert(
            SchoolScreeningsCompanion.insert(
              id: 'screening-affected',
              visitPlanId: visitId,
              serialNo: 2,
              screeningDate: DateTime.utc(2026, 4, 1),
              childName: 'Affected Child',
              gender: Gender.FEMALE,
            ),
          );
      await db.into(db.schoolScreeningFindings).insert(
            SchoolScreeningFindingsCompanion.insert(
              id: 'finding-1',
              schoolScreeningId: 'screening-affected',
              diseaseId: diseaseId,
              diseaseCategorySnapshot: DiseaseCategory.DEFICIENCIES,
            ),
          );

      // The "Disease/Referred Line List" (a later phase's query) is exactly
      // this join — a screening with at least one finding row.
      final affectedIds = await (db.selectOnly(db.schoolScreeningFindings)
            ..addColumns([db.schoolScreeningFindings.schoolScreeningId])
            ..groupBy([db.schoolScreeningFindings.schoolScreeningId]))
          .map((row) => row.read(db.schoolScreeningFindings.schoolScreeningId))
          .get();

      expect(affectedIds, ['screening-affected']);
    },
  );
}
