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

/// School/AWC master failures (Phase 1.5). Messages are shown to the user
/// as they are, so they are written in plain words.
final class NameRequiredFailure extends Failure {
  const NameRequiredFailure() : super('Please enter the name.');
}

/// A non-blank official code already belongs to another record. Saving is
/// blocked; the other record is named so the user can find it.
final class DuplicateOfficialCodeFailure extends Failure {
  const DuplicateOfficialCodeFailure({
    required String codeLabel,
    required String recordLabel,
    this.existingName,
  }) : super(
         existingName == null
             ? '$codeLabel already exists. This $recordLabel is already in '
                   'the master.'
             : '$codeLabel already exists. This $recordLabel is already in '
                   'the master: $existingName.',
       );

  final String? existingName;
}

final class MasterRecordNotFoundFailure extends Failure {
  const MasterRecordNotFoundFailure()
    : super('This record could not be found. It may have been changed.');
}
