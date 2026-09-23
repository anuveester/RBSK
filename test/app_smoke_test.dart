import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/app.dart';

void main() {
  testWidgets('app boots and renders the placeholder screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: RbskApp()),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('RBSK Referred Line'), findsWidgets);
    expect(find.text('Project skeleton (Phase 1.1)'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
