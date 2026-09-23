import 'package:drift/drift.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/domain/entities/staff_member.dart';
import 'package:referredline/domain/repositories/staff_repository.dart';

class DriftStaffRepository implements StaffRepository {
  DriftStaffRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<StaffMember>> getAll() async {
    final rows = await _db.select(_db.staff).get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<StaffMember>> getActiveAsOf(DateTime asOf) async {
    final query =
        _db.select(_db.staff).join([
            innerJoin(
              _db.staffAssignments,
              _db.staffAssignments.staffId.equalsExp(_db.staff.id),
            ),
          ])
          ..where(
            _db.staffAssignments.startDate.isSmallerOrEqualValue(asOf) &
                (_db.staffAssignments.endDate.isNull() |
                    _db.staffAssignments.endDate.isBiggerOrEqualValue(asOf)),
          );

    final rows = await query.get();
    final seen = <String>{};
    final result = <StaffMember>[];
    for (final row in rows) {
      final staffRow = row.readTable(_db.staff);
      if (seen.add(staffRow.id)) {
        result.add(_toEntity(staffRow));
      }
    }
    return result;
  }

  StaffMember _toEntity(StaffData r) => StaffMember(
    id: r.id,
    fullName: r.fullName,
    designation: r.designation,
    qualification: r.qualification,
  );
}
