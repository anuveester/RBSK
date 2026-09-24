import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/app.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/database_provider.dart';

import '../../support/master_app.dart';

/// D5: when the data cannot be opened the Masters show a plain message with
/// Try again — no Restore button, no technical detail — and nothing is
/// deleted.
void main() {
  Future<int Function()> launchFailing(
    WidgetTester tester,
    Object error,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async {
            opens++;
            throw error;
          }),
        ],
        child: const RbskApp(),
      ),
    );
    await settle(tester);
    return () => opens;
  }

  const masters = {'more-schools': 'School Master', 'more-awcs': 'AWC Master'};
  for (final entry in masters.entries) {
    testWidgets('${entry.value}: a locked database shows "Your data is locked '
        'right now. Your data is NOT deleted." with Try again and no '
        'Restore', (tester) async {
      final opens = await launchFailing(
        tester,
        const DatabaseKeyUnavailableException(
          DatabaseKeyUnavailableReason.keyMissingForExistingDatabase,
        ),
      );
      await openMaster(tester, entry.key);

      expect(byKey('data-unavailable'), findsOneWidget);
      expect(find.text('Your data is locked right now.'), findsOneWidget);
      expect(find.text('Your data is NOT deleted.'), findsOneWidget);
      expect(byKey('data-try-again'), findsOneWidget);
      expect(find.textContaining('Restore'), findsNothing);
      expect(find.textContaining('Backup'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('keyMissing'), findsNothing);

      final before = opens();
      await tester.tap(byKey('data-try-again'));
      await settle(tester);
      expect(opens(), before + 1, reason: 'Try again opens once more');
      expect(byKey('data-unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('any other open failure shows the plain generic message', (
    tester,
  ) async {
    await launchFailing(tester, StateError('synthetic failure'));
    await openMaster(tester, 'more-schools');

    expect(
      find.text('Your data could not be opened right now.'),
      findsOneWidget,
    );
    expect(find.text('Your data is NOT deleted.'), findsOneWidget);
    expect(find.textContaining('synthetic failure'), findsNothing);
    expect(find.textContaining('Restore'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
