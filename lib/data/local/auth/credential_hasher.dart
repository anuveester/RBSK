import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Derives and verifies the local credential verifier for Phase 1.4's Option
/// A authentication (docs/28_AUTHENTICATION_ARCHITECTURE_DECISION.md §7,
/// §11, §18). The raw PIN is never stored — only this derived, salted,
/// one-way verifier is.
///
/// **Algorithm: PBKDF2-HMAC-SHA256.** Chosen over a fast hash (plain SHA-256
/// via `package:crypto`, explicitly rejected per the approved final
/// decisions) because a 6-digit PIN's small keyspace (§Parameters below)
/// needs a deliberately slow, tunable primitive to resist offline brute
/// force if the stored verifier is ever extracted. `pointycastle` was
/// selected over alternatives (`bcrypt`, `argon2`-family packages) after
/// checking pub.dev directly this phase: it is pure Dart (no native/platform
/// build step — this project already has one native-build dependency,
/// `sqlite3mc`, and deliberately avoids a second one), has ~3.66M downloads
/// and 415 likes (vs. the `bcrypt` package's ~50k downloads / 45 likes),
/// and is compatible with this project's Dart SDK constraint (`^3.13.2`).
/// Argon2 (memory-hard, arguably stronger) was not chosen because the
/// actively-maintained Dart/Flutter options for it are native-binding based,
/// which would repeat the exact native-build fragility this project already
/// hit once with `sqlcipher_flutter_libs` (docs/24_PHASE_1_2_REPORT.md §C) —
/// not a risk worth taking for this phase's credential layer.
///
/// **Parameters:**
/// - Iterations: **210,000**. OWASP's current (2023) Password Storage Cheat
///   Sheet recommends 600,000 for PBKDF2-HMAC-SHA256, benchmarked against
///   dedicated GPU hardware attacking a *stolen* verifier. This
///   implementation uses 210,000 instead — a deliberate, documented
///   trade-off, not an oversight: it runs as pure Dart (not
///   hardware-accelerated native code) on Android hardware as old as
///   `minSdk 26`, and login happens many times per field workday, so
///   verification latency matters for a shared departmental device. 210,000
///   is still far above the widely-deployed 100,000-iteration baseline from
///   a decade of PBKDF2 usage. The iteration count is embedded in the
///   verifier string itself (see Verifier format below), so raising it later
///   never invalidates existing verifiers — each user's verifier is
///   upgraded transparently the next time they reset their credential, the
///   standard PBKDF2 upgrade path. **This value has not been benchmarked on
///   real RBSK field hardware in this environment — benchmarking on an
///   actual target device before production rollout is recommended, not
///   assumed adequate.**
/// - Salt: 16 bytes (128-bit), generated with `Random.secure()` per
///   credential — the same cryptographically secure generator already
///   proven for the database encryption passphrase
///   (`database_connection.dart`'s `generatePassphrase()`). The salt is
///   **not treated as a secret** — it is stored alongside the derived hash
///   in the verifier string, exactly as PBKDF2's design intends; its purpose
///   is to defeat precomputed (rainbow-table) attacks and ensure two users
///   with the same PIN get unrelated stored verifiers, not to add secrecy.
/// - Derived key length: 32 bytes (256-bit).
///
/// **Verifier format:** `pbkdf2-hmac-sha256$<iterations>$<base64 salt>$<base64 hash>`
/// — a single self-describing string (the same style as Django's/Werkzeug's
/// password-hash format), so the algorithm and iteration count travel with
/// the verifier rather than being assumed from context.
const String credentialAlgorithmTag = 'pbkdf2-hmac-sha256';
const int credentialIterations = 210000;
const int _saltLengthBytes = 16;
const int _derivedKeyLengthBytes = 32;

/// Runs [deriveCredentialVerifier] on a background isolate. At 210,000
/// iterations the derivation is CPU-bound for a noticeable moment; running
/// it on the UI isolate would freeze the screen (including its progress
/// indicator) while it computes.
Future<String> deriveCredentialVerifierInBackground(String pin) =>
    Isolate.run(() => deriveCredentialVerifier(pin));

/// Runs [verifyCredential] on a background isolate — see
/// [deriveCredentialVerifierInBackground].
Future<bool> verifyCredentialInBackground(String pin, String verifier) =>
    Isolate.run(() => verifyCredential(pin, verifier));

/// Derives a verifier string for [pin]. Never logs or returns the raw PIN.
String deriveCredentialVerifier(String pin) {
  final salt = _randomBytes(_saltLengthBytes);
  final derived = _pbkdf2(
    utf8.encode(pin),
    salt,
    credentialIterations,
    _derivedKeyLengthBytes,
  );
  return '$credentialAlgorithmTag\$$credentialIterations\$'
      '${base64Encode(salt)}\$${base64Encode(derived)}';
}

/// Verifies [pin] against a previously-derived [verifier]. Returns false
/// (never throws) for a malformed verifier — a corrupted stored value must
/// fail closed, not crash the login screen.
bool verifyCredential(String pin, String verifier) {
  final parts = verifier.split(r'$');
  if (parts.length != 4 || parts[0] != credentialAlgorithmTag) {
    return false;
  }

  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations <= 0) {
    return false;
  }

  final Uint8List salt;
  final Uint8List expected;
  try {
    salt = base64Decode(parts[2]);
    expected = base64Decode(parts[3]);
  } on FormatException {
    return false;
  }
  // An empty or truncated key would compare equal to an equally short
  // derivation, so such a verifier would accept any PIN. Fail closed.
  if (expected.length != _derivedKeyLengthBytes) {
    return false;
  }

  final actual = _pbkdf2(utf8.encode(pin), salt, iterations, expected.length);
  return _constantTimeEquals(actual, expected);
}

Uint8List _pbkdf2(
  List<int> password,
  Uint8List salt,
  int iterations,
  int keyLengthBytes,
) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iterations, keyLengthBytes));
  return derivator.process(Uint8List.fromList(password));
}

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

/// Constant-time comparison — an early-exit `==` would leak timing
/// information about how many leading bytes matched.
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
