import 'package:referredline/data/local/enums.dart';
import 'package:referredline/domain/entities/auth_status.dart';

import 'routes.dart';

/// The route guard, as a pure function so every case can be unit-tested
/// directly. go_router runs this on every navigation — including a direct
/// jump to a deep path — so no protected route is reachable by typing or
/// pushing its location.
///
/// [status] is null while the auth state is loading, or could not be
/// determined (e.g. the database key is unavailable).
/// Returns the location to redirect to, or null to allow [location].
///
/// Rules:
/// - Loading / unavailable: splash, or the restore screen (so data can be
///   recovered when the database key is unavailable).
/// - Uninitialized (no user exists): Admin setup, or restore (a replacement
///   phone restoring from a package).
/// - Logged out: login, PIN recovery, or restore (the restore screen itself
///   only offers setting Admin access when no Admin can log in). `/setup`
///   goes to login, so setup cannot be re-run once any user exists.
/// - Authenticated: unauthenticated-only screens go to Home. Admin-only
///   screens go to Home for anyone who is not an Admin.
String? resolveAuthRedirect(AuthStatus? status, String location) {
  switch (status) {
    case null:
      return {Routes.splash, Routes.restore}.contains(location)
          ? null
          : Routes.splash;
    case AuthUninitialized():
      return {Routes.setup, Routes.restore}.contains(location)
          ? null
          : Routes.setup;
    case AuthLoggedOut():
      return {Routes.login, Routes.recoverPin, Routes.restore}.contains(location)
          ? null
          : Routes.login;
    case AuthAuthenticated(:final session):
      if (Routes.unauthenticatedOnly.contains(location)) {
        return Routes.home;
      }
      if (Routes.adminOnly.contains(location) && session.role != AppRole.ADMIN) {
        return Routes.home;
      }
      return null;
  }
}
