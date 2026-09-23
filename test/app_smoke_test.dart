import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/features/auth/presentation/screens/admin_setup_screen.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('a fresh install boots to first-run Admin setup', (tester) async {
    final harness = AppHarness();
    await harness.launch(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(AdminSetupScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await harness.dispose(tester);
  });
}
