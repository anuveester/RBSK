import 'package:referredline/data/local/app_database.dart' as db;
import 'package:referredline/domain/entities/financial_year.dart';
import 'package:referredline/domain/repositories/financial_year_repository.dart';

// Drift generates a row data class also named `FinancialYear` from the
// `FinancialYears` table — colliding with the domain entity of the same name.
// The whole `app_database.dart` import is prefixed (`db.`) in this file to
// keep the two unambiguous; `_db` itself is still just an `AppDatabase`
// instance, so table-getter calls like `_db.financialYears` are unaffected.
class DriftFinancialYearRepository implements FinancialYearRepository {
  DriftFinancialYearRepository(this._db);

  final db.AppDatabase _db;

  @override
  Future<List<FinancialYear>> getAll() async {
    final rows = await _db.select(_db.financialYears).get();
    return rows
        .map(
          (r) => FinancialYear(
            id: r.id,
            label: r.label,
            startDate: r.startDate,
            endDate: r.endDate,
          ),
        )
        .toList();
  }
}
