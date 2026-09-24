import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/app.dart';
import 'package:referredline/features/home/presentation/screens/home_screen.dart';

void main() {
  testWidgets('app boots directly into the main shell on Home, with no '
      'login, setup or PIN screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RbskApp()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'no PIN entry');
    for (final text in ['Log in', 'Set up Administrator', 'Recovery Code']) {
      expect(find.textContaining(text), findsNothing, reason: text);
    }
  });
}
