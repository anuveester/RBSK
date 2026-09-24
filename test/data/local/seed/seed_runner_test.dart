import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/local/seed/disease_master_seed_data.dart';
import 'package:referredline/data/local/seed/seed_runner.dart';

import '../test_database.dart';

void main() {
  group('SeedRunner — idempotency', () {
    test('running seedAll twice does not duplicate any row', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final runner = SeedRunner(db);

      await runner.seedAll();
      final countsAfterFirst = await _rowCounts(db);

      await runner.seedAll();
      final countsAfterSecond = await _rowCounts(db);

      expect(countsAfterSecond, countsAfterFirst);
    });

    test('running seedAll three times does not throw', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final runner = SeedRunner(db);

      await runner.seedAll();
      await runner.seedAll();
      await runner.seedAll();
      // No exception = pass. Row counts re-verified below in other tests.
    });
  });

  group('SeedRunner — Financial Year', () {
    test('FY 2025-26 is seeded', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      final rows = await db.select(db.financialYears).get();
      expect(rows.map((r) => r.label), contains('2025-26'));
    });

    test('FY 2026-27 is NOT seeded', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      final rows = await db.select(db.financialYears).get();
      expect(rows.map((r) => r.label), isNot(contains('2026-27')));
      // And nothing else either — exactly one FY exists at this phase.
      expect(rows, hasLength(1));
    });
  });

  group('SeedRunner — Disease Master', () {
    test('exactly 37 rows are seeded', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      final rows = await db.select(db.diseaseMaster).get();
      expect(rows, hasLength(37));
    });

    test('category counts match the source: 11/8/9/9', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      final rows = await db.select(db.diseaseMaster).get();
      final byCategory = <DiseaseCategory, int>{};
      for (final r in rows) {
        byCategory[r.category] = (byCategory[r.category] ?? 0) + 1;
      }

      expect(byCategory[DiseaseCategory.DEFECTS_AT_BIRTH], 11);
      expect(byCategory[DiseaseCategory.DEFICIENCIES], 8);
      expect(byCategory[DiseaseCategory.DISEASES], 9);
      expect(byCategory[DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY], 9);
    });

    test('every seeded row matches the source data file exactly', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      final rows = await db.select(db.diseaseMaster).get();
      final byId = {for (final r in rows) r.id: r};

      for (final expected in diseaseMasterSeedData) {
        final actual = byId[expected.id];
        expect(actual, isNotNull, reason: 'missing row ${expected.id}');
        expect(actual!.officialCode, expected.officialCode);
        expect(actual.name, expected.name);
        expect(actual.category, expected.category);
      }
    });

    test('code 30 is seeded as the catch-all "Others (Specify)"', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      final row =
          await (db.select(
            db.diseaseMaster,
          )..where((t) => t.officialCode.equals('30'))).getSingle();

      expect(row.name, 'Others (Specify)');
      expect(row.category, DiseaseCategory.DEFICIENCIES);
      expect(row.officialCode, othersSpecifyOfficialCode);
    });

    test('no row exists that is not in the source data file (no invented rows)',
        () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      final rows = await db.select(db.diseaseMaster).get();
      final expectedIds = diseaseMasterSeedData.map((r) => r.id).toSet();
      final actualIds = rows.map((r) => r.id).toSet();

      expect(actualIds, expectedIds);
    });

    test('codes 31-38 are not present (never invented)', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      final rows = await db.select(db.diseaseMaster).get();
      final codes = rows.map((r) => r.officialCode).toSet();

      for (var code = 31; code <= 38; code++) {
        expect(codes, isNot(contains('$code')));
      }
    });
  });

  group('SeedRunner — Referral configuration', () {
    test('3 School + 5 AWC destinations are seeded (8 total)', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      final rows = await db.select(db.referralDestinations).get();
      expect(rows, hasLength(8));
      expect(
        rows.map((r) => r.code).toSet(),
        {
          'PHC_CHC',
          'DISTRICT_HOSPITAL',
          'HIGHER_CENTER',
          'PHC',
          'CHC',
          'DH',
          'DEIC',
          'NRC',
        },
      );
    });

    test('School context rows never reference DEIC or NRC', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      final query = db.select(db.referralDestinationContexts).join([
        innerJoin(
          db.referralDestinations,
          db.referralDestinations.id.equalsExp(
            db.referralDestinationContexts.referralDestinationId,
          ),
        ),
      ])..where(
          db.referralDestinationContexts.context.equalsValue(
            LocationType.SCHOOL,
          ),
        );
      final rows = await query.get();
      final codes = rows
          .map((r) => r.readTable(db.referralDestinations).code)
          .toSet();

      expect(codes, {'PHC_CHC', 'DISTRICT_HOSPITAL', 'HIGHER_CENTER'});
      expect(codes, isNot(contains('DEIC')));
      expect(codes, isNot(contains('NRC')));
    });
  });

  group('SeedRunner — Staff', () {
    test('4 staff members are seeded with an open-ended assignment each',
        () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      final staff = await db.select(db.staff).get();
      final assignments = await db.select(db.staffAssignments).get();

      expect(staff, hasLength(4));
      expect(assignments, hasLength(4));
      expect(assignments.every((a) => a.endDate == null), isTrue);
      expect(
        staff.map((s) => s.fullName).toSet(),
        {'Rajni Pratap', 'Deepak Yadav', 'Shabnam Khan', 'Mangal Kumar'},
      );
    });

    test(
      'NO seeded staff row has a non-null phone number — the privacy rule '
      'holds at the database level, not just in the seed data file',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        await SeedRunner(db).seedAll();

        final staff = await db.select(db.staff).get();
        expect(staff.every((s) => s.phone == null), isTrue);
      },
    );
  });

  group('SeedRunner — database integrity', () {
    test('schemaVersion is unchanged by seeding', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      expect(db.schemaVersion, 2);
    });

    test('table count is still exactly 28 after seeding (no schema objects '
        'were added)', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '__drift%'",
          )
          .get();
      expect(rows, hasLength(28));
    });

    test('seeding writes to no table outside the 6 Phase 1.3 domains',
        () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await SeedRunner(db).seedAll();

      // Every other business table must remain empty. Queried by raw table
      // name (not the generated Dart table getters) so this list is typed
      // uniformly regardless of each table's specific generated type.
      const untouchedTableNames = [
        'schools',
        'awcs',
        'plan_imports',
        'visit_plans',
        'holidays',
        'visit_status_history',
        'disease_aliases',
        'screening_sessions',
        'school_screenings',
        'school_screening_findings',
        'awc_screenings',
        'awc_screening_findings',
        'awc_checklist_items',
        'awc_screening_checklist_responses',
        'treatment_records',
        'register_photos',
        'register_photo_derivatives',
        'ocr_jobs',
        'ocr_results',
        'audit_log',
        'users',
        'devices',
      ];
      for (final tableName in untouchedTableNames) {
        final count = await db
            .customSelect('SELECT COUNT(*) AS c FROM $tableName')
            .getSingle()
            .then((r) => r.read<int>('c'));
        expect(count, 0, reason: '$tableName should stay empty');
      }
    });
  });
}

Future<Map<String, int>> _rowCounts(AppDatabase db) async {
  return {
    'financial_years': await db.financialYears.count().getSingle(),
    'staff': await db.staff.count().getSingle(),
    'staff_assignments': await db.staffAssignments.count().getSingle(),
    'disease_master': await db.diseaseMaster.count().getSingle(),
    'referral_destinations': await db.referralDestinations.count().getSingle(),
    'referral_destination_contexts':
        await db.referralDestinationContexts.count().getSingle(),
  };
}
