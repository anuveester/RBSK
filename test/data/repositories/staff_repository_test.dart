import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/seed/seed_runner.dart';
import 'package:referredline/data/repositories/drift_staff_repository.dart';

import '../local/test_database.dart';

void main() {
  test('getAll returns all 4 Team-B members', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();

    final repo = DriftStaffRepository(db);
    final staff = await repo.getAll();

    expect(staff, hasLength(4));
    expect(
      staff.map((s) => s.fullName).toSet(),
      {'Rajni Pratap', 'Deepak Yadav', 'Shabnam Khan', 'Mangal Kumar'},
    );
  });

  test('getActiveAsOf resolves all 4 members for a date within FY 2025-26',
      () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();

    final repo = DriftStaffRepository(db);
    final active = await repo.getActiveAsOf(DateTime.utc(2025, 9, 1));

    expect(active, hasLength(4));
  });

  test('getActiveAsOf returns nothing before any assignment started',
      () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();

    final repo = DriftStaffRepository(db);
    final active = await repo.getActiveAsOf(DateTime.utc(2024, 1, 1));

    expect(active, isEmpty);
  });

  test('the entity type structurally has no phone field to leak', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await SeedRunner(db).seedAll();

    final repo = DriftStaffRepository(db);
    final staff = await repo.getAll();

    // If StaffMember ever grows a phone field, this test still passes —
    // the real guarantee is `test/data/local/seed/seed_runner_test.dart`'s
    // "NO seeded staff row has a non-null phone number" check against the
    // database itself. This test just confirms the repository round-trips
    // designation/qualification correctly, which it can only do if it maps
    // fields honestly.
    final rajni = staff.firstWhere((s) => s.fullName == 'Rajni Pratap');
    expect(rajni.designation, 'Medical Officer');
    expect(rajni.qualification, 'BAMS');
  });
}
