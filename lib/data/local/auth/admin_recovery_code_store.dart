import 'dart:convert';

import 'package:referredline/data/local/database_connection.dart';

/// The stored form of the Admin Recovery Code (docs/30 R1): a verifier only
/// — the code itself is shown once and never stored.
class AdminRecoveryRecord {
  const AdminRecoveryRecord({
    required this.userId,
    required this.verifier,
    required this.createdAt,
    required this.acknowledged,
  });

  /// The Admin whose PIN this code can reset.
  final String userId;

  /// Credential verifier of the code (same format and KDF as PINs).
  final String verifier;
  final DateTime createdAt;

  /// Whether the Admin confirmed they wrote the code down.
  final bool acknowledged;

  AdminRecoveryRecord copyWith({bool? acknowledged}) => AdminRecoveryRecord(
    userId: userId,
    verifier: verifier,
    createdAt: createdAt,
    acknowledged: acknowledged ?? this.acknowledged,
  );
}

/// One record per phone, in [SecureKeyStore]. Replacing it (a new code)
/// invalidates the old code — that is how a code is used only once.
class AdminRecoveryCodeStore {
  AdminRecoveryCodeStore(this._store);

  final SecureKeyStore _store;

  static const String storageKey = 'rbsk_admin_recovery_code_v1';

  /// Null if none is set up. Throws [SecureStorageUnavailableException] if the
  /// store can't be read; returns null for an unreadable (corrupted) value.
  Future<AdminRecoveryRecord?> read() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AdminRecoveryRecord(
        userId: map['userId'] as String,
        verifier: map['verifier'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        acknowledged: map['acknowledged'] as bool,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> write(AdminRecoveryRecord record) => _store.write(
    storageKey,
    jsonEncode({
      'userId': record.userId,
      'verifier': record.verifier,
      'createdAt': record.createdAt.toUtc().toIso8601String(),
      'acknowledged': record.acknowledged,
    }),
  );
}
