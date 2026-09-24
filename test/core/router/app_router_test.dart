import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/router/app_router.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/features/home/presentation/screens/home_screen.dart';
import 'package:referredline/features/more/presentation/screens/more_screen.dart';
import 'package:referredline/features/referrals/presentation/screens/referrals_placeholder_screen.dart';
import 'package:referredline/features/reports/presentation/screens/reports_placeholder_screen.dart';
import 'package:referredline/features/visits/presentation/screens/visits_placeholder_screen.dart';

const _destinations = {
  'Home': (Routes.home, HomeScreen),
  'Visits': (Routes.visits, VisitsPlaceholderScreen),
  'Referrals': (Routes.referrals, ReferralsPlaceholderScreen),
  'Reports': (Routes.reports, ReportsPlaceholderScreen),
  'More': (Routes.more, MoreScreen),
};

Future<GoRouter> _pump(WidgetTester tester) async {
  final router = createRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

Set<String> _allPaths(List<RouteBase> routes) => {
  for (final route in routes) ...[
    if (route is GoRoute) route.path,
    ..._allPaths(route.routes),
  ],
};

void main() {
  test('route constants are stable', () {
    expect(
      [Routes.home, Routes.visits, Routes.referrals, Routes.reports, Routes.more],
      ['/', '/visits', '/referrals', '/reports', '/more'],
    );
  });

  test('only the five shell destinations are routes; no authentication '
      'route exists', () {
    final paths = _allPaths(createRouter().configuration.routes);
    expect(paths, {
      Routes.home,
      Routes.visits,
      Routes.referrals,
      Routes.reports,
      Routes.more,
    });
  });

  testWidgets('the initial location is Home, inside the shell', (tester) async {
    await _pump(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      bar.destinations.map((d) => (d as NavigationDestination).label),
      _destinations.keys,
    );
  });

  testWidgets('every destination opens from the navigation bar and by direct '
      'navigation', (tester) async {
    final router = await _pump(tester);
    for (final MapEntry(key: label, value: (path, screen))
        in _destinations.entries) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(screen), findsOneWidget, reason: 'tap $label');

      router.go(Routes.home);
      await tester.pumpAndSettle();
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.byType(screen), findsOneWidget, reason: 'go $path');
    }
  });
}
