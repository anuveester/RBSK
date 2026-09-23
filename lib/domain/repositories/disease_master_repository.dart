import 'package:referredline/data/local/enums.dart';
import 'package:referredline/domain/entities/disease_finding.dart';

abstract interface class DiseaseMasterRepository {
  Future<List<DiseaseFinding>> getAll();
  Future<List<DiseaseFinding>> getByCategory(DiseaseCategory category);
  Future<DiseaseFinding?> getByOfficialCode(String officialCode);
}
