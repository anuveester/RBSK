import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/seed/seed_runner.dart';
import 'package:referredline/data/repositories/drift_financial_year_repository.dart';

import '../local/test_database.dart';

void main() {
  test('repository reads the seeded FY 2025-26 and nothing else', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();

    final repo = DriftFinancialYearRepository(db);
    final years = await repo.getAll();

    expect(years, hasLength(1));
    expect(years.single.label, '2025-26');
    expect(years.single.startDate, DateTime.utc(2025, 4, 1));
    expect(years.single.endDate, DateTime.utc(2026, 3, 31));
  });

  test('returns an empty list before seeding', () async {
    final db = openTestDatabase();
    addTearDown(db.close);

    final repo = DriftFinancialYearRepository(db);
    expect(await repo.getAll(), isEmpty);
  });
}
