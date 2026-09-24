import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/app.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/database_provider.dart';

import '../data/local/test_database.dart';

/// Runs the real app — real router, screens, providers and repositories —
/// over an in-memory database, so widget tests never touch the Keystore,
/// path_provider or the device file system.
class MasterApp {
  MasterApp() : db = openTestDatabase();

  final AppDatabase db;
  int databaseOpens = 0;

  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async {
            databaseOpens++;
            return db;
          }),
        ],
        child: const RbskApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  }
}

/// Lets real asynchronous database work finish and pumps frames until
/// [until] matches — or, with no finder, for a short fixed period.
Future<void> settle(
  WidgetTester tester, {
  Finder? until,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  var quietRounds = 0;
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (until != null) {
      if (until.evaluate().isNotEmpty) {
        // Let a route transition (about 300 ms) finish, so the previous
        // page is no longer on screen.
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        return;
      }
    } else if (++quietRounds >= 8) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for ${until ?? 'the app to settle'}');
}

Finder byKey(String key) => find.byKey(ValueKey(key));

/// From Home: More tab, then the given Masters entry.
Future<void> openMaster(WidgetTester tester, String entryKey) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text('More')),
  );
  await settle(tester, until: byKey(entryKey));
  await tester.tap(byKey(entryKey));
  await settle(tester);
}

/// Taps [key] after scrolling the page until it is built and visible.
Future<void> tapVisible(WidgetTester tester, String key) async {
  // Let a preceding enterText settle first: focusing a field starts a short
  // scroll animation on the next frame, and a scrolling list ignores taps.
  await _frames(tester);
  if (byKey(key).evaluate().isEmpty) {
    await tester.dragUntilVisible(
      byKey(key),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
  }
  await tester.ensureVisible(byKey(key));
  await _frames(tester);
  await tester.tap(byKey(key));
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
