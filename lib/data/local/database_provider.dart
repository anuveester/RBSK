import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'database_connection.dart';

/// The single, centralized access point for the app database
/// (Phase 1.2 instruction §4: "Do not initialize the database from arbitrary
/// UI widgets. Keep database lifecycle management centralized.").
///
/// `flutter_riverpod`'s `FutureProvider` keeps this a singleton for the
/// app's lifetime and closes the connection automatically when the
/// [ProviderScope] is disposed (app shutdown or test teardown) — no widget
/// opens or closes a database connection itself.
final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final executor = await openEncryptedDatabase();
  final database = AppDatabase(executor);

  ref.onDispose(() {
    // ignore: unawaited_futures
    database.close();
  });

  return database;
});
