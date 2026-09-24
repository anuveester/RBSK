import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/auth/credential_hasher.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/features/auth/presentation/screens/admin_setup_screen.dart';
import 'package:referredline/features/auth/presentation/screens/login_screen.dart';
import 'package:referredline/features/home/presentation/screens/home_screen.dart';

import '../../support/app_harness.dart';

// Synthetic test PINs only — never a real credential.
const _setupPin = '271828';
const _pin = '161803';
const _wrongPin = '161804';

late String _verifier;

Finder _key(String key) => find.byKey(ValueKey(key));

String _fieldText(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(of: _key(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

Future<void> _attemptLogin(
  WidgetTester tester,
  String userId,
  String pin,
) async {
  await tester.tap(_key('login-user-$userId'));
  await tester.pump();
  await tester.enterText(_key('login-pin'), pin);
  await tester.pump();
  await tester.tap(_key('login-submit'));
  await settle(
    tester,
    until: find.byWidgetPredicate(
      (w) =>
          w is FilledButton &&
          w.onPressed == null &&
          w.key == const ValueKey('login-submit'),
    ),
  );
  // Busy state seen (or already finished) — now wait for the outcome.
  await settle(
    tester,
    until: find.byWidgetPredicate(
      (w) =>
          (w is Text && w.key == const ValueKey('login-error')) ||
          w is HomeScreen,
    ),
  );
}

void main() {
  setUpAll(() {
    _verifier = deriveCredentialVerifier(_pin);
  });

  group('first-run Admin setup', () {
    testWidgets('creates the Admin, opens the shell, and the session '
        'survives an app restart', (tester) async {
      final h = AppHarness();
      await h.launch(tester);
      expect(find.byType(AdminSetupScreen), findsOneWidget);

      await tester.enterText(_key('setup-name'), 'Synthetic Admin');
      await tester.enterText(_key('setup-pin'), _setupPin);
      await tester.enterText(_key('setup-confirm-pin'), _setupPin);
      await tester.tap(_key('setup-submit'));

      // The Admin Recovery Code is shown once, and the app does not move on
      // until the Admin confirms it is written down.
      await settle(tester, until: _key('recovery-code-text'));
      final code = tester.widget<Text>(_key('recovery-code-text')).data!;
      expect(code, startsWith('AR-'));
      expect(find.byType(HomeScreen), findsNothing);
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        _key('recovery-code-continue'),
        100,
        scrollable: scrollable,
      );
      expect(
        tester.widget<FilledButton>(_key('recovery-code-continue')).onPressed,
        isNull,
        reason: 'nothing confirmed yet',
      );
      await tester.enterText(_key('recovery-code-confirm'), 'XXX');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(_key('recovery-code-continue')).onPressed,
        isNull,
        reason: 'box not ticked and wrong last group',
      );
      await confirmRecoveryCode(tester, code);
      await settle(tester, until: find.byType(HomeScreen));

      expect(find.byType(NavigationBar), findsOneWidget);
      for (final value in h.store.values.values) {
        expect(value, isNot(contains(code)));
        expect(value, isNot(contains(code.replaceAll('-', '').substring(2))));
      }
      final users = await tester.runAsync(() => h.db.select(h.db.users).get());
      expect(users, hasLength(1));
      expect(users!.single.role, AppRole.ADMIN);
      expect(users.single.displayName, 'Synthetic Admin');
      for (final value in h.store.values.values) {
        expect(value, isNot(contains(_setupPin)));
      }

      // Restart: same device storage, fresh app — straight back in, offline.
      await h.launch(tester);
      await settle(tester, until: find.byType(HomeScreen));
      expect(find.byType(AdminSetupScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      await h.dispose(tester);
    });

    testWidgets('mismatched PINs are rejected, create nothing, and the PIN '
        'fields are cleared', (tester) async {
      final h = AppHarness();
      await h.launch(tester);

      await tester.enterText(_key('setup-name'), 'Synthetic Admin');
      await tester.enterText(_key('setup-pin'), _setupPin);
      await tester.enterText(_key('setup-confirm-pin'), '999999');
      await tester.tap(_key('setup-submit'));
      await settle(tester);

      expect(find.text('The two PINs do not match.'), findsOneWidget);
      expect(_fieldText(tester, 'setup-pin'), isEmpty);
      expect(_fieldText(tester, 'setup-confirm-pin'), isEmpty);
      expect(
        await tester.runAsync(() => h.db.select(h.db.users).get()),
        isEmpty,
      );
      expect(find.byType(AdminSetupScreen), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('a PIN shorter than 6 digits is rejected', (tester) async {
      final h = AppHarness();
      await h.launch(tester);

      await tester.enterText(_key('setup-name'), 'Synthetic Admin');
      await tester.enterText(_key('setup-pin'), '1234');
      await tester.enterText(_key('setup-confirm-pin'), '1234');
      await tester.tap(_key('setup-submit'));
      await settle(tester);

      expect(find.text('PIN must be exactly 6 digits.'), findsOneWidget);
      expect(
        await tester.runAsync(() => h.db.select(h.db.users).get()),
        isEmpty,
      );
      await h.dispose(tester);
    });

    testWidgets('the PIN field accepts digits only, at most 6', (tester) async {
      final h = AppHarness();
      await h.launch(tester);

      await tester.enterText(_key('setup-pin'), '12ab34567');
      await tester.pump();

      expect(_fieldText(tester, 'setup-pin'), '123456');
      await h.dispose(tester);
    });

    testWidgets('once an Admin exists, the app opens login, not setup', (
      tester,
    ) async {
      final h = AppHarness();
      await tester.runAsync(
        () =>
            h.provision(id: 'admin', role: AppRole.ADMIN, verifier: _verifier),
      );
      await h.launch(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AdminSetupScreen), findsNothing);
      await h.dispose(tester);
    });
  });

  group('login', () {
    testWidgets('a wrong PIN shows an error and stays on login; the correct '
        'PIN opens the shell', (tester) async {
      final h = AppHarness();
      await tester.runAsync(
        () => h.provision(
          id: 'mo',
          role: AppRole.MEDICAL_OFFICER,
          verifier: _verifier,
          displayName: 'Synthetic MO',
        ),
      );
      await h.launch(tester);

      final submit = tester.widget<FilledButton>(_key('login-submit'));
      expect(submit.onPressed, isNull, reason: 'no user chosen, no PIN yet');

      await _attemptLogin(tester, 'mo', _wrongPin);
      expect(find.text('Incorrect PIN.'), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(_fieldText(tester, 'login-pin'), isEmpty);

      await _attemptLogin(tester, 'mo', _pin);
      expect(find.byType(HomeScreen), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('deactivated users are not offered in the picker', (
      tester,
    ) async {
      final h = AppHarness();
      await tester.runAsync(() async {
        await h.provision(
          id: 'active',
          role: AppRole.TEAM_MEMBER,
          verifier: _verifier,
        );
        await h.provision(
          id: 'gone',
          role: AppRole.TEAM_MEMBER,
          verifier: _verifier,
        );
        await (h.db.update(h.db.users)..where((t) => t.id.equals('gone')))
            .write(const UsersCompanion(isActive: Value(false)));
      });
      await h.launch(tester);

      expect(_key('login-user-active'), findsOneWidget);
      expect(_key('login-user-gone'), findsNothing);
      await h.dispose(tester);
    });

    testWidgets('after 5 wrong PINs the screen reports the lockout', (
      tester,
    ) async {
      final h = AppHarness();
      await tester.runAsync(
        () => h.provision(
          id: 'tm',
          role: AppRole.TEAM_MEMBER,
          verifier: _verifier,
        ),
      );
      await h.launch(tester);

      for (var i = 0; i < 5; i++) {
        await _attemptLogin(tester, 'tm', _wrongPin);
        expect(
          find.text('Incorrect PIN.'),
          findsOneWidget,
          reason: 'attempt $i',
        );
      }
      await _attemptLogin(tester, 'tm', _pin);

      expect(
        find.textContaining('Too many incorrect attempts. Try again in'),
        findsOneWidget,
      );
      expect(find.byType(HomeScreen), findsNothing);
      await h.dispose(tester);
    });
  });

  group('logout', () {
    testWidgets('returns to login and stays logged out after a restart', (
      tester,
    ) async {
      final h = AppHarness();
      await tester.runAsync(
        () =>
            h.provision(id: 'admin', role: AppRole.ADMIN, verifier: _verifier),
      );
      h.persistSession('admin', AppRole.ADMIN);
      await h.launch(tester);
      expect(find.byType(HomeScreen), findsOneWidget);

      await _tapNav(tester, 'More');
      await tester.tap(_key('more-logout'));
      await settle(tester, until: find.byType(LoginScreen));

      await h.launch(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      await h.dispose(tester);
    });
  });
}
