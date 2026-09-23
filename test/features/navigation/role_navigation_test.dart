import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/auth/credential_hasher.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/features/home/presentation/screens/home_screen.dart';
import 'package:referredline/features/more/presentation/screens/more_screen.dart';
import 'package:referredline/features/referrals/presentation/screens/referrals_placeholder_screen.dart';
import 'package:referredline/features/reports/presentation/screens/reports_placeholder_screen.dart';
import 'package:referredline/features/visits/presentation/screens/visits_placeholder_screen.dart';

import '../../support/app_harness.dart';

const _destinations = {
  'Home': HomeScreen,
  'Visits': VisitsPlaceholderScreen,
  'Referrals': ReferralsPlaceholderScreen,
  'Reports': ReportsPlaceholderScreen,
  'More': MoreScreen,
};

const _adminOnly = ['Backup Export', 'Audit Log'];

late String _verifier;

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

/// Signs [role] in via a persisted session (the restore path), then checks
/// the whole navigation surface that role sees.
Future<void> _expectNavigationFor(WidgetTester tester, AppRole role) async {
  final h = AppHarness();
  await tester.runAsync(
    // Synthetic test PIN only.
    () => h.provision(id: 'user', role: role, verifier: _verifier),
  );
  h.persistSession('user', role);
  await h.launch(tester);

  expect(find.byType(HomeScreen), findsOneWidget);
  final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
  expect(
    bar.destinations.map((d) => (d as NavigationDestination).label),
    _destinations.keys,
  );

  for (final entry in _destinations.entries) {
    await _tapNav(tester, entry.key);
    expect(find.byType(entry.value), findsOneWidget, reason: entry.key);
  }

  // Now on More.
  expect(find.byKey(const ValueKey('more-logout')), findsOneWidget);
  for (final label in _adminOnly) {
    expect(
      find.byKey(ValueKey('more-item-$label')),
      role == AppRole.ADMIN ? findsOneWidget : findsNothing,
      reason: '$label for ${role.name}',
    );
  }
  await h.dispose(tester);
}

void main() {
  setUpAll(() {
    _verifier = deriveCredentialVerifier('123789');
  });

  testWidgets(
    'ADMIN navigation: 5 destinations, Admin-only More entries',
    (tester) => _expectNavigationFor(tester, AppRole.ADMIN),
  );

  testWidgets(
    'MEDICAL_OFFICER navigation: 5 destinations, no Admin-only '
    'entries',
    (tester) => _expectNavigationFor(tester, AppRole.MEDICAL_OFFICER),
  );

  testWidgets(
    'TEAM_MEMBER navigation: 5 destinations, no Admin-only entries',
    (tester) => _expectNavigationFor(tester, AppRole.TEAM_MEMBER),
  );
}
