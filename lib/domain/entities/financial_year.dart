/// Plain read-model for `financial_years` (docs/04_DATABASE_ARCHITECTURE.md §2.1).
/// No Drift type leaks past the data layer — see docs/06_PROJECT_STRUCTURE.md.
class FinancialYear {
  const FinancialYear({
    required this.id,
    required this.label,
    required this.startDate,
    required this.endDate,
  });

  final String id;
  final String label;
  final DateTime startDate;
  final DateTime endDate;
}
