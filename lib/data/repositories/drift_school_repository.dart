import 'package:drift/drift.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/utils/id_generator.dart';
import 'package:referredline/core/utils/text_normalize.dart';
import 'package:referredline/data/local/app_database.dart' as db;
import 'package:referredline/data/local/audit/business_audit_writer.dart';
import 'package:referredline/data/local/sqlite_errors.dart';
import 'package:referredline/domain/entities/master_list_query.dart';
import 'package:referredline/domain/entities/school.dart';
import 'package:referredline/domain/repositories/school_repository.dart';

import 'master_query_helpers.dart';

/// See drift_financial_year_repository.dart for why `app_database.dart` is
/// imported with a `db.` prefix: the generated `School` row class collides
/// with the domain entity of the same name.
class DriftSchoolRepository implements SchoolRepository {
  DriftSchoolRepository(
    this._db, {
    this._audit = const BusinessAuditWriter(),
  });

  final db.AppDatabase _db;
  final BusinessAuditWriter _audit;

  static const String _table = 'schools';

  static const _duplicateCode = DuplicateOfficialCodeFailure(
    codeLabel: 'School Code',
    recordLabel: 'school',
  );

  @override
  Future<List<School>> search(MasterListQuery query) async {
    final t = _db.schools;
    final select = _db.select(t)
      ..where((s) => s.isDeleted.equals(false))
      ..where((s) => activeFilterExpression(s.isActive, query.status))
      ..orderBy([
        (s) => OrderingTerm.asc(s.name.lower()),
        (s) => OrderingTerm.asc(s.officialSchoolCode),
      ]);
    if (query.district != null) {
      select.where((s) => s.district.equals(query.district!));
    }
    if (query.block != null) {
      select.where((s) => s.block.equals(query.block!));
    }
    final pattern = likePattern(query.text);
    if (pattern != null) {
      select.where(
        (s) =>
            s.name.lower().like(pattern, escapeChar: likeEscape) |
            s.officialSchoolCode.lower().like(pattern, escapeChar: likeEscape),
      );
    }
    return (await select.get()).map(_toEntity).toList();
  }

  @override
  Future<School?> getById(String id) async {
    final row = await (_db.select(
      _db.schools,
    )..where((s) => s.id.equals(id) & s.isDeleted.equals(false))).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<List<String>> districts() =>
      distinctValues(_db, _db.schools, _db.schools.district, _db.schools.isDeleted);

  @override
  Future<List<String>> blocks({String? district}) => distinctValues(
    _db,
    _db.schools,
    _db.schools.block,
    _db.schools.isDeleted,
    whereColumn: district == null ? null : _db.schools.district,
    whereValue: district,
  );

  @override
  Future<School?> findByOfficialCode(String code, {String? excludeId}) async {
    final wanted = blankToNull(code);
    if (wanted == null) {
      return null;
    }
    // Exact match, like the unique index. Deleted rows count too: the
    // index still holds their codes.
    final rows = await (_db.select(
      _db.schools,
    )..where((s) => s.officialSchoolCode.equals(wanted))).get();
    final other = rows.where((r) => r.id != excludeId).firstOrNull;
    return other == null ? null : _toEntity(other);
  }

  @override
  Future<List<School>> possibleDuplicatesFor(
    SchoolInput input, {
    String? excludeId,
  }) async {
    final key = normalizeForMatch(input.name);
    if (key.isEmpty) {
      return const [];
    }
    return (await _allNotDeleted())
        .where((s) => s.id != excludeId && normalizeForMatch(s.name) == key)
        .toList();
  }

  @override
  Future<List<List<School>>> possibleDuplicateGroups() async =>
      groupBy(await _allNotDeleted(), (s) => normalizeForMatch(s.name));

  @override
  Future<School> create(SchoolInput input) async {
    final value = _validated(input);
    await _refuseTakenCode(value.officialSchoolCode);
    final id = generateUuidV4();
    final now = DateTime.now().toUtc();
    await _guardUnique(
      () => _db.transaction(() async {
        await _db
            .into(_db.schools)
            .insert(
              db.SchoolsCompanion.insert(
                id: id,
                name: value.name,
                officialSchoolCode: Value(value.officialSchoolCode),
                institutionType: Value(value.institutionType),
                district: Value(value.district),
                block: Value(value.block),
                panchayatVillage: Value(value.panchayatVillage),
                address: Value(value.address),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        await _audit.recordInsert(
          _db,
          table: _table,
          recordId: id,
          values: {..._columns(value), 'is_active': true},
        );
      }),
    );
    return (await getById(id))!;
  }

  @override
  Future<School> update(String id, SchoolInput input) async {
    final existing = await getById(id);
    if (existing == null) {
      throw const MasterRecordNotFoundFailure();
    }
    final value = _validated(input);
    final before = _columns(_inputOf(existing));
    final after = _columns(value);
    final changed = {
      for (final key in after.keys)
        if (before[key] != after[key]) key,
    };
    if (changed.isEmpty) {
      return existing;
    }
    if (changed.contains('official_school_code')) {
      await _refuseTakenCode(value.officialSchoolCode, excludeId: id);
    }
    await _guardUnique(
      () => _write(
        existing,
        db.SchoolsCompanion(
          name: Value(value.name),
          officialSchoolCode: Value(value.officialSchoolCode),
          institutionType: Value(value.institutionType),
          district: Value(value.district),
          block: Value(value.block),
          panchayatVillage: Value(value.panchayatVillage),
          address: Value(value.address),
        ),
        oldValues: {for (final k in changed) k: before[k]},
        newValues: {for (final k in changed) k: after[k]},
      ),
    );
    return (await getById(id))!;
  }

  @override
  Future<School> setActive(String id, {required bool active}) async {
    final existing = await getById(id);
    if (existing == null) {
      throw const MasterRecordNotFoundFailure();
    }
    if (existing.isActive == active) {
      return existing;
    }
    await _write(
      existing,
      db.SchoolsCompanion(isActive: Value(active)),
      oldValues: {'is_active': existing.isActive},
      newValues: {'is_active': active},
    );
    return (await getById(id))!;
  }

  /// One UPDATE plus its audit row, in one transaction. Advances
  /// `updated_at` and `row_version`.
  Future<void> _write(
    School existing,
    db.SchoolsCompanion changes, {
    required Map<String, Object?> oldValues,
    required Map<String, Object?> newValues,
  }) => _db.transaction(() async {
    await (_db.update(_db.schools)..where((s) => s.id.equals(existing.id)))
        .write(
          changes.copyWith(
            updatedAt: Value(DateTime.now().toUtc()),
            rowVersion: Value(existing.rowVersion + 1),
          ),
        );
    await _audit.recordUpdate(
      _db,
      table: _table,
      recordId: existing.id,
      oldValues: oldValues,
      newValues: newValues,
    );
  });

  SchoolInput _validated(SchoolInput input) {
    final value = input.normalized();
    if (value.name.isEmpty) {
      throw const NameRequiredFailure();
    }
    return value;
  }

  Future<void> _refuseTakenCode(String? code, {String? excludeId}) async {
    if (code == null) {
      return;
    }
    final other = await findByOfficialCode(code, excludeId: excludeId);
    if (other != null) {
      throw DuplicateOfficialCodeFailure(
        codeLabel: 'School Code',
        recordLabel: 'school',
        existingName: other.name,
      );
    }
  }

  /// The unique index is the final guard; its violation reads the same as
  /// the friendly pre-check.
  Future<void> _guardUnique(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (isUniqueConstraintViolation(e)) {
        throw _duplicateCode;
      }
      rethrow;
    }
  }

  Future<List<School>> _allNotDeleted() async {
    final rows = await (_db.select(
      _db.schools,
    )..where((s) => s.isDeleted.equals(false))).get();
    return rows.map(_toEntity).toList();
  }

  static Map<String, Object?> _columns(SchoolInput v) => {
    'name': v.name,
    'official_school_code': v.officialSchoolCode,
    'institution_type': v.institutionType,
    'district': v.district,
    'block': v.block,
    'panchayat_village': v.panchayatVillage,
    'address': v.address,
  };

  static SchoolInput _inputOf(School s) => SchoolInput(
    name: s.name,
    officialSchoolCode: s.officialSchoolCode,
    institutionType: s.institutionType,
    district: s.district,
    block: s.block,
    panchayatVillage: s.panchayatVillage,
    address: s.address,
  );

  static School _toEntity(db.School r) => School(
    id: r.id,
    officialSchoolCode: r.officialSchoolCode,
    name: r.name,
    institutionType: r.institutionType,
    district: r.district,
    block: r.block,
    panchayatVillage: r.panchayatVillage,
    address: r.address,
    dataQualityNotes: r.dataQualityNotes,
    isActive: r.isActive,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
    rowVersion: r.rowVersion,
  );
}
