import 'dart:convert';

import 'package:referredline/data/local/enums.dart';
import 'package:referredline/domain/entities/auth_session.dart';

/// Encodes/decodes [AuthSession] for persistence in [SecureKeyStore]. Only
/// `userId`, `role`, and a timestamp are stored — no health information, no
/// credential material (docs/27_PHASE_1_4_PLAN.md §12).
String encodeAuthSession(AuthSession session) => jsonEncode({
  'userId': session.userId,
  'role': session.role.name,
  'loggedInAt': session.loggedInAt.toIso8601String(),
});

/// Returns null for a missing, empty, or malformed value — a corrupted
/// session entry must fail closed (treated as logged out), never crash.
AuthSession? decodeAuthSession(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return AuthSession(
      userId: map['userId'] as String,
      role: AppRole.values.byName(map['role'] as String),
      loggedInAt: DateTime.parse(map['loggedInAt'] as String),
    );
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  } on ArgumentError {
    return null;
  }
}
