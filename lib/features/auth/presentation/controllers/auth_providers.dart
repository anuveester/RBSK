import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/database_provider.dart';
import 'package:referredline/data/repositories/drift_user_repository.dart';
import 'package:referredline/data/repositories/local_auth_repository.dart';
import 'package:referredline/domain/entities/app_user.dart';
import 'package:referredline/domain/repositories/auth_repository.dart';
import 'package:referredline/domain/repositories/user_repository.dart';

/// Android Keystore-backed, same production implementation the database
/// encryption key already uses (Phase 1.2) — reused, not duplicated.
final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => const FlutterSecureStorageKeyStore(),
);

final userRepositoryProvider = FutureProvider<UserRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftUserRepository(db);
});

/// The single wiring point for [AuthRepository] — swapping
/// `LocalAuthRepository` for a future cloud-backed implementation
/// (docs/28_AUTHENTICATION_ARCHITECTURE_DECISION.md §10) only changes this
/// provider.
final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final userRepository = await ref.watch(userRepositoryProvider.future);
  final keyStore = ref.watch(secureKeyStoreProvider);
  return LocalAuthRepository(
    userRepository: userRepository,
    keyStore: keyStore,
  );
});

/// Active users for the login screen's identity picker (docs/28 §Login UX —
/// select yourself from the known ~8–10 team members, then enter a PIN,
/// rather than typing a username/email every time on a shared field device).
final activeUsersProvider = FutureProvider<List<AppUser>>((ref) async {
  final userRepository = await ref.watch(userRepositoryProvider.future);
  return userRepository.getAllActive();
});
