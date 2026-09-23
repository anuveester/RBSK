import 'dart:math';

/// A random RFC 4122 version-4 UUID, for rows created at runtime (the
/// bootstrap Admin; later, any Admin-created user).
///
/// docs/04_DATABASE_ARCHITECTURE.md §0 requires client-generated UUIDv4
/// primary keys: the same value identifies the row locally and in the
/// cloud Postgres schema, whose frozen DDL declares `id uuid PRIMARY KEY`,
/// so the id must be a valid `uuid`, not just a unique string.
///
/// Built from `Random.secure()` (the generator already used for the
/// database passphrase) instead of adding the `uuid` package: v4 is 122
/// random bits plus fixed version/variant bits, formatted 8-4-4-4-12.
String generateUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
