/// FY 2025-26 only — source-confirmed from the Micro Plan header
/// (docs/17_SOURCE_DATA_QUALITY_REPORT.md). FY 2026-27 is deliberately NOT
/// seeded: no source plan for it has been analyzed yet
/// (docs/00_PROJECT_MASTER_PLAN.md §10, resolution R3). Future financial
/// years are added only when the corresponding official plan is supplied and
/// analyzed — never speculatively.
class FinancialYearSeedRow {
  FinancialYearSeedRow({
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

// DateTime has no const constructor, so this list is `final`, not `const` —
// still immutable in practice (never reassigned, never mutated).
final List<FinancialYearSeedRow> financialYearSeedData = [
  FinancialYearSeedRow(
    id: 'fy-2025-26',
    label: '2025-26',
    startDate: DateTime.utc(2025, 4, 1),
    endDate: DateTime.utc(2026, 3, 31),
  ),
];
