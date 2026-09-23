import 'package:referredline/data/local/enums.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';

import 'test_database.dart';

/// Phase 1.2 instruction §8 and docs/04_DATABASE_ARCHITECTURE.md §7: planned/
/// enrolment figures (from the Micro Plan) and actual screened-child counts
/// are two strictly separate lineages that must never be mixed into one
/// field, and actual counts are always DERIVED from screening rows, never
/// stored as a maintained counter.
void main() {
  test(
    'planned_*_count on visit_plans and actual screened count are '
    'independent — changing one never touches the other',
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

      // The Micro Plan's own snapshot — stored verbatim, including the kind
      // of male+female<>total mismatch documented in
      // docs/17_SOURCE_DATA_QUALITY_REPORT.md §6. Never recomputed.
      await (db.update(db.visitPlans)..where((t) => t.id.equals(visitId)))
          .write(
        const VisitPlansCompanion(
          plannedMaleCount: Value(83),
          plannedFemaleCount: Value(130),
          plannedTotalCount: Value(255), // deliberately != 83 + 130
        ),
      );

      // Actual screening: only 2 children actually screened that day.
      for (final name in ['Child A', 'Child B']) {
        await db.into(db.schoolScreenings).insert(
              SchoolScreeningsCompanion.insert(
                id: 'screening-$name',
                visitPlanId: visitId,
                serialNo: name == 'Child A' ? 1 : 2,
                screeningDate: DateTime.utc(2026, 4, 1),
                childName: name,
                gender: Gender.FEMALE,
              ),
            );
      }

      final plan = await (db.select(
        db.visitPlans,
      )..where((t) => t.id.equals(visitId))).getSingle();
      final actualScreenedCount =
          await (db.select(db.schoolScreenings)
                ..where((t) => t.visitPlanId.equals(visitId)))
              .get()
              .then((rows) => rows.length);

      // The mismatch in the source data is preserved exactly, not "fixed".
      expect(plan.plannedMaleCount! + plan.plannedFemaleCount!, 213);
      expect(plan.plannedTotalCount, 255);

      // Actual count is derived from real rows and is wildly different from
      // the plan — proving the two are not the same field or reconciled.
      expect(actualScreenedCount, 2);
      expect(actualScreenedCount, isNot(plan.plannedTotalCount));
    },
  );

  test('visit_plans has no column that stores an "actual screened count"',
      () async {
    // A structural assertion: the only way to get an actual count is to
    // COUNT the screening rows — there is no shortcut column to accidentally
    // use instead, and therefore nothing that can drift out of sync with the
    // real records.
    final db = openTestDatabase();
    addTearDown(db.close);

    final columns = db.visitPlans.$columns.map((c) => c.name);
    expect(
      columns.where((c) => c.toLowerCase().contains('screened')),
      isEmpty,
    );
    expect(
      columns.where((c) => c.toLowerCase().contains('actual') && c.contains('count')),
      isEmpty,
    );
  });
}
