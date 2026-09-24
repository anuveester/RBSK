import 'package:drift/drift.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/utils/id_generator.dart';
import 'package:referredline/core/utils/text_normalize.dart';
import 'package:referredline/data/local/app_database.dart' as db;
import 'package:referredline/data/local/audit/business_audit_writer.dart';
import 'package:referredline/data/local/sqlite_errors.dart';
import 'package:referredline/domain/entities/awc.dart';
import 'package:referredline/domain/entities/master_list_query.dart';
import 'package:referredline/domain/repositories/awc_repository.dart';

import 'master_query_helpers.dart';

/// See drift_financial_year_repository.dart for why `app_database.dart` is
/// imported with a `db.` prefix: the generated `Awc` row class collides with
/// the domain entity of the same name.
///
/// `source_plan_awc_code` is never written here — it is non-authoritative
/// Micro Plan data for the import phase — and `official_awc_code` is only
/// what a person enters (never generated).
class DriftAwcRepository implements AwcRepository {
  DriftAwcRepository(
    this._db, {
    this._audit = const BusinessAuditWriter(),
  });

  final db.AppDatabase _db;
  final BusinessAuditWriter _audit;

  static const String _table = 'awcs';

  static const _duplicateCode = DuplicateOfficialCodeFailure(
    codeLabel: 'AWC Code',
    recordLabel: 'AWC',
  );

  @override
  Future<List<Awc>> search(MasterListQuery query) async {
    final select = _db.select(_db.awcs)
      ..where((a) => a.isDeleted.equals(false))
      ..where((a) => activeFilterExpression(a.isActive, query.status))
      ..orderBy([
        (a) => OrderingTerm.asc(a.name.lower()),
        (a) => OrderingTerm.asc(a.panchayatVillage.lower()),
        (a) => OrderingTerm.asc(a.subcentreNo),
      ]);
    if (query.district != null) {
      select.where((a) => a.district.equals(query.district!));
    }
    if (query.block != null) {
      select.where((a) => a.block.equals(query.block!));
    }
    final pattern = likePattern(query.text);
    if (pattern != null) {
      select.where(
        (a) =>
            a.name.lower().like(pattern, escapeChar: likeEscape) |
            a.officialAwcCode.lower().like(pattern, escapeChar: likeEscape) |
            a.panchayatVillage.lower().like(pattern, escapeChar: likeEscape),
      );
    }
    return (await select.get()).map(_toEntity).toList();
  }

  @override
  Future<Awc?> getById(String id) async {
    final row = await (_db.select(
      _db.awcs,
    )..where((a) => a.id.equals(id) & a.isDeleted.equals(false))).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<List<String>> districts() =>
      distinctValues(_db, _db.awcs, _db.awcs.district, _db.awcs.isDeleted);

  @override
  Future<List<String>> blocks({String? district}) => distinctValues(
    _db,
    _db.awcs,
    _db.awcs.block,
    _db.awcs.isDeleted,
    whereColumn: district == null ? null : _db.awcs.district,
    whereValue: district,
  );

  @override
  Future<Awc?> findByOfficialCode(String code, {String? excludeId}) async {
    final wanted = blankToNull(code);
    if (wanted == null) {
      return null;
    }
    final rows = await (_db.select(
      _db.awcs,
    )..where((a) => a.officialAwcCode.equals(wanted))).get();
    final other = rows.where((r) => r.id != excludeId).firstOrNull;
    return other == null ? null : _toEntity(other);
  }

  @override
  Future<List<Awc>> possibleDuplicatesFor(
    AwcInput input, {
    String? excludeId,
  }) async {
    if (normalizeForMatch(input.name).isEmpty) {
      return const [];
    }
    final key = _matchKey(
      input.name,
      input.panchayatVillage,
      input.subcentreNo,
    );
    return (await _allNotDeleted())
        .where(
          (a) =>
              a.id != excludeId &&
              _matchKey(a.name, a.panchayatVillage, a.subcentreNo) == key,
        )
        .toList();
  }

  @override
  Future<List<List<Awc>>> possibleDuplicateGroups() async => groupBy(
    await _allNotDeleted(),
    (a) => _matchKey(a.name, a.panchayatVillage, a.subcentreNo),
  );

  @override
  Future<Awc> create(AwcInput input) async {
    final value = _validated(input);
    await _refuseTakenCode(value.officialAwcCode);
    final id = generateUuidV4();
    final now = DateTime.now().toUtc();
    await _guardUnique(
      () => _db.transaction(() async {
        await _db
            .into(_db.awcs)
            .insert(
              db.AwcsCompanion.insert(
                id: id,
                name: value.name,
                officialAwcCode: Value(value.officialAwcCode),
                subcentreNo: Value(value.subcentreNo),
                panchayatVillage: Value(value.panchayatVillage),
                block: Value(value.block),
                district: Value(value.district),
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
  Future<Awc> update(String id, AwcInput input) async {
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
    if (changed.contains('official_awc_code')) {
      await _refuseTakenCode(value.officialAwcCode, excludeId: id);
    }
    await _guardUnique(
      () => _write(
        existing,
        db.AwcsCompanion(
          name: Value(value.name),
          officialAwcCode: Value(value.officialAwcCode),
          subcentreNo: Value(value.subcentreNo),
          panchayatVillage: Value(value.panchayatVillage),
          block: Value(value.block),
          district: Value(value.district),
        ),
        oldValues: {for (final k in changed) k: before[k]},
        newValues: {for (final k in changed) k: after[k]},
      ),
    );
    return (await getById(id))!;
  }

  @override
  Future<Awc> setActive(String id, {required bool active}) async {
    final existing = await getById(id);
    if (existing == null) {
      throw const MasterRecordNotFoundFailure();
    }
    if (existing.isActive == active) {
      return existing;
    }
    await _write(
      existing,
      db.AwcsCompanion(isActive: Value(active)),
      oldValues: {'is_active': existing.isActive},
      newValues: {'is_active': active},
    );
    return (await getById(id))!;
  }

  Future<void> _write(
    Awc existing,
    db.AwcsCompanion changes, {
    required Map<String, Object?> oldValues,
    required Map<String, Object?> newValues,
  }) => _db.transaction(() async {
    await (_db.update(_db.awcs)..where((a) => a.id.equals(existing.id))).write(
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

  /// Name + village + subcentre number, each normalized; blank matches
  /// blank (docs/35_PHASE_1_5_PLAN.md §7).
  static String _matchKey(String name, String? village, int? subcentreNo) =>
      '${normalizeForMatch(name)}\u0000${normalizeForMatch(village)}'
      '\u0000${subcentreNo ?? ''}';

  AwcInput _validated(AwcInput input) {
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
        codeLabel: 'AWC Code',
        recordLabel: 'AWC',
        existingName: other.name,
      );
    }
  }

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

  Future<List<Awc>> _allNotDeleted() async {
    final rows = await (_db.select(
      _db.awcs,
    )..where((a) => a.isDeleted.equals(false))).get();
    return rows.map(_toEntity).toList();
  }

  static Map<String, Object?> _columns(AwcInput v) => {
    'name': v.name,
    'official_awc_code': v.officialAwcCode,
    'subcentre_no': v.subcentreNo,
    'panchayat_village': v.panchayatVillage,
    'block': v.block,
    'district': v.district,
  };

  static AwcInput _inputOf(Awc a) => AwcInput(
    name: a.name,
    officialAwcCode: a.officialAwcCode,
    subcentreNo: a.subcentreNo,
    panchayatVillage: a.panchayatVillage,
    block: a.block,
    district: a.district,
  );

  static Awc _toEntity(db.Awc r) => Awc(
    id: r.id,
    officialAwcCode: r.officialAwcCode,
    sourcePlanAwcCode: r.sourcePlanAwcCode,
    name: r.name,
    subcentreNo: r.subcentreNo,
    panchayatVillage: r.panchayatVillage,
    block: r.block,
    district: r.district,
    dataQualityNotes: r.dataQualityNotes,
    isActive: r.isActive,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
    rowVersion: r.rowVersion,
  );
}
