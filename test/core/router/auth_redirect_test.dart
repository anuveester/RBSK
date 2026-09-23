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
