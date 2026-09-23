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
