import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:referredline/domain/entities/auth_status.dart';

import 'auth_providers.dart';

/// Owns the app's current [AuthStatus] — the single source the router's
/// redirect logic reads. Every transition (setup, login, logout) goes through
/// here, so the router always reacts to the same state the UI sees.
///
/// Failures from the underlying [AuthRepository] (wrong PIN, lockout,
/// deactivated account, bootstrap already done) are rethrown to the calling
/// screen unchanged, so the screen can show a specific message — this
/// controller's state only ever changes on a *successful* transition.
class AuthController extends AsyncNotifier<AuthStatus> {
  @override
  Future<AuthStatus> build() async {
    final repository = await ref.watch(authRepositoryProvider.future);
    return repository.determineStatus();
  }

  Future<void> setupBootstrapAdmin({
    required String displayName,
    required String pin,
  }) async {
    final repository = await ref.read(authRepositoryProvider.future);
    final session = await repository.setupBootstrapAdmin(
      displayName: displayName,
      pin: pin,
    );
    ref.invalidate(activeUsersProvider);
    state = AsyncData(AuthAuthenticated(session));
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
