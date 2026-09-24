import 'package:referredline/core/router/routes.dart';
import 'package:referredline/data/local/enums.dart';

/// A single entry in the `More` destination's menu. Entries without a
/// [route] are inert labels for screens that belong to later phases.
/// Admin-only entries are simply absent from a non-admin's list, not
/// disabled-and-visible.
class MoreMenuItem {
  const MoreMenuItem(this.label, {this.route});

  final String label;
  final String? route;
}

/// The RBAC read model for the `More` destination — docs/27_PHASE_1_4_PLAN.md
/// §3.5. Source: docs/04_DATABASE_ARCHITECTURE.md §3 RBAC matrix (`users`
/// manage, `backup export / audit log` — ADMIN only). The route guard
/// enforces the same restriction for direct navigation
/// (`Routes.adminOnly`).
const List<MoreMenuItem> _adminOnlyMoreMenuItems = [
  MoreMenuItem('Admin Recovery Code', route: Routes.moreRecoveryCode),
  MoreMenuItem('Backup Export', route: Routes.moreBackup),
  MoreMenuItem('Audit Log'),
];

List<MoreMenuItem> moreMenuItemsFor(AppRole role) {
  return switch (role) {
    AppRole.ADMIN => List.unmodifiable(_adminOnlyMoreMenuItems),
    AppRole.MEDICAL_OFFICER || AppRole.TEAM_MEMBER => const [],
  };
}
