import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/app.dart';
import 'package:referredline/core/platform/recovery_file_gateway.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/auth/auth_session_codec.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/database_provider.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:referredline/data/local/security/security_providers.dart';
import 'package:referredline/data/repositories/drift_user_repository.dart';
import 'package:referredline/data/repositories/local_auth_repository.dart';
import 'package:referredline/domain/entities/auth_session.dart';
import 'package:referredline/features/auth/presentation/controllers/auth_providers.dart';

import '../data/local/test_database.dart';
import 'in_memory_secure_key_store.dart';

/// Runs the real app — real `LocalAuthRepository`, real router, real
/// screens — over an in-memory database and an in-memory key store, so
/// widget tests never touch path_provider or the Android Keystore.
class AppHarness {
  AppHarness()
    : db = openTestDatabase(),
      store = InMemorySecureKeyStore(),
      dbKeyStore = InMemorySecureKeyStore(),
      dir = Directory.systemTemp.createTempSync('rbsk_harness_') {
    // Removed even if the test fails before dispose().
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
  }

  final AppDatabase db;
  final InMemorySecureKeyStore store;
  final InMemorySecureKeyStore dbKeyStore;
  final Directory dir;
  final FakeRecoveryFileGateway gateway = FakeRecoveryFileGateway();

  PendingSecurityEventJournal get journal =>
      PendingSecurityEventJournal(() async => File('${dir.path}/journal.jsonl'));

  List<Override> get overrides => [
    userRepositoryProvider.overrideWith((ref) async => DriftUserRepository(db)),
    secureKeyStoreProvider.overrideWithValue(store),
    securityAuditProvider.overrideWith(
      (ref) async => DatabaseSecurityAuditLog(db, fallback: journal),
    ),
    securityEventJournalProvider.overrideWithValue(journal),
    databaseKeyManagerProvider.overrideWithValue(
      DatabaseKeyManager(store: dbKeyStore),
    ),
    recoveryWorkDirectoryProvider.overrideWithValue(
      () async => Directory('${dir.path}/work'),
    ),
    recoveryFileGatewayProvider.overrideWithValue(gateway),
  ];

  /// Pumps a fresh app instance. Calling it again with the same harness is
  /// an app restart: same database, same secure storage, new process state.
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides,
        child: const RbskApp(),
      ),
    );
    await settle(tester);
  }

  /// Adds a user with a pre-derived verifier (the way a future
  /// user-management phase would), since Phase 1.4 has no in-app flow for
  /// creating non-Admin users.
  Future<void> provision({
    required String id,
    required AppRole role,
    required String verifier,
    String displayName = 'Test User',
  }) async {
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(id: id, displayName: displayName, role: role),
        );
    store.values[credentialVerifierStorageKey(id)] = verifier;
  }

  /// Persists a session as if the user had logged in on a previous launch.
  void persistSession(String userId, AppRole role) {
    store.values[authSessionStorageKey] = encodeAuthSession(
      AuthSession(
        userId: userId,
        role: role,
        loggedInAt: DateTime.utc(2026, 9, 1),
      ),
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await db.close();
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
  }
}

/// Stand-in for Android's document picker: records saves, hands back a
/// prepared file for picks.
class FakeRecoveryFileGateway implements RecoveryFileGateway {
  final List<String> savedNames = [];
  File? nextPick;

  @override
  Future<bool> saveToDevice(File file, String suggestedName) async {
    savedNames.add(suggestedName);
    return true;
  }

  @override
  Future<File?> pickPackage(File destination) async {
    final source = nextPick;
    if (source == null) {
      return null;
    }
    await destination.parent.create(recursive: true);
    return source.copy(destination.path);
  }
}

/// Confirms a one-time recovery code screen the way a person would: scroll
/// to the checkbox, tick it, type the last group, tap Continue.
Future<void> confirmRecoveryCode(WidgetTester tester, String code) async {
  Finder key(String k) => find.byKey(ValueKey(k));
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(key('recovery-code-written'), 100, scrollable: scrollable);
  await tester.tap(key('recovery-code-written'));
  await tester.scrollUntilVisible(key('recovery-code-confirm'), 100, scrollable: scrollable);
  await tester.enterText(key('recovery-code-confirm'), code.split('-').last);
  await tester.pump();
  await tester.scrollUntilVisible(key('recovery-code-continue'), 100, scrollable: scrollable);
  await tester.tap(key('recovery-code-continue'));
}

/// Lets real asynchronous work finish (the KDF runs on a background isolate,
/// which fake-async test time cannot advance) and pumps frames until
/// [finder] matches — or, with no finder, for a short fixed period.
Future<void> settle(
  WidgetTester tester, {
  Finder? until,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  var quietRounds = 0;
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    // 100ms of frame time per round, so route transitions (~300ms) finish
    // within a few rounds; the progress indicators rule out pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 100));
    if (until != null) {
      if (until.evaluate().isNotEmpty) {
        await tester.pump();
        return;
      }
    } else if (++quietRounds >= 10) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for ${until ?? 'the app to settle'}');
}
