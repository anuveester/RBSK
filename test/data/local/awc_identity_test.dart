import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

/// Phase 1.2 instruction §7 ("Important AWC ID test") and Phase 0.6 approval
/// condition A: no genuine official Government AWC ID exists in any source
/// material, so `official_awc_code` stays null and is never invented; the
/// unstable Micro Plan integer (`source_plan_awc_code`) is retained only as
/// a non-authoritative reference and carries NO uniqueness constraint.
/// docs/16_PHASE0_DATABASE_REVIEW.md §2 documents the underlying finding
/// (the same plan code maps to different real AWCs across months in 15+
/// cases) that this rule exists to prevent from becoming a false identity.
void main() {
  group('AWC official ID rule', () {
    test('official_awc_code may be null', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      final id = await seeds.awc(id: 'awc-1', officialAwcCode: null);

      final row = await (db.select(
        db.awcs,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.officialAwcCode, isNull);
    });

    test(
      'two different AWCs may both have a null official_awc_code '
      '(no uniqueness violation while unset)',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final seeds = Seeds(db);

        await seeds.awc(id: 'awc-1', officialAwcCode: null);
        await seeds.awc(id: 'awc-2', officialAwcCode: null);

        final count = await db.awcs.count().getSingle();
        expect(count, 2);
      },
    );

    test('a non-blank official_awc_code IS unique once real data exists',
        () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      await seeds.awc(id: 'awc-1', officialAwcCode: 'GOVT-AWC-0001');

      expect(
        () => seeds.awc(id: 'awc-2', officialAwcCode: 'GOVT-AWC-0001'),
        throwsA(isA<Object>()),
      );
    });

    test(
      'REGRESSION: two different AWC records may legally share the same '
      'source_plan_awc_code — this is the exact scenario the frozen schema '
      'exists to allow (the Micro Plan code 57 mapped to both "HEERAPUR" '
      'and "BARODASWAMI 1+2" across different months, per '
      'docs/16_PHASE0_DATABASE_REVIEW.md §2).',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final seeds = Seeds(db);

        final firstId = await seeds.awc(
          id: 'awc-heerapur',
          name: 'HEERAPUR',
          sourcePlanAwcCode: '57',
        );
        final secondId = await seeds.awc(
          id: 'awc-barodaswami',
          name: 'BARODASWAMI 1+2',
          sourcePlanAwcCode: '57',
        );

        final rows =
            await (db.select(db.awcs)
                  ..where((t) => t.sourcePlanAwcCode.equals('57')))
                .get();

        expect(rows.map((r) => r.id).toSet(), {firstId, secondId});
        expect(rows, hasLength(2));
      },
    );

    test(
      'a repeated source_plan_awc_code never becomes a fabricated '
      'official_awc_code',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final seeds = Seeds(db);

        await seeds.awc(
          id: 'awc-a',
          sourcePlanAwcCode: '57',
          officialAwcCode: null,
        );
        await seeds.awc(
          id: 'awc-b',
          sourcePlanAwcCode: '57',
          officialAwcCode: null,
        );

        final rows = await db.select(db.awcs).get();
        expect(
          rows.every((r) => r.officialAwcCode == null),
          isTrue,
          reason:
              'nothing in the schema or seed logic should ever synthesize '
              'an official code from the plan-local one',
        );
      },
    );
  });
}
