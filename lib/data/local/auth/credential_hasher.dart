import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:referredline/core/security/crypto_utils.dart';

/// Derives and verifies local credential verifiers (6-digit PINs, and the
/// Admin Recovery Code). Only the derived, salted, one-way verifier is ever
/// stored — never the secret itself.
///
/// **Approved KDF (docs/30 §6, approved for now):** PBKDF2-HMAC-SHA256,
/// 210,000 iterations, 16-byte random salt, 32-byte derived key. The
/// iteration count is below OWASP's current 600,000; raising it is deferred
/// until a real Android device can be benchmarked. It lives only in
/// [CredentialKdfPolicy.current] — change it there and existing verifiers
/// are upgraded on the next successful login (see
/// `LocalAuthRepository.login`), with no migration.
///
/// **Why PBKDF2 and not Argon2id:** an earlier version of this comment (and
/// docs/27 §0.1) said Argon2 was rejected because the Dart options rely on
/// native bindings. That was wrong: `pointycastle` 4.0.0 — this dependency —
/// includes pure-Dart Argon2id. The actual reasons (docs/30 §4.4): for a
/// 6-digit PIN no KDF prevents offline exhaustion of 10⁶ values, the verifier
/// is only reachable by an attacker who can already read the database key,
/// and pure-Dart Argon2id performance and memory on target devices are
/// unmeasured.
///
/// **Verifier format:** `pbkdf2-hmac-sha256$<iterations>$<base64 salt>$<base64 key>`.
/// Self-describing, so each stored verifier carries the parameters it was
/// made with.
class CredentialKdfPolicy {
  const CredentialKdfPolicy({
    required this.iterations,
    this.saltLengthBytes = 16,
    this.derivedKeyLengthBytes = 32,
  });

  /// The approved parameters in force. The only place they are defined.
  static const CredentialKdfPolicy current = CredentialKdfPolicy(
    iterations: 210000,
  );

  static const String algorithmTag = 'pbkdf2-hmac-sha256';

  final int iterations;
  final int saltLengthBytes;
  final int derivedKeyLengthBytes;
}

// Bounds for accepting a stored verifier. A value outside them is treated as
// corrupted and fails closed: too few iterations would make a tampered
// verifier cheap to satisfy; an absurd count would hang verification.
const int _minAcceptedIterations = 10000;
const int _maxAcceptedIterations = 10000000;
const int _minAcceptedSaltBytes = 16;
const int _minAcceptedKeyBytes = 32;
const int _maxAcceptedKeyBytes = 64;

class _ParsedVerifier {
  const _ParsedVerifier(this.iterations, this.salt, this.key);

  final int iterations;
  final Uint8List salt;
  final Uint8List key;
}

_ParsedVerifier? _parse(String verifier) {
  final parts = verifier.split(r'$');
  if (parts.length != 4 || parts[0] != CredentialKdfPolicy.algorithmTag) {
    return null;
  }
  final iterations = int.tryParse(parts[1]);
  if (iterations == null ||
      iterations < _minAcceptedIterations ||
      iterations > _maxAcceptedIterations) {
    return null;
  }
  final Uint8List salt;
  final Uint8List key;
  try {
    salt = base64Decode(parts[2]);
    key = base64Decode(parts[3]);
  } on FormatException {
    return null;
  }
  // An empty or truncated key would compare equal to an equally short
  // derivation, so such a verifier would accept any PIN. Fail closed.
  if (salt.length < _minAcceptedSaltBytes ||
      key.length < _minAcceptedKeyBytes ||
      key.length > _maxAcceptedKeyBytes) {
    return null;
  }
  return _ParsedVerifier(iterations, salt, key);
}

/// Runs [deriveCredentialVerifier] on a background isolate. The derivation
/// is CPU-bound for a noticeable moment; running it on the UI isolate would
/// freeze the screen (including its progress indicator).
Future<String> deriveCredentialVerifierInBackground(
  String secret, {
  CredentialKdfPolicy policy = CredentialKdfPolicy.current,
}) => Isolate.run(() => deriveCredentialVerifier(secret, policy: policy));

/// Runs [verifyCredential] on a background isolate.
Future<bool> verifyCredentialInBackground(String secret, String verifier) =>
    Isolate.run(() => verifyCredential(secret, verifier));

/// Derives a verifier string for [secret]. Never logs or returns the secret.
String deriveCredentialVerifier(
  String secret, {
  CredentialKdfPolicy policy = CredentialKdfPolicy.current,
}) {
  final salt = secureRandomBytes(policy.saltLengthBytes);
  final derived = _pbkdf2(
    utf8.encode(secret),
    salt,
    policy.iterations,
    policy.derivedKeyLengthBytes,
  );
  return '${CredentialKdfPolicy.algorithmTag}\$${policy.iterations}\$'
      '${base64Encode(salt)}\$${base64Encode(derived)}';
}

/// Verifies [secret] against a stored [verifier]. Returns false (never
/// throws) for a malformed or out-of-bounds verifier.
bool verifyCredential(String secret, String verifier) {
  final parsed = _parse(verifier);
  if (parsed == null) {
    return false;
  }
  final actual = _pbkdf2(
    utf8.encode(secret),
    parsed.salt,
    parsed.iterations,
    parsed.key.length,
  );
  return constantTimeEquals(actual, parsed.key);
}

/// True if [verifier] was made with weaker parameters than [policy] and
/// should be re-derived after the next successful verification. A verifier
/// made with stronger parameters is left alone (no downgrade).
bool verifierNeedsRehash(
  String verifier, {
  CredentialKdfPolicy policy = CredentialKdfPolicy.current,
}) {
  final parsed = _parse(verifier);
  if (parsed == null) {
    return false;
  }
  return parsed.iterations < policy.iterations ||
      parsed.salt.length < policy.saltLengthBytes ||
      parsed.key.length < policy.derivedKeyLengthBytes;
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
