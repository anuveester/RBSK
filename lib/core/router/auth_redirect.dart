import 'package:referredline/domain/entities/auth_status.dart';

import 'routes.dart';

/// The route guard, as a pure function so every case can be unit-tested
/// directly. go_router runs this on every navigation — including a direct
/// jump to a deep path — so no protected route is reachable by typing or
/// pushing its location.
///
/// [status] is null while the auth state is still loading at startup.
/// Returns the location to redirect to, or null to allow [location].
///
/// Rules:
/// - Loading: everything goes to the splash screen.
/// - Uninitialized (no user exists): everything goes to Admin setup.
/// - Logged out: everything goes to login. This includes `/setup`, so setup
///   cannot be re-run once any user exists.
/// - Authenticated: splash, setup and login redirect to Home; every shell
///   destination is allowed.
///
/// There is no role-restricted *route* in Phase 1.4: all three roles may
/// open all five destinations (docs/04 §3 grants every role access to
/// visits, screening, referrals and reports). Role-gated navigation is the
/// `More` menu's Admin-only entries — see `core/rbac/more_menu_items.dart`.
String? resolveAuthRedirect(AuthStatus? status, String location) {
  switch (status) {
    case null:
      return location == Routes.splash ? null : Routes.splash;
    case AuthUninitialized():
      return location == Routes.setup ? null : Routes.setup;
    case AuthLoggedOut():
      return location == Routes.login ? null : Routes.login;
    case AuthAuthenticated():
      return Routes.unauthenticatedOnly.contains(location) ? Routes.home : null;
  }
}
