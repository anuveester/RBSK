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

/// Micro Plan import failures (Phase 1.6). Plain words: shown as they are.
final class FinancialYearNotFoundFailure extends Failure {
  const FinancialYearNotFoundFailure(this.label)
    : super(
        label == null
            ? 'The Micro Plan does not say which financial year it is for.'
            : 'Financial year $label is not set up in the app.',
      );

  final String? label;
}

/// A Micro Plan for this financial year is already imported and has not
/// been undone [USER-DECIDED 2026-09-25, option A].
final class MicroPlanAlreadyImportedFailure extends Failure {
  const MicroPlanAlreadyImportedFailure(this.financialYearLabel, this.importId)
    : super(
        'The Micro Plan for $financialYearLabel is already imported. '
        'Undo that import first if it was a mistake.',
      );

  final String financialYearLabel;
  final String importId;
}

final class MicroPlanImportNotFoundFailure extends Failure {
  const MicroPlanImportNotFoundFailure()
    : super('This import could not be found.');
}

final class MicroPlanImportAlreadyUndoneFailure extends Failure {
  const MicroPlanImportAlreadyUndoneFailure()
    : super('This import has already been undone.');
}

/// Undo is only allowed while no work has started on any visit or holiday
/// from the import — field work is never erased.
final class MicroPlanUndoBlockedFailure extends Failure {
  const MicroPlanUndoBlockedFailure(this.touchedCount)
    : super(
        'This import cannot be undone: work has already started on '
        '$touchedCount of its visits or holidays.',
      );

  final int touchedCount;
}
