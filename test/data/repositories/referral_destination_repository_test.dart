import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/local/seed/seed_runner.dart';
import 'package:referredline/data/repositories/drift_referral_destination_repository.dart';

import '../local/test_database.dart';

/// This is the Phase 1.3 exit criterion, stated verbatim in
/// docs/21_PHASE_0_6_FREEZE.md §10: "referral picker returns the right list
/// per context." Every test here reads through the repository, not the raw
/// table, so it proves the read layer, not just the seed data.
void main() {
  test('School returns exactly PHC/CHC, District Hospital, Higher Center',
      () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();
    final repo = DriftReferralDestinationRepository(db);

    final destinations =
        await repo.getDestinations(context: LocationType.SCHOOL);

    expect(
      destinations.map((d) => d.code).toSet(),
      {'PHC_CHC', 'DISTRICT_HOSPITAL', 'HIGHER_CENTER'},
    );
  });

  test('School query never returns an AWC-only destination', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();
    final repo = DriftReferralDestinationRepository(db);

    final destinations =
        await repo.getDestinations(context: LocationType.SCHOOL);
    final codes = destinations.map((d) => d.code).toSet();

    expect(codes, isNot(contains('DEIC')));
    expect(codes, isNot(contains('NRC')));
    expect(codes, isNot(contains('PHC')));
    expect(codes, isNot(contains('CHC')));
    expect(codes, isNot(contains('DH')));
  });

  test('AWC + Deficiencies returns PHC, CHC, NRC — never DEIC', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();
    final repo = DriftReferralDestinationRepository(db);

    final destinations = await repo.getDestinations(
      context: LocationType.AWC,
      category: DiseaseCategory.DEFICIENCIES,
    );

    expect(destinations.map((d) => d.code).toSet(), {'PHC', 'CHC', 'NRC'});
  });

  test('AWC + Defects at Birth returns DH, DEIC only', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();
    final repo = DriftReferralDestinationRepository(db);

    final destinations = await repo.getDestinations(
      context: LocationType.AWC,
      category: DiseaseCategory.DEFECTS_AT_BIRTH,
    );

    expect(destinations.map((d) => d.code).toSet(), {'DH', 'DEIC'});
  });

  test('AWC + Developmental Delay returns DEIC only', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();
    final repo = DriftReferralDestinationRepository(db);

    final destinations = await repo.getDestinations(
      context: LocationType.AWC,
      category: DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY,
    );

    expect(destinations.map((d) => d.code).toSet(), {'DEIC'});
  });

  test('AWC routing is never assumed to equal School routing', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();
    final repo = DriftReferralDestinationRepository(db);

    final school =
        await repo.getDestinations(context: LocationType.SCHOOL);
    final awcDiseases = await repo.getDestinations(
      context: LocationType.AWC,
      category: DiseaseCategory.DISEASES,
    );

    expect(
      school.map((d) => d.code).toSet(),
      isNot(awcDiseases.map((d) => d.code).toSet()),
    );
  });
}
