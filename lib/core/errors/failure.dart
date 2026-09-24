/// Base type for recoverable errors surfaced to the UI.
///
/// Later phases extend this per layer (local database, sync, OCR, export) so a
/// screen can react to a failure without catching raw exceptions.
sealed class Failure {
  const Failure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message, {super.cause});
}

/// Auth failures (Phase 1.4, docs/28_AUTHENTICATION_ARCHITECTURE_DECISION.md).
/// Deliberately carry no credential material in [Failure.message] — these
/// are shown directly to the UI.
final class BootstrapAlreadyCompletedFailure extends Failure {
  const BootstrapAlreadyCompletedFailure()
    : super('Admin setup has already been completed on this device.');
}

final class InvalidPinFormatFailure extends Failure {
  const InvalidPinFormatFailure() : super('PIN must be exactly 6 digits.');
}

final class InvalidDisplayNameFailure extends Failure {
  const InvalidDisplayNameFailure() : super('Name is required.');
}

final class InvalidCredentialsFailure extends Failure {
  const InvalidCredentialsFailure() : super('Incorrect PIN.');
}

final class AccountDeactivatedFailure extends Failure {
  const AccountDeactivatedFailure() : super('This account is deactivated.');
}

/// The local brute-force mitigation (docs/28 §Security). [retryAfter] is the
/// remaining cooldown — shown to the user, not a secret.
final class AccountLockedFailure extends Failure {
  const AccountLockedFailure(this.retryAfter)
    : super('Too many incorrect attempts. Try again shortly.');

  final Duration retryAfter;
}

final class NoActiveSessionFailure extends Failure {
  const NoActiveSessionFailure() : super('No active session.');
}

/// Recovery failures. Messages are written for a Medical Officer, not a
/// developer, and never contain code or key material.
final class NoRecoveryCodeFailure extends Failure {
  const NoRecoveryCodeFailure()
    : super('No Admin Recovery Code has been set up on this phone.');
}

final class InvalidRecoveryCodeFailure extends Failure {
  const InvalidRecoveryCodeFailure()
    : super('That recovery code is not correct. Please check it and try again.');
}

final class RecoveryCodeTypingFailure extends Failure {
  const RecoveryCodeTypingFailure(super.message);
}

final class RecoveryAccountUnavailableFailure extends Failure {
  const RecoveryAccountUnavailableFailure()
    : super('The Admin account for this recovery code is not active on this phone.');
}

final class InvalidBackupKeyFailure extends Failure {
  const InvalidBackupKeyFailure()
    : super('That Backup Recovery Key is not correct for this data.');
}

final class NoBackupKeyFailure extends Failure {
  const NoBackupKeyFailure()
    : super('The Backup Recovery Key has not been set up on this phone yet.');
}

final class AdminAccessRestoreNotAllowedFailure extends Failure {
  const AdminAccessRestoreNotAllowedFailure()
    : super(
        'An Admin can already log in on this phone. '
        'Use the Admin Recovery Code if the PIN is forgotten.',
      );
}

final class NotAuthorizedFailure extends Failure {
  const NotAuthorizedFailure() : super('Only an Admin can do this.');
}

/// Secure storage on the phone could not be read or written. Nothing was
/// deleted.
final class SecureStorageFailure extends Failure {
  const SecureStorageFailure()
    : super(
        'This phone’s secure storage could not be used just now. '
        'Nothing has been deleted. Please try again.',
      );
}
