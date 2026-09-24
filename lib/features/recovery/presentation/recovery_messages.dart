import 'package:referredline/core/platform/recovery_file_gateway.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/recovery/database_recovery_service.dart';
import 'package:referredline/data/local/recovery/recovery_package.dart';

/// Plain-language messages for a Medical Officer. Technical detail (the
/// reason name) is shown separately as a short reference for support, never
/// secrets.
String recoveryErrorMessage(Object error) => switch (error) {
  SecretCodeFormatException(:final problem) => switch (problem) {
    SecretCodeProblem.wrongKind =>
      'This looks like the Admin Recovery Code. Please enter the Backup '
          'Recovery Key (it starts with BK).',
    SecretCodeProblem.checkFailed =>
      'There is a typing mistake in the key. Please check each character.',
    SecretCodeProblem.invalidFormat =>
      'The key should have 27 letters and numbers, like '
          'BK-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXX.',
  },
  RecoveryPackageException(:final reason) => switch (reason) {
    RecoveryPackageError.notARecoveryPackage =>
      'This file is not an RBSK recovery package. Please choose the backup '
          'file (it ends with .rbskrp).',
    RecoveryPackageError.unsupportedVersion =>
      'This backup was made by a different version of the app and cannot be '
          'opened by this version.',
    RecoveryPackageError.differentBackupKey =>
      'This backup was made with a different Backup Recovery Key. Please '
          'check you have the right key for this backup.',
    RecoveryPackageError.authenticationFailed ||
    RecoveryPackageError.databaseIntegrityFailed ||
    RecoveryPackageError.malformed =>
      'This backup file is damaged or has been changed, so it cannot be '
          'trusted. Nothing on this phone was changed. Please try another '
          'copy of the backup.',
    RecoveryPackageError.tooLarge =>
      'This file is too large to be an RBSK backup.',
    RecoveryPackageError.databaseDoesNotOpen =>
      'The data inside this backup could not be opened. Nothing on this '
          'phone was changed.',
  },
  PlaintextDatabaseException() =>
    'The data on this phone is not stored encrypted, so it was not exported. '
        'Please contact your RBSK administrator.',
  NoBackupKeyException() =>
    'The Backup Recovery Key has not been set up on this phone yet.',
  DatabaseKeyUnavailableException() =>
    'The secure key for the data could not be saved. Nothing has been '
        'deleted. Please try again.',
  RecoveryFileTransferException() =>
    'The file could not be copied. Please try again or choose another '
        'location.',
  _ => 'Something went wrong. Nothing has been deleted. Please try again.',
};

String? recoveryErrorReference(Object error) => switch (error) {
  RecoveryPackageException(:final reason) => reason.name,
  DatabaseKeyUnavailableException(:final reason) => reason.name,
  SecretCodeFormatException(:final problem) => problem.name,
  _ => null,
};
