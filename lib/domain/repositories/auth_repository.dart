import 'package:referredline/domain/entities/auth_recovery.dart';
import 'package:referredline/domain/entities/auth_session.dart';
import 'package:referredline/domain/entities/auth_status.dart';

/// Abstracted so the credential-verification mechanism stays replaceable if
/// a future cloud identity provider is introduced — see
/// docs/28_AUTHENTICATION_ARCHITECTURE_DECISION.md §10. Only
/// `LocalAuthRepository` (docs/28 Option A) implements this; nothing above
/// this interface (session handling, RBAC, audit) needs to change if that
/// implementation is ever replaced.
///
/// Every failure is a `Failure` with a message fit to show a Medical
/// Officer; none contains a PIN, code, or key.
abstract interface class AuthRepository {
  /// Reads current state without side effects — used by the router's
  /// redirect logic and app startup.
  Future<AuthStatus> determineStatus();

  /// Establishes the one bootstrap Admin account and its Admin Recovery
  /// Code. Throws `BootstrapAlreadyCompletedFailure` if any user already
  /// exists — the guard against accidentally re-running first-run setup.
  Future<RecoveryCodeIssued> setupBootstrapAdmin({
    required String displayName,
    required String pin,
  });

  /// Throws `InvalidCredentialsFailure`, `AccountDeactivatedFailure`, or
  /// `AccountLockedFailure` on failure — never returns a session for a
  /// rejected attempt. Upgrades an outdated PIN verifier after success.
  Future<AuthSession> login({required String userId, required String pin});

  Future<void> logout();

  /// Restores a persisted session, offline, with no network call. Returns
  /// null if no session is persisted, or if the persisted session's user no
  /// longer exists / is no longer active.
  Future<AuthSession?> currentSession();

  // --- Authorization for privileged operations ---

  /// The current session, re-checked against the `users` row, if it belongs
  /// to an active Admin. Throws `NoActiveSessionFailure` if nobody is logged
  /// in and `NotAuthorizedFailure` otherwise. Every Admin-only operation
  /// calls this itself; it never trusts a user id passed in by the caller.
  /// [operation] is a short, non-secret label for the audit trail.
  Future<AuthSession> requireAdminSession({String operation});

  /// [requireAdminSession] plus a fresh check of that Admin's PIN (counted
  /// by the lockout). Used before operations that hand out secrets or data.
  Future<AuthSession> reauthenticateAdmin({
    required String pin,
    String operation,
  });

  // --- Admin Recovery Code (docs/30 R1) ---

  Future<AdminRecoveryStatus> adminRecoveryStatus();

  /// The logged-in Admin confirmed that their current code is written down.
  /// Throws `NotAuthorizedFailure` unless the session is the code's Admin.
  Future<void> confirmRecoveryCodeRecorded();

  /// Resets the Admin's PIN with the Admin Recovery Code. The code is used
  /// up and a new one is issued. The database and its key are not touched.
  Future<RecoveryCodeIssued> resetPinWithRecoveryCode({
    required String recoveryCode,
    required String newPin,
  });

  /// Replaces the Admin Recovery Code (the old one stops working) for the
  /// logged-in Admin, after re-checking their PIN. Returns the new code for
  /// one-time display.
  Future<String> createNewRecoveryCode({required String currentPin});

  // --- After a restore (docs/30 R5) ---

  /// Whether at least one active Admin has a PIN on this phone.
  Future<bool> hasAdminAbleToLogIn();

  /// Sets a PIN for an Admin in restored data, authorized by the Backup
  /// Recovery Key. Refused if any Admin can already log in on this phone.
  Future<RecoveryCodeIssued> restoreAdminAccess({
    required String backupKey,
    required String adminUserId,
    required String newPin,
  });
}
