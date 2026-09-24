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
