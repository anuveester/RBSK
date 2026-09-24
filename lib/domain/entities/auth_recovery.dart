import 'auth_session.dart';

/// Result of an operation that ends by showing a new Admin Recovery Code
/// once (first-run setup, PIN reset, restoring Admin access, or creating a
/// new code).
class RecoveryCodeIssued {
  const RecoveryCodeIssued({
    required this.session,
    required this.recoveryCode,
    this.recoveryCodeSaved = true,
  });

  final AuthSession session;

  /// The formatted code, for one-time display. Null only when
  /// [recoveryCodeSaved] is false.
  final String? recoveryCode;

  /// False if the PIN was changed but the new recovery code could not be
  /// saved; the previous code then remains valid.
  final bool recoveryCodeSaved;

  @override
  String toString() => 'RecoveryCodeIssued(redacted)';
}

/// Whether this phone has an Admin Recovery Code, without revealing it.
class AdminRecoveryStatus {
  const AdminRecoveryStatus({
    required this.exists,
    this.adminUserId,
    this.acknowledged = false,
    this.createdAt,
  });

  static const none = AdminRecoveryStatus(exists: false);

  final bool exists;
  final String? adminUserId;
  final bool acknowledged;
  final DateTime? createdAt;
}
