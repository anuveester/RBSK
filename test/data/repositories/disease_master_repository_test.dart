import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/local/seed/seed_runner.dart';
import 'package:referredline/data/repositories/drift_disease_master_repository.dart';

import '../local/test_database.dart';

void main() {
  test('getAll returns all 37 seeded findings', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();

    final repo = DriftDiseaseMasterRepository(db);
    expect(await repo.getAll(), hasLength(37));
  });

  test('getByCategory filters correctly', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();

    final repo = DriftDiseaseMasterRepository(db);
    final defects = await repo.getByCategory(DiseaseCategory.DEFECTS_AT_BIRTH);

    expect(defects, hasLength(11));
    expect(defects.every((d) => d.category == DiseaseCategory.DEFECTS_AT_BIRTH),
        isTrue);
  });

  test('getByOfficialCode resolves the catch-all (code 30)', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();

    final repo = DriftDiseaseMasterRepository(db);
    final finding = await repo.getByOfficialCode('30');

    expect(finding, isNotNull);
    expect(finding!.name, 'Others (Specify)');
  });

  test('getByOfficialCode returns null for an unused code (e.g. 35)',
      () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();

    final repo = DriftDiseaseMasterRepository(db);
    expect(await repo.getByOfficialCode('35'), isNull);
  });
}
