import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/repositories/drift_user_repository.dart';

import '../local/test_database.dart';

void main() {
  test(
    'hasAnyUsers is false on an empty database, true once a user exists',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repo = DriftUserRepository(db);

      expect(await repo.hasAnyUsers(), isFalse);
      await Seeds(db).user();
      expect(await repo.hasAnyUsers(), isTrue);
    },
  );

  test(
    'createUser writes a users row with no staff link and reads it back',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repo = DriftUserRepository(db);

      final created = await repo.createUser(
        id: 'user-a',
        displayName: 'Synthetic Admin',
        role: AppRole.ADMIN,
      );
      final read = await repo.getById('user-a');
      final row = await (db.select(
        db.users,
      )..where((t) => t.id.equals('user-a'))).getSingle();

      expect(created.role, AppRole.ADMIN);
      expect(read!.displayName, 'Synthetic Admin');
      expect(read.isActive, isTrue);
      expect(row.staffId, isNull);
    },
  );

  test('getById returns null for an unknown id', () async {
    final db = openTestDatabase();
    addTearDown(db.close);

    expect(await DriftUserRepository(db).getById('nope'), isNull);
  });

  test('getAllActive excludes deactivated users', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final seeds = Seeds(db);
    await seeds.user(id: 'active');
    await seeds.user(id: 'inactive');
    await (db.update(db.users)..where((t) => t.id.equals('inactive'))).write(
      const UsersCompanion(isActive: Value(false)),
    );

    final active = await DriftUserRepository(db).getAllActive();

    expect(active.map((u) => u.id), ['active']);
  });

  test('recordLogin sets last_login_at', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await Seeds(db).user(id: 'u');
    final at = DateTime.utc(2026, 1, 2, 3, 4, 5);

    await DriftUserRepository(db).recordLogin('u', at);
    final row = await (db.select(
      db.users,
    )..where((t) => t.id.equals('u'))).getSingle();

    expect(row.lastLoginAt, at);
  });
}
