import 'package:referredline/domain/entities/financial_year.dart';

abstract interface class FinancialYearRepository {
  Future<List<FinancialYear>> getAll();
}
