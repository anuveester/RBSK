import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/utils/text_normalize.dart';

void main() {
  group('normalizeForMatch', () {
    test('trims leading and trailing whitespace', () {
      expect(normalizeForMatch('  Test School  '), 'test school');
    });

    test('collapses repeated inner whitespace, including tabs and new lines',
        () {
      expect(normalizeForMatch('Test   School\t\tOne\nTwo'), 'test school one two');
    });

    test('ignores case', () {
      expect(normalizeForMatch('TEST School'), normalizeForMatch('test school'));
    });

    test('does no fuzzy matching: spelling and punctuation stay', () {
      expect(normalizeForMatch('Lagaun'), isNot(normalizeForMatch('Lagon')));
      expect(normalizeForMatch('Test-School'), isNot(normalizeForMatch('Test School')));
    });

    test('null and blank are both empty, so blank matches blank', () {
      expect(normalizeForMatch(null), '');
      expect(normalizeForMatch('   '), '');
    });
  });

  group('blankToNull', () {
    test('keeps the text as entered apart from surrounding whitespace', () {
      expect(blankToNull('  SYN-0001 '), 'SYN-0001');
      expect(blankToNull('Mixed  Case'), 'Mixed  Case');
    });

    test('blank stays blank (null)', () {
      expect(blankToNull(null), isNull);
      expect(blankToNull(''), isNull);
      expect(blankToNull('   '), isNull);
    });
  });
}
