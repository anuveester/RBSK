import 'package:referredline/domain/entities/auth_session.dart';
import 'package:referredline/domain/entities/auth_status.dart';

/// Abstracted so the credential-verification mechanism stays replaceable if
/// a future cloud identity provider is introduced — see
/// docs/28_AUTHENTICATION_ARCHITECTURE_DECISION.md §10. Only
/// `LocalAuthRepository` (docs/28 Option A) implements this in Phase 1.4;
/// nothing above this interface (session handling, RBAC, audit) needs to
/// change if that implementation is ever replaced.
abstract interface class AuthRepository {
  /// Reads current state without side effects — used by the router's
  /// redirect logic and app startup.
  Future<AuthStatus> determineStatus();

  /// Establishes the one bootstrap Admin account. Throws
  /// `BootstrapAlreadyCompletedFailure` if any user already exists — the
  /// guard against accidentally re-running first-run setup.
  Future<AuthSession> setupBootstrapAdmin({
    required String displayName,
    required String pin,
  });

  /// Throws `InvalidCredentialsFailure`, `AccountDeactivatedFailure`, or
  /// `AccountLockedFailure` on failure — never returns a session for a
  /// rejected attempt.
  Future<AuthSession> login({required String userId, required String pin});

  Future<void> logout();

  /// Restores a persisted session, offline, with no network call. Returns
  /// null if no session is persisted, or if the persisted session's user no
  /// longer exists / is no longer active.
  Future<AuthSession?> currentSession();
}
