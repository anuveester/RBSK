import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/router/app_router.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/domain/entities/auth_session.dart';
import 'package:referredline/domain/entities/auth_status.dart';
import 'package:referredline/features/auth/presentation/screens/admin_setup_screen.dart';
import 'package:referredline/features/auth/presentation/screens/login_screen.dart';
import 'package:referredline/features/auth/presentation/screens/splash_screen.dart';
import 'package:referredline/features/home/presentation/screens/home_screen.dart';
import 'package:referredline/features/more/presentation/screens/more_screen.dart';
import 'package:referredline/features/referrals/presentation/screens/referrals_placeholder_screen.dart';
import 'package:referredline/features/reports/presentation/screens/reports_placeholder_screen.dart';
import 'package:referredline/features/visits/presentation/screens/visits_placeholder_screen.dart';

import '../../support/app_harness.dart';

const _protected = {
  Routes.home: HomeScreen,
  Routes.visits: VisitsPlaceholderScreen,
  Routes.referrals: ReferralsPlaceholderScreen,
  Routes.reports: ReportsPlaceholderScreen,
  Routes.more: MoreScreen,
};

AuthAuthenticated _signedIn(AppRole role) => AuthAuthenticated(
  AuthSession(userId: 'u', role: role, loggedInAt: DateTime.utc(2026)),
);

/// Drives the router directly with a hand-set auth state, independent of
/// the auth controller, so the guard itself is what's under test.
Future<GoRouter> _pumpRouter(
  WidgetTester tester,
  AppHarness harness,
  ValueNotifier<AuthStatus?> status,
) async {
  final router = createRouter(authStatus: status);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await settle(tester);
  return router;
}

Future<void> _go(WidgetTester tester, GoRouter router, String location) async {
  router.go(location);
  await settle(tester);
}

void main() {
  test('route constants are stable', () {
    expect(Routes.home, '/');
    expect(Routes.login, '/login');
    expect(Routes.setup, '/setup');
    expect(Routes.splash, '/splash');
    expect(
      [Routes.visits, Routes.referrals, Routes.reports, Routes.more],
      ['/visits', '/referrals', '/reports', '/more'],
    );
  });

  testWidgets('while auth is loading, the splash screen is shown',
      (tester) async {
    final harness = AppHarness();
    await _pumpRouter(tester, harness, ValueNotifier(null));

    expect(find.byType(SplashScreen), findsOneWidget);
    await harness.dispose(tester);
  });

  testWidgets('UNINITIALIZED: setup is shown and direct navigation elsewhere '
      'is refused', (tester) async {
    final harness = AppHarness();
    final router = await _pumpRouter(
      tester,
      harness,
      ValueNotifier(const AuthUninitialized()),
    );
    expect(find.byType(AdminSetupScreen), findsOneWidget);

    for (final location in [..._protected.keys, Routes.login]) {
      await _go(tester, router, location);
      expect(find.byType(AdminSetupScreen), findsOneWidget, reason: location);
    }
    await harness.dispose(tester);
  });

  testWidgets('LOGGED_OUT: direct navigation to any protected route, or to '
      'setup, lands on login', (tester) async {
    final harness = AppHarness();
    final router = await _pumpRouter(
      tester,
      harness,
      ValueNotifier(const AuthLoggedOut()),
    );
    expect(find.byType(LoginScreen), findsOneWidget);

    for (final location in [..._protected.keys, Routes.setup]) {
      await _go(tester, router, location);
      expect(find.byType(LoginScreen), findsOneWidget, reason: location);
      expect(find.byType(NavigationBar), findsNothing, reason: location);
    }
    await harness.dispose(tester);
  });

  testWidgets('AUTHENTICATED: every destination opens, and login/setup '
      'bounce back to Home', (tester) async {
    final harness = AppHarness();
    final router = await _pumpRouter(
      tester,
      harness,
      ValueNotifier(_signedIn(AppRole.TEAM_MEMBER)),
    );
    expect(find.byType(HomeScreen), findsOneWidget);

    for (final entry in _protected.entries) {
      await _go(tester, router, entry.key);
      expect(find.byType(entry.value), findsOneWidget, reason: entry.key);
    }
    for (final location in [Routes.login, Routes.setup, Routes.splash]) {
      await _go(tester, router, location);
      expect(find.byType(HomeScreen), findsOneWidget, reason: location);
    }
    await harness.dispose(tester);
  });

  testWidgets('the router follows auth state changes: sign-in opens the '
      'shell, sign-out returns to login', (tester) async {
    final harness = AppHarness();
    final status = ValueNotifier<AuthStatus?>(const AuthLoggedOut());
    final router = await _pumpRouter(tester, harness, status);

    status.value = _signedIn(AppRole.ADMIN);
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);

    await _go(tester, router, Routes.reports);
    status.value = const AuthLoggedOut();
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ReportsPlaceholderScreen), findsNothing);
    await harness.dispose(tester);
  });
}
