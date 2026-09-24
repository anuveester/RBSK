import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/security/secret_code.dart';

final _formatted = RegExp(
  r'^(AR|BK)-[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){5}-[0-9A-HJKMNP-TV-Z]{3}$',
);

SecretCodeProblem? _problem(String input, SecretCodeKind kind) {
  try {
    SecretCode.parse(input, kind);
    return null;
  } on SecretCodeFormatException catch (e) {
    return e.problem;
  }
}

void main() {
  test('carries 128 bits from the secure generator, all distinct', () {
    final codes = List.generate(
      1000,
      (_) => SecretCode.generate(SecretCodeKind.adminRecovery),
    );
    expect(codes.every((c) => c.bytes.length == 16), isTrue);
    expect(codes.map((c) => c.canonical).toSet(), hasLength(1000));
  });

  test('formats as the documented grouped, prefixed code', () {
    for (final kind in SecretCodeKind.values) {
      final code = SecretCode.generate(kind);
      expect(code.formatted, matches(_formatted));
      expect(code.formatted, startsWith('${kind.prefix}-'));
      expect(code.canonical, hasLength(27));
    }
  });

  test('parses back exactly, tolerating how people type it', () {
    final code = SecretCode.generate(SecretCodeKind.adminRecovery);
    final variants = [
      code.formatted,
      code.formatted.toLowerCase(),
      code.canonical,
      code.formatted.replaceAll('-', ' '),
      code.canonical.replaceAll('0', 'O').replaceAll('1', 'I'),
      code.canonical.replaceAll('1', 'L'),
    ];
    for (final v in variants) {
      expect(
        SecretCode.parse(v, SecretCodeKind.adminRecovery).bytes,
        code.bytes,
        reason: 'variant $v',
      );
    }
  });

  test('a code of the other kind is reported as the wrong kind', () {
    final backup = SecretCode.generate(SecretCodeKind.backupRecovery);
    expect(
      _problem(backup.formatted, SecretCodeKind.adminRecovery),
      SecretCodeProblem.wrongKind,
    );
    expect(
      _problem(backup.canonical, SecretCodeKind.adminRecovery),
      SecretCodeProblem.wrongKind,
    );
  });

  test('single-character typos are caught by the check character '
      '(about 31 in 32)', () {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    var caught = 0;
    const trials = 300;
    for (var i = 0; i < trials; i++) {
      final code = SecretCode.generate(SecretCodeKind.adminRecovery);
      final chars = code.canonical.split('');
      final pos = i % 26;
      chars[pos] = alphabet[(alphabet.indexOf(chars[pos]) + 1 + i % 31) % 32];
      final problem = _problem(chars.join(), SecretCodeKind.adminRecovery);
      if (problem == SecretCodeProblem.checkFailed ||
          problem == SecretCodeProblem.invalidFormat) {
        caught++;
      }
    }
    expect(caught, greaterThan(trials * 0.9));
  });

  test('malformed input is rejected', () {
    final code = SecretCode.generate(SecretCodeKind.backupRecovery);
    for (final bad in [
      '',
      'BK-',
      code.canonical.substring(1),
      '${code.canonical}X',
      code.canonical.replaceRange(0, 1, 'U'),
      'XY${code.canonical}',
    ]) {
      expect(
        _problem(bad, SecretCodeKind.backupRecovery),
        isNotNull,
        reason: bad,
      );
    }
  });

  test('toString never contains the code', () {
    final code = SecretCode.generate(SecretCodeKind.adminRecovery);
    expect(code.toString(), isNot(contains(code.canonical)));
    expect(code.toString(), contains('redacted'));
  });
}
