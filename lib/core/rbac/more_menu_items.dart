import 'package:referredline/data/local/enums.dart';

/// A single entry in the `More` destination's menu. Deliberately a plain
/// label with no navigation target and no business logic behind it — the
/// real Masters/Staff/Settings/Admin screens (docs/02_SCREEN_MAP.md) are out
/// of scope for Phase 1.4 (docs/27_PHASE_1_4_PLAN.md §4). Admin-only entries
/// are simply absent from a non-admin's list, not disabled-and-visible.
class MoreMenuItem {
  const MoreMenuItem(this.label);

  final String label;
}

/// The RBAC read model for the `More` destination — docs/27_PHASE_1_4_PLAN.md
/// §3.5: "a small, testable way to ask 'can the current user do X' ... not a
/// full permission-enforcement framework, just enough for 'should this nav
/// item be visible'." Source: docs/04_DATABASE_ARCHITECTURE.md §3 RBAC
/// matrix (`backup export / audit log` — ADMIN only).
///
/// This is the frozen roadmap's exit criterion made concrete and testable:
/// "Each role sees the correct navigation" (docs/21_PHASE_0_6_FREEZE.md §10).
const List<MoreMenuItem> _adminOnlyMoreMenuItems = [
  MoreMenuItem('Backup Export'),
  MoreMenuItem('Audit Log'),
];

List<MoreMenuItem> moreMenuItemsFor(AppRole role) {
  return switch (role) {
    AppRole.ADMIN => List.unmodifiable(_adminOnlyMoreMenuItems),
    AppRole.MEDICAL_OFFICER || AppRole.TEAM_MEMBER => const [],
  };
}
