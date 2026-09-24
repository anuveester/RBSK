import 'package:drift/drift.dart' show QueryExecutor;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'database_connection.dart';
import 'recovery/recovery_providers.dart';
import 'security/security_audit.dart';
import 'security/security_providers.dart';

/// The one [DatabaseKeyManager] (isolated key namespace, no destructive
/// resets — see [FlutterSecureStorageKeyStore.databaseKey]).
final databaseKeyManagerProvider = Provider<DatabaseKeyManager>(
  (ref) => DatabaseKeyManager(),
);

/// The single, centralized access point for the app database
/// (Phase 1.2 instruction §4: "Do not initialize the database from arbitrary
/// UI widgets. Keep database lifecycle management centralized.").
///
/// Before opening, a restore that was interrupted (crash, power loss) is
/// finished or undone, so the database is never opened half-restored; if
/// that cannot be done the open fails and is retried later.
///
/// If the database key is unavailable this provider fails with
/// [DatabaseKeyUnavailableException] — after recording the event — and
/// nothing is created, replaced or deleted. On a successful open, security
/// events recorded while the database was unavailable are moved into
/// `audit_log`.
final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final journal = ref.watch(securityEventJournalProvider);
  final recovery = ref.watch(databaseRecoveryServiceProvider);
  await recovery.resolveInterruptedRestore();
  await ref.read(recoveryLeftoversRemovedProvider.future);

  final QueryExecutor executor;
  try {
    executor = await openEncryptedDatabase(
      keyManager: ref.watch(databaseKeyManagerProvider),
    );
  } on DatabaseKeyUnavailableException catch (e) {
    await journal.record(
      SecurityEvent(
        SecurityEventType.databaseKeyUnavailable,
        details: {'reason': e.reason.name},
      ),
    );
    rethrow;
  }
  final database = AppDatabase(executor);

  ref.onDispose(() {
    // ignore: unawaited_futures
    closeAppDatabase(database);
  });

  await DatabaseSecurityAuditLog(database).flushPending(journal);
  return database;
});

final Expando<Future<void>> _closing = Expando<Future<void>>();

/// Closes [database] once; later calls return the same future. Used by the
/// restore flow, which must close the database before moving its file,
/// and by provider disposal.
Future<void> closeAppDatabase(AppDatabase database) =>
    _closing[database] ??= database.close();
