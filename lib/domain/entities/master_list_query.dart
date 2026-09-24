/// Which records a School/AWC list shows. Lists start on [active]
/// (docs/35_PHASE_1_5_PLAN.md §8).
enum ActiveFilter { active, inactive, all }

/// The search and filters of a School or AWC master list.
class MasterListQuery {
  const MasterListQuery({
    this.text = '',
    this.district,
    this.block,
    this.status = ActiveFilter.active,
  });

  /// Matched case-insensitively as a substring — no fuzzy matching.
  final String text;
  final String? district;
  final String? block;
  final ActiveFilter status;

  MasterListQuery copyWith({
    String? text,
    String? Function()? district,
    String? Function()? block,
    ActiveFilter? status,
  }) => MasterListQuery(
    text: text ?? this.text,
    district: district == null ? this.district : district(),
    block: block == null ? this.block : block(),
    status: status ?? this.status,
  );
}
