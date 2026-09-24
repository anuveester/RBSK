import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/router/auth_redirect.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/domain/entities/auth_session.dart';
import 'package:referredline/domain/entities/auth_status.dart';

const _shellRoutes = [
  Routes.home,
  Routes.visits,
  Routes.referrals,
  Routes.reports,
  Routes.more,
];

const _allRoutes = [..._shellRoutes, Routes.splash, Routes.setup, Routes.login];

AuthAuthenticated _authenticated(AppRole role) => AuthAuthenticated(
  AuthSession(userId: 'u', role: role, loggedInAt: DateTime.utc(2026)),
);

void main() {
  test('while auth is loading, every route goes to the splash screen', () {
    for (final route in _allRoutes) {
      final expected = route == Routes.splash ? null : Routes.splash;
      expect(resolveAuthRedirect(null, route), expected, reason: route);
    }
  });

  test('UNINITIALIZED: every route, including direct deep links, goes to '
      'Admin setup', () {
    for (final route in _allRoutes) {
      final expected = route == Routes.setup ? null : Routes.setup;
      expect(
        resolveAuthRedirect(const AuthUninitialized(), route),
        expected,
        reason: route,
      );
    }
  });

  test('LOGGED_OUT: every protected route redirects to login', () {
    for (final route in _shellRoutes) {
      expect(
        resolveAuthRedirect(const AuthLoggedOut(), route),
        Routes.login,
        reason: route,
      );
    }
    expect(resolveAuthRedirect(const AuthLoggedOut(), Routes.login), isNull);
  });

  test('LOGGED_OUT: Admin setup cannot be re-entered once a user exists', () {
    expect(
      resolveAuthRedirect(const AuthLoggedOut(), Routes.setup),
      Routes.login,
    );
  });

  test('LOGGED_OUT: an unknown path also goes to login', () {
    expect(
      resolveAuthRedirect(const AuthLoggedOut(), '/admin/secret'),
      Routes.login,
    );
  });

  test('recovery screens are reachable only where they apply', () {
    // Database unavailable (status null): the restore screen, for recovery.
    expect(resolveAuthRedirect(null, Routes.restore), isNull);
    expect(resolveAuthRedirect(null, Routes.recoverPin), Routes.splash);
    // First run: setup or restore (replacement phone).
    expect(resolveAuthRedirect(const AuthUninitialized(), Routes.restore), isNull);
    expect(
      resolveAuthRedirect(const AuthUninitialized(), Routes.recoverPin),
      Routes.setup,
    );
    // Logged out: PIN recovery and restore (which itself checks whether
    // any Admin can log in).
    expect(resolveAuthRedirect(const AuthLoggedOut(), Routes.recoverPin), isNull);
    expect(resolveAuthRedirect(const AuthLoggedOut(), Routes.restore), isNull);
    // Signed in: never.
    for (final role in AppRole.values) {
      expect(resolveAuthRedirect(_authenticated(role), Routes.restore), Routes.home);
      expect(
        resolveAuthRedirect(_authenticated(role), Routes.recoverPin),
        Routes.home,
      );
    }
  });

  test('Admin-only screens: allowed for ADMIN, redirected for everyone else, '
      'including by direct navigation', () {
    for (final route in Routes.adminOnly) {
      expect(resolveAuthRedirect(_authenticated(AppRole.ADMIN), route), isNull);
      expect(
        resolveAuthRedirect(_authenticated(AppRole.MEDICAL_OFFICER), route),
        Routes.home,
      );
      expect(
        resolveAuthRedirect(_authenticated(AppRole.TEAM_MEMBER), route),
        Routes.home,
      );
      expect(resolveAuthRedirect(const AuthLoggedOut(), route), Routes.login);
      expect(resolveAuthRedirect(null, route), Routes.splash);
    }
  });

  for (final role in AppRole.values) {
    test('AUTHENTICATED ${role.name}: login, setup and splash redirect to '
        'Home', () {
      for (final route in Routes.unauthenticatedOnly) {
        expect(
          resolveAuthRedirect(_authenticated(role), route),
          Routes.home,
          reason: route,
        );
      }
    });

    test('AUTHENTICATED ${role.name}: all five destinations are allowed', () {
      for (final route in _shellRoutes) {
        expect(
          resolveAuthRedirect(_authenticated(role), route),
          isNull,
          reason: route,
        );
      }
    });
  }
}
