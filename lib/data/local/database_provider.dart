import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'database_connection.dart';

/// The one [DatabaseKeyManager] (isolated key namespace, no destructive
/// resets — see [FlutterSecureStorageKeyStore.databaseKey]).
final databaseKeyManagerProvider = Provider<DatabaseKeyManager>(
  (ref) => DatabaseKeyManager(),
);

/// The single, centralized access point for the app database
/// (Phase 1.2 instruction §4: "Do not initialize the database from arbitrary
/// UI widgets. Keep database lifecycle management centralized.").
///
/// Opened lazily, by the first feature that reads it. If the database key is
/// unavailable this provider fails with [DatabaseKeyUnavailableException],
/// and nothing is created, replaced or deleted.
///
/// `flutter_riverpod`'s `FutureProvider` keeps this a singleton for the
/// app's lifetime and closes the connection when the [ProviderScope] is
/// disposed (app shutdown or test teardown).
final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final executor = await openEncryptedDatabase(
    keyManager: ref.watch(databaseKeyManagerProvider),
  );
  final database = AppDatabase(executor);

  ref.onDispose(() {
    // ignore: unawaited_futures
    database.close();
  });

  return database;
});
