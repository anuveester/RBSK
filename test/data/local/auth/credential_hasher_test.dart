import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/auth/credential_hasher.dart';

// Synthetic test PINs only — never a real credential.
const _pin = '482913';
const _otherPin = '482914';

void main() {
  group('deriveCredentialVerifier', () {
    test('produces the documented self-describing format', () {
      final verifier = deriveCredentialVerifier(_pin);
      final parts = verifier.split(r'$');

      expect(parts, hasLength(4));
      expect(parts[0], 'pbkdf2-hmac-sha256');
      expect(parts[1], '210000');
      expect(base64Decode(parts[2]), hasLength(16), reason: '128-bit salt');
      expect(base64Decode(parts[3]), hasLength(32), reason: '256-bit key');
    });

    test(
      'uses a fresh salt per credential — same PIN, different verifiers',
      () {
        final a = deriveCredentialVerifier(_pin);
        final b = deriveCredentialVerifier(_pin);

        expect(a, isNot(b));
        expect(a.split(r'$')[2], isNot(b.split(r'$')[2]));
      },
    );

    test('verifier never contains the raw PIN in any obvious encoding', () {
      final verifier = deriveCredentialVerifier(_pin);

      expect(verifier, isNot(contains(_pin)));
      expect(verifier, isNot(contains(base64Encode(utf8.encode(_pin)))));
      expect(
        verifier,
        isNot(contains(base64Encode(utf8.encode(_pin)).replaceAll('=', ''))),
      );
    });
  });

  group('verifyCredential', () {
    late String verifier;

    setUpAll(() {
      verifier = deriveCredentialVerifier(_pin);
    });

    test('accepts the correct PIN', () {
      expect(verifyCredential(_pin, verifier), isTrue);
    });

    test('rejects an incorrect PIN, including a one-digit difference', () {
      expect(verifyCredential(_otherPin, verifier), isFalse);
      expect(verifyCredential('000000', verifier), isFalse);
      expect(verifyCredential('', verifier), isFalse);
    });

    test('fails closed on malformed or tampered verifiers', () {
      final parts = verifier.split(r'$');
      final wrongTag = ['sha256', ...parts.skip(1)].join(r'$');
      final badIterations = [parts[0], 'abc', parts[2], parts[3]].join(r'$');
      final zeroIterations = [parts[0], '0', parts[2], parts[3]].join(r'$');
      final badBase64 = [parts[0], parts[1], '!!!', parts[3]].join(r'$');

      for (final bad in [
        '',
        'garbage',
        wrongTag,
        badIterations,
        zeroIterations,
        badBase64,
      ]) {
        expect(verifyCredential(_pin, bad), isFalse, reason: bad);
      }
    });

    test('a verifier with an empty or truncated key accepts no PIN', () {
      // Regression: an empty key once compared equal to an empty
      // derivation, so this shape accepted any PIN.
      final parts = verifier.split(r'$');
      final emptyKey = [parts[0], parts[1], parts[2], ''].join(r'$');
      final shortKey = [
        parts[0],
        parts[1],
        parts[2],
        base64Encode(base64Decode(parts[3]).sublist(0, 16)),
      ].join(r'$');

      for (final bad in [emptyKey, shortKey]) {
        expect(verifyCredential(_pin, bad), isFalse, reason: bad);
        expect(verifyCredential(_otherPin, bad), isFalse, reason: bad);
      }
    });

    test('honours the iteration count embedded in the verifier', () {
      // A verifier created with a different iteration count must still
      // verify — this is what lets the count be raised later without
      // invalidating existing verifiers. Changing the embedded count on an
      // existing verifier must make it fail.
      final parts = verifier.split(r'$');
      final tampered = [parts[0], '1000', parts[2], parts[3]].join(r'$');

      expect(verifyCredential(_pin, tampered), isFalse);
    });
  });

  group('background isolate wrappers', () {
    test(
      'derive and verify give the same results off the UI isolate',
      () async {
        final verifier = await deriveCredentialVerifierInBackground(_pin);

        expect(await verifyCredentialInBackground(_pin, verifier), isTrue);
        expect(
          await verifyCredentialInBackground(_otherPin, verifier),
          isFalse,
        );
      },
    );
  });
}
