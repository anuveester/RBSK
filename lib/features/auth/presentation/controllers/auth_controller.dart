import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:referredline/domain/entities/auth_recovery.dart';
import 'package:referredline/domain/entities/auth_session.dart';
import 'package:referredline/domain/entities/auth_status.dart';

import 'auth_providers.dart';

/// Owns the app's current [AuthStatus] — the single source the router's
/// redirect logic reads. Every transition (setup, login, logout, recovery)
/// goes through here, so the router always reacts to the same state the UI
/// sees.
///
/// Operations that issue a new Admin Recovery Code (setup, PIN reset,
/// restoring Admin access) do **not** switch to authenticated immediately:
/// the code is shown once, and only when the Admin confirms it is written
/// down does [completeAfterRecoveryCode] move on. That keeps the code on
/// screen instead of the router navigating away from it.
///
/// Failures from the repository are rethrown to the calling screen
/// unchanged, so the screen can show the right message.
class AuthController extends AsyncNotifier<AuthStatus> {
  AuthSession? _pendingSession;

  @override
  Future<AuthStatus> build() async {
    _pendingSession = null;
    final repository = await ref.watch(authRepositoryProvider.future);
    return repository.determineStatus();
  }

  /// Returns the Admin Recovery Code to show once.
  Future<String> setupBootstrapAdmin({
    required String displayName,
    required String pin,
  }) async {
    final repository = await ref.read(authRepositoryProvider.future);
    final issued = await repository.setupBootstrapAdmin(
      displayName: displayName,
      pin: pin,
    );
    ref.invalidate(activeUsersProvider);
    _pendingSession = issued.session;
    return issued.recoveryCode!;
  }

  Future<RecoveryCodeIssued> resetPinWithRecoveryCode({
    required String recoveryCode,
    required String newPin,
  }) async {
    final repository = await ref.read(authRepositoryProvider.future);
    final issued = await repository.resetPinWithRecoveryCode(
      recoveryCode: recoveryCode,
      newPin: newPin,
    );
    _pendingSession = issued.session;
    return issued;
  }

  Future<RecoveryCodeIssued> restoreAdminAccess({
    required String backupKey,
    required String adminUserId,
    required String newPin,
  }) async {
    final repository = await ref.read(authRepositoryProvider.future);
    final issued = await repository.restoreAdminAccess(
      backupKey: backupKey,
      adminUserId: adminUserId,
      newPin: newPin,
    );
    _pendingSession = issued.session;
    return issued;
  }

  /// Called once the Admin has written the new code down (or, if the code
  /// could not be saved, has read that message). Records the confirmation
  /// and signs in.
  Future<void> completeAfterRecoveryCode({required bool codeWasShown}) async {
    final repository = await ref.read(authRepositoryProvider.future);
    if (codeWasShown) {
      await repository.confirmRecoveryCodeRecorded();
    }
    ref.invalidate(adminRecoveryStatusProvider);
    ref.invalidate(adminCanLogInProvider);
    final session = _pendingSession;
    _pendingSession = null;
    if (session != null) {
      state = AsyncData(AuthAuthenticated(session));
    }
  }

  Future<void> login({required String userId, required String pin}) async {
    final repository = await ref.read(authRepositoryProvider.future);
    final session = await repository.login(userId: userId, pin: pin);
    state = AsyncData(AuthAuthenticated(session));
  }

  Future<void> logout() async {
    final repository = await ref.read(authRepositoryProvider.future);
    await repository.logout();
    state = const AsyncData(AuthLoggedOut());
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthStatus>(AuthController.new);
