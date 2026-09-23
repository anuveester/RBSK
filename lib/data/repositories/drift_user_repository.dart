import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/domain/entities/app_user.dart';
import 'package:referredline/domain/repositories/user_repository.dart';

class DriftUserRepository implements UserRepository {
  DriftUserRepository(this._db);

  final AppDatabase _db;

  @override
  Future<bool> hasAnyUsers() async {
    final count = await _db
        .customSelect('SELECT COUNT(*) AS c FROM users')
        .getSingle()
        .then((r) => r.read<int>('c'));
    return count > 0;
  }

  @override
  Future<AppUser?> getById(String id) async {
    final row = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<List<AppUser>> getAllActive() async {
    final rows = await (_db.select(
      _db.users,
    )..where((t) => t.isActive.equals(true))).get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<AppUser> createUser({
    required String id,
    required String displayName,
    required AppRole role,
  }) async {
    await _db
        .into(_db.users)
        .insert(
          UsersCompanion.insert(id: id, displayName: displayName, role: role),
        );
    return AppUser(
      id: id,
      displayName: displayName,
      role: role,
      isActive: true,
    );
  }

  @override
  Future<void> recordLogin(String id, DateTime at) async {
    await (_db.update(_db.users)..where((t) => t.id.equals(id))).write(
      UsersCompanion(lastLoginAt: Value(at)),
    );
  }

  AppUser _toEntity(User r) => AppUser(
    id: r.id,
    displayName: r.displayName,
    role: r.role,
    isActive: r.isActive,
    email: r.email,
  );
}
