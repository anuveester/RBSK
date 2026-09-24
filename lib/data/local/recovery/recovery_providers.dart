import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/database_provider.dart';
import 'package:referredline/data/local/security/security_providers.dart';

import 'backup_key_store.dart';
import 'database_recovery_service.dart';

final backupKeyStoreProvider = Provider<BackupKeyStore>(
  (ref) => BackupKeyStore(ref.watch(secureKeyStoreProvider)),
);

/// Where the database file lives.
final databaseFileLocatorProvider = Provider<Future<File> Function()>(
  (ref) => () => databaseFile(),
);

/// Working folder for packages on their way in or out. In the cache
/// directory, which platform backup never includes; files are removed after
/// each operation, and anything left over is removed at start-up.
final recoveryWorkDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    final dir = await getTemporaryDirectory();
    return Directory(p.join(dir.path, 'recovery'));
  },
);

final databaseRecoveryServiceProvider = Provider<DatabaseRecoveryService>(
  (ref) => DatabaseRecoveryService(
    keyManager: ref.watch(databaseKeyManagerProvider),
    backupKeys: ref.watch(backupKeyStoreProvider),
    databaseFileLocator: ref.watch(databaseFileLocatorProvider),
    workDirectory: ref.watch(recoveryWorkDirectoryProvider),
    preOpenAudit: ref.watch(securityEventJournalProvider),
  ),
);

/// Start-up clean-up of files an interrupted export or import left behind.
/// Runs once per app process (it is read, not watched, by the database
/// provider), before anything can be in progress.
final recoveryLeftoversRemovedProvider = FutureProvider<void>(
  (ref) => ref.read(databaseRecoveryServiceProvider).removeLeftoverFiles(),
);
