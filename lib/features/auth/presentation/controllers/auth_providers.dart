import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:referredline/core/platform/recovery_file_gateway.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/database_provider.dart';
import 'package:referredline/data/local/recovery/backup_key_store.dart';
import 'package:referredline/data/local/recovery/database_recovery_service.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:referredline/data/local/security/security_providers.dart';
import 'package:referredline/data/repositories/drift_user_repository.dart';
import 'package:referredline/data/repositories/local_auth_repository.dart';
import 'package:referredline/domain/entities/app_user.dart';
import 'package:referredline/domain/entities/auth_recovery.dart';
import 'package:referredline/domain/repositories/auth_repository.dart';
import 'package:referredline/domain/repositories/user_repository.dart';

/// General secure storage (credentials, sessions, lockout, recovery-code
/// and backup-key verifiers). Android Keystore-backed, and never resets
/// itself on error — see [FlutterSecureStorageKeyStore.general].
final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => const FlutterSecureStorageKeyStore.general(),
);

final userRepositoryProvider = FutureProvider<UserRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftUserRepository(db);
});

/// Security events go to `audit_log`, falling back to the pending journal.
final securityAuditProvider = FutureProvider<SecurityEventSink>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DatabaseSecurityAuditLog(
    db,
    fallback: ref.watch(securityEventJournalProvider),
  );
});

final backupKeyStoreProvider = Provider<BackupKeyStore>(
  (ref) => BackupKeyStore(ref.watch(secureKeyStoreProvider)),
);

/// The single wiring point for [AuthRepository] — swapping
/// `LocalAuthRepository` for a future cloud-backed implementation
/// (docs/28_AUTHENTICATION_ARCHITECTURE_DECISION.md §10) only changes this
/// provider.
final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final userRepository = await ref.watch(userRepositoryProvider.future);
  final audit = await ref.watch(securityAuditProvider.future);
  final keyStore = ref.watch(secureKeyStoreProvider);
  return LocalAuthRepository(
    userRepository: userRepository,
    keyStore: keyStore,
    audit: audit,
    backupKeys: ref.watch(backupKeyStoreProvider),
  );
});

/// Active users for the login screen's identity picker (docs/28 §Login UX —
/// select yourself from the known ~8–10 team members, then enter a PIN,
/// rather than typing a username/email every time on a shared field device).
final activeUsersProvider = FutureProvider<List<AppUser>>((ref) async {
  final userRepository = await ref.watch(userRepositoryProvider.future);
  return userRepository.getAllActive();
});

final adminRecoveryStatusProvider = FutureProvider<AdminRecoveryStatus>((
  ref,
) async {
  final repository = await ref.watch(authRepositoryProvider.future);
  return repository.adminRecoveryStatus();
});

/// False after a restore, until an Admin's PIN is set on this phone.
final adminCanLogInProvider = FutureProvider<bool>((ref) async {
  final repository = await ref.watch(authRepositoryProvider.future);
  return repository.hasAdminAbleToLogIn();
});

final recoveryFileGatewayProvider = Provider<RecoveryFileGateway>(
  (ref) => const AndroidRecoveryFileGateway(),
);

/// Working folder for packages on their way in or out. In the cache
/// directory, which platform backup never includes; files are removed after
/// each operation.
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
    databaseFileLocator: () => databaseFile(),
    workDirectory: ref.watch(recoveryWorkDirectoryProvider),
    preOpenAudit: ref.watch(securityEventJournalProvider),
  ),
);
