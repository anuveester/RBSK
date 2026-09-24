import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:referredline/core/platform/recovery_file_gateway.dart';
import 'package:referredline/data/local/database_provider.dart';
import 'package:referredline/data/local/recovery/recovery_providers.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:referredline/data/local/security/security_providers.dart';
import 'package:referredline/data/repositories/drift_user_repository.dart';
import 'package:referredline/data/repositories/local_auth_repository.dart';
import 'package:referredline/domain/entities/app_user.dart';
import 'package:referredline/domain/entities/auth_recovery.dart';
import 'package:referredline/domain/repositories/auth_repository.dart';
import 'package:referredline/domain/repositories/user_repository.dart';

export 'package:referredline/data/local/recovery/recovery_providers.dart'
    show
        backupKeyStoreProvider,
        databaseRecoveryServiceProvider,
        recoveryWorkDirectoryProvider;
export 'package:referredline/data/local/security/security_providers.dart'
    show secureKeyStoreProvider;

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
