import 'dart:math';

/// Generates a random, locally-unique identifier for a `users` row created
/// at runtime (the bootstrap Admin; later, any Admin-created user).
///
/// Reuses the exact same `Random.secure()` pattern already proven for the
/// database encryption passphrase (`generatePassphrase()` in
/// `data/local/database_connection.dart`) rather than adding the `uuid`
/// package as a new dependency — 128 bits of cryptographically secure
/// randomness, hex-encoded, is collision-resistant enough for this project's
/// ~8–10 user scale, and the `users.id` column is a plain TEXT primary key
/// with no format constraint (Phase 1.3's own seed data already uses
/// deterministic string ids like `'staff-rajni-pratap'`, not strict
/// UUIDv4 — this project has never enforced UUID formatting at the schema
/// level, only uniqueness).
String generateLocalId(String prefix) {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '$prefix-$hex';
}
