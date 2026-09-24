import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'crypto_utils.dart';

/// Which recovery secret a code is. The prefix is shown to people and is
/// part of the check character, but not of the secret. There is one kind:
/// the Backup Recovery Key, which opens encrypted recovery packages.
enum SecretCodeKind {
  /// Opens encrypted recovery packages (docs/30 R5).
  backupRecovery('BK');

  const SecretCodeKind(this.prefix);

  final String prefix;
}

/// Why typed text is not a usable code. None of these reveal anything about
/// the real code.
enum SecretCodeProblem { invalidFormat, checkFailed }

class SecretCodeFormatException implements Exception {
  const SecretCodeFormatException(this.problem);

  final SecretCodeProblem problem;

  @override
  String toString() => 'SecretCodeFormatException(${problem.name})';
}

/// A 128-bit recovery secret, written for people: Crockford Base32 (no
/// I, L, O or U, so nothing looks alike), 26 data characters plus one check
/// character, in groups of four — e.g. `BK-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXX`.
///
/// The check character is 5 bits of SHA-256 over (kind, secret). It catches
/// most typing mistakes before a key is used, and reveals nothing useful
/// about the secret.
class SecretCode {
  SecretCode._(this.kind, this.bytes);

  /// A new code from `Random.secure()`.
  factory SecretCode.generate(SecretCodeKind kind) =>
      SecretCode._(kind, secureRandomBytes(entropyBytes));

  /// Parses what a person typed. Tolerates lower case, spaces, missing
  /// hyphens, a missing prefix, and the Crockford look-alikes O→0, I/L→1.
  factory SecretCode.parse(String input, SecretCodeKind kind) {
    var text = input.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    const totalChars = _dataChars + 1;
    if (text.length == totalChars + 2) {
      final prefix = text.substring(0, 2);
      if (prefix != kind.prefix) {
        throw const SecretCodeFormatException(SecretCodeProblem.invalidFormat);
      }
      text = text.substring(2);
    }
    if (text.length != totalChars) {
      throw const SecretCodeFormatException(SecretCodeProblem.invalidFormat);
    }
    text = text.replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');
    if (!text.split('').every(_alphabet.contains)) {
      throw const SecretCodeFormatException(SecretCodeProblem.invalidFormat);
    }

    final bytes = _decode(text.substring(0, _dataChars));
    if (bytes == null) {
      throw const SecretCodeFormatException(SecretCodeProblem.invalidFormat);
    }
    if (text[_dataChars] != _checkChar(kind, bytes)) {
      throw const SecretCodeFormatException(SecretCodeProblem.checkFailed);
    }
    return SecretCode._(kind, bytes);
  }

  static const int entropyBytes = 16;
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const int _dataChars = 26;

  final SecretCodeKind kind;

  /// The raw 128-bit secret.
  final Uint8List bytes;

  /// Data plus check characters, no prefix or grouping. The stable text form
  /// used as KDF input.
  String get canonical => _encode(bytes) + _checkChar(kind, bytes);

  /// What is shown to people.
  String get formatted {
    final chars = canonical;
    final groups = <String>[
      for (var i = 0; i < chars.length; i += 4)
        chars.substring(i, i + 4 > chars.length ? chars.length : i + 4),
    ];
    return '${kind.prefix}-${groups.join('-')}';
  }

  /// Deliberately not the code: this object must never end up in logs.
  @override
  String toString() => 'SecretCode(${kind.name}, redacted)';

  static String _encode(Uint8List bytes) {
    var buffer = 0;
    var bits = 0;
    final out = StringBuffer();
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 0x1f]);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) {
      out.write(_alphabet[(buffer << (5 - bits)) & 0x1f]);
    }
    return out.toString();
  }

  /// Null if the trailing padding bits are not zero (not a code this class
  /// produced).
  static Uint8List? _decode(String chars) {
    var buffer = 0;
    var bits = 0;
    final out = <int>[];
    for (final c in chars.split('')) {
      buffer = (buffer << 5) | _alphabet.indexOf(c);
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
      buffer &= (1 << bits) - 1;
    }
    if (out.length != entropyBytes || buffer != 0) {
      return null;
    }
    return Uint8List.fromList(out);
  }

  static String _checkChar(SecretCodeKind kind, Uint8List bytes) {
    final digest = SHA256Digest().process(
      Uint8List.fromList([...utf8.encode('rbsk-code:${kind.prefix}:'), ...bytes]),
    );
    return _alphabet[digest[0] >> 3];
  }
}
