import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/domain/entities/disease_finding.dart';
import 'package:referredline/domain/repositories/disease_master_repository.dart';

class DriftDiseaseMasterRepository implements DiseaseMasterRepository {
  DriftDiseaseMasterRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<DiseaseFinding>> getAll() async {
    final rows = await _db.select(_db.diseaseMaster).get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<DiseaseFinding>> getByCategory(DiseaseCategory category) async {
    final rows =
        await (_db.select(
          _db.diseaseMaster,
        )..where((t) => t.category.equalsValue(category))).get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<DiseaseFinding?> getByOfficialCode(String officialCode) async {
    final row =
        await (_db.select(
          _db.diseaseMaster,
        )..where((t) => t.officialCode.equals(officialCode))).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  DiseaseFinding _toEntity(DiseaseMasterData r) => DiseaseFinding(
    id: r.id,
    officialCode: r.officialCode,
    name: r.name,
    category: r.category,
    applicableTo: r.applicableTo,
    description: r.description,
    isActive: r.isActive,
  );
}
