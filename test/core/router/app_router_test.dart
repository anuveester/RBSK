import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/router/app_router.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/features/home/presentation/screens/home_placeholder_screen.dart';

void main() {
  test('router exposes the home route', () {
    final router = createRouter();

    final paths = router.configuration.routes
        .whereType<GoRoute>()
        .map((route) => route.path)
        .toList();

    expect(paths, contains(Routes.home));
  });

  test('route constants are stable', () {
    expect(Routes.home, '/');
    expect(Routes.homeName, 'home');
  });

  testWidgets('initial location resolves to the home placeholder screen',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: createRouter()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomePlaceholderScreen), findsOneWidget);
  });
}
