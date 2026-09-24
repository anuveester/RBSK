import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/app.dart';
import 'package:referredline/core/router/app_router.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/auth/credential_hasher.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/database_provider.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/local/recovery/database_recovery_service.dart';
import 'package:referredline/data/local/recovery/restore_transaction.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:referredline/data/repositories/drift_user_repository.dart';
import 'package:referredline/data/repositories/local_auth_repository.dart';
import 'package:referredline/domain/entities/auth_session.dart';
import 'package:referredline/domain/entities/auth_status.dart';
import 'package:referredline/features/auth/presentation/controllers/auth_providers.dart';
import 'package:referredline/features/auth/presentation/screens/login_screen.dart';
import 'package:referredline/features/home/presentation/screens/home_screen.dart';
import 'package:referredline/features/recovery/presentation/screens/backup_screen.dart';
import 'package:referredline/features/recovery/presentation/screens/restore_screen.dart';

import '../../data/local/test_database.dart';
import '../../support/app_harness.dart';
import '../../support/phone_fixture.dart';

// Synthetic test PINs only.
const _pin = '407615';
const _newPin = '358190';

Finder _key(String k) => find.byKey(ValueKey(k));

Future<void> _confirmShownCode(WidgetTester tester) async {
  await settle(tester, until: _key('recovery-code-text'));
  final code = tester.widget<Text>(_key('recovery-code-text')).data!;
  await confirmRecoveryCode(tester, code);
}

void main() {
  testWidgets('database key unavailable: the app explains in plain words '
      'that data is not deleted, and offers restore', (tester) async {
    final h = AppHarness();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          authRepositoryProvider.overrideWith(
            (ref) async => throw const DatabaseKeyUnavailableException(
              DatabaseKeyUnavailableReason.keyMissingForExistingDatabase,
            ),
          ),
        ],
        child: const RbskApp(),
      ),
    );
    await settle(tester, until: _key('splash-error'));

    expect(find.text('Your data is locked'), findsOneWidget);
    expect(find.textContaining('has NOT been deleted'), findsOneWidget);
    expect(find.textContaining('keyMissingForExistingDatabase'), findsOneWidget);
    expect(find.textContaining('PBKDF2'), findsNothing);

    await tester.tap(_key('splash-restore'));
    await settle(tester, until: _key('restore-choose'));
    expect(find.byType(RestoreScreen), findsOneWidget);
    expect(find.textContaining('kept aside, not deleted'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('forgot PIN: the Admin Recovery Code resets it, a new code is '
      'shown once, then the Admin is signed in', (tester) async {
    final h = AppHarness();
    final issued = (await tester.runAsync(
      () => LocalAuthRepository(
        userRepository: DriftUserRepository(h.db),
        keyStore: h.store,
      ).setupBootstrapAdmin(displayName: 'Synthetic Admin', pin: _pin),
    ))!;
    await tester.runAsync(
      () => LocalAuthRepository(
        userRepository: DriftUserRepository(h.db),
        keyStore: h.store,
      ).logout(),
    );
    await h.launch(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.tap(_key('login-forgot-pin'));
    await settle(tester, until: _key('recover-code'));
    await tester.enterText(_key('recover-code'), issued.recoveryCode!.toLowerCase());
    await tester.enterText(_key('recover-pin'), _newPin);
    await tester.enterText(_key('recover-confirm-pin'), _newPin);
    await tester.tap(_key('recover-submit'));

    await _confirmShownCode(tester);
    await settle(tester, until: find.byType(HomeScreen));
    expect(find.byType(HomeScreen), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('a wrong recovery code shows a plain message and stays put',
      (tester) async {
    final h = AppHarness();
    await tester.runAsync(
      () => h.provision(
        id: 'admin',
        role: AppRole.ADMIN,
        verifier: deriveCredentialVerifier(_pin),
      ),
    );
    await h.launch(tester);
    await tester.tap(_key('login-forgot-pin'));
    await settle(tester, until: _key('recover-code'));

    await tester.enterText(_key('recover-code'), 'AR-0000-0000');
    await tester.enterText(_key('recover-pin'), _newPin);
    await tester.enterText(_key('recover-confirm-pin'), _newPin);
    await tester.tap(_key('recover-submit'));
    await settle(tester, until: _key('recover-error'));

    expect(find.textContaining('27 letters and numbers'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    await h.dispose(tester);
  });

  group('Admin-only screens', () {
    Future<GoRouter> pumpAs(WidgetTester tester, AppHarness h, AppRole role) async {
      final router = createRouter(
        authStatus: ValueNotifier(
          AuthAuthenticated(
            AuthSession(userId: 'u', role: role, loggedInAt: DateTime.utc(2026)),
          ),
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await settle(tester);
      return router;
    }

    for (final role in [AppRole.MEDICAL_OFFICER, AppRole.TEAM_MEMBER]) {
      testWidgets('${role.name} jumping straight to backup or recovery-code '
          'lands on Home', (tester) async {
        final h = AppHarness();
        final router = await pumpAs(tester, h, role);
        for (final route in Routes.adminOnly) {
          router.go(route);
          await settle(tester);
          expect(find.byType(HomeScreen), findsOneWidget, reason: route);
          expect(find.byType(BackupScreen), findsNothing);
        }
        await h.dispose(tester);
      });
    }

    testWidgets('ADMIN can open the backup screen', (tester) async {
      final h = AppHarness();
      final router = await pumpAs(tester, h, AppRole.ADMIN);
      router.go(Routes.moreBackup);
      await settle(tester, until: _key('backup-setup-key'));
      expect(find.byType(BackupScreen), findsOneWidget);
      await h.dispose(tester);
    });
  });

  testWidgets('setting up the Backup Recovery Key needs the Admin PIN, then '
      'shows the key once', (tester) async {
    final h = AppHarness();
    await tester.runAsync(
      () => h.provision(
        id: 'admin',
        role: AppRole.ADMIN,
        verifier: deriveCredentialVerifier(_pin),
      ),
    );
    h.persistSession('admin', AppRole.ADMIN);
    await h.launch(tester);
    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('More')),
    );
    await settle(tester);
    await tester.tap(_key('more-item-Backup Export'));
    await settle(tester, until: _key('backup-setup-key'));

    await tester.tap(_key('backup-setup-key'));
    await settle(tester, until: _key('pin-confirm-field'));
    await tester.enterText(_key('pin-confirm-field'), _pin);
    await tester.pump();
    await tester.tap(_key('pin-confirm-submit'));

    await settle(tester, until: _key('recovery-code-text'));
    final key = tester.widget<Text>(_key('recovery-code-text')).data!;
    expect(key, startsWith('BK-'));
    for (final value in h.store.values.values) {
      expect(value, isNot(contains(key)));
    }
    await _confirmShownCode(tester);
    await settle(tester, until: _key('backup-key-id'));
    expect(_key('backup-export'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('after a restore with no Admin PIN on the phone, login offers '
      'Admin access with the Backup Recovery Key', (tester) async {
    final h = AppHarness();
    // A restored Admin: a users row, but no PIN on this phone.
    await tester.runAsync(
      () => h.db.into(h.db.users).insert(
        UsersCompanion.insert(
          id: 'restored-admin',
          displayName: 'Restored Admin',
          role: AppRole.ADMIN,
        ),
      ),
    );
    await h.launch(tester);

    expect(_key('login-restored-banner'), findsOneWidget);
    await tester.tap(_key('login-restore-admin'));
    await settle(tester, until: _key('restore-admin-submit'));
    expect(_key('restore-admin-restored-admin'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('a restore that fails part-way shows a plain message, leaves '
      'the phone as it was, and replaces the closed database connection',
      (tester) async {
    final h = AppHarness();
    final a = Phone('ui_a');
    final b = Phone('ui_b');
    addTearDown(a.delete);
    addTearDown(b.delete);
    late SecretCode backupKey;
    await tester.runAsync(() async {
      final db = await a.open();
      await a.auth(db).setupBootstrapAdmin(displayName: 'Admin A', pin: _pin);
      backupKey = await a.service().createBackupKey(
        auth: a.auth(db),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
      final made = await a.service().createPackage(
        db,
        auth: a.auth(db),
        currentPin: _pin,
        audit: DatabaseSecurityAuditLog(db),
      );
      h.gateway.nextPick = await made.copy('${a.dir.path}/picked.rbskrp');
      await db.close();
    });

    var databaseBuilds = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          authRepositoryProvider.overrideWith(
            (ref) async => throw const DatabaseKeyUnavailableException(
              DatabaseKeyUnavailableReason.keyMissingForExistingDatabase,
            ),
          ),
          // Succeeds, so only an explicit invalidate rebuilds it (a failing
          // provider would be retried automatically).
          appDatabaseProvider.overrideWith((ref) async {
            databaseBuilds++;
            final db = openTestDatabase();
            ref.onDispose(db.close);
            return db;
          }),
          databaseRecoveryServiceProvider.overrideWithValue(
            DatabaseRecoveryService(
              keyManager: b.keyManager,
              backupKeys: b.backupKeys,
              databaseFileLocator: () async => b.dbFile,
              workDirectory: () async => Directory('${b.dir.path}/work'),
              preOpenAudit: b.journal,
              beforeRestoreStep: (step) {
                if (step == RestoreStep.installDatabaseKey) {
                  throw StateError('injected failure');
                }
              },
            ),
          ),
        ],
        child: const RbskApp(),
      ),
    );
    await settle(tester, until: _key('splash-error'));
    ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).listen(appDatabaseProvider, (_, _) {});
    await settle(tester);
    final buildsBefore = databaseBuilds;

    await tester.tap(_key('splash-restore'));
    await settle(tester, until: _key('restore-choose'));
    await tester.tap(_key('restore-choose'));
    await settle(tester, until: _key('restore-backup-key'));
    await tester.enterText(_key('restore-backup-key'), backupKey.formatted);
    await tester.tap(_key('restore-verify'));
    await settle(tester, until: _key('restore-understood'));
    await tester.tap(_key('restore-understood'));
    await tester.pump();
    await tester.tap(_key('restore-install'));
    await settle(tester, until: _key('restore-error'));

    expect(find.textContaining('Nothing has been deleted'), findsOneWidget);
    expect(databaseBuilds, greaterThan(buildsBefore), reason: 'reopened');
    expect(b.dbFile.existsSync(), isFalse, reason: 'rolled back');
    expect(File('${b.dbFile.path}.restore-marker').existsSync(), isFalse);
    await h.dispose(tester);
  });
}
