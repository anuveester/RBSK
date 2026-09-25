import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/import/xlsx_micro_plan_reader.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_models.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_parser.dart';

import '../../../fixtures/micro_plan/real_plan_2025_26.dart';
import '../../../fixtures/micro_plan/real_plan_2025_26_expected.dart';

const _reader = XlsxMicroPlanReader();

Uint8List _fixture(String name) =>
    File('test/fixtures/micro_plan/$name').readAsBytesSync();

/// Comparable form of a cell: dates by calendar day only (the fixture holds
/// local DateTimes, the reader returns UTC ones).
Object? _norm(Object? value) => value is DateTime
    ? 'date:${value.year}-${value.month}-${value.day}'
    : value;

List<Object?> _trimmed(List<Object?> row) {
  var end = row.length;
  while (end > 0 && row[end - 1] == null) {
    end--;
  }
  return [for (final v in row.take(end)) _norm(v)];
}

String _describe(ParsedPlanRow row) {
  final date = row.visitDate == null
      ? '-'
      : row.visitDate!.toIso8601String().substring(0, 10);
  final flags = row.flags.map((f) => f.name).toList()..sort();
  return '${row.sheetName}|${row.sourceRow}|${row.kind.name}|$date|'
      '${flags.join(',')}';
}

void main() {
  group('the real 2025-26 workbook (anonymised copy)', () {
    final sheets = _reader.read(
      _fixture('real_plan_2025_26_anonymised.xlsx'),
    );

    test('reads the 12 month sheets in workbook order', () {
      expect(sheets.map((s) => s.name), [
        for (final s in realPlan2025Sheets) s.name,
      ]);
    });

    test('every cell matches the fixture read by openpyxl', () {
      for (var i = 0; i < sheets.length; i++) {
        final ours = sheets[i].rows;
        final expected = realPlan2025Sheets[i].rows;
        final length = ours.length > expected.length
            ? ours.length
            : expected.length;
        for (var r = 0; r < length; r++) {
          expect(
            _trimmed(r < ours.length ? ours[r] : const []),
            _trimmed(r < expected.length ? expected[r] : const []),
            reason: '${sheets[i].name} row ${r + 1}',
          );
        }
      }
    });

    test('merged ranges match the fixture', () {
      String key(MicroPlanMerge m) =>
          '${m.firstRow}:${m.lastRow}:${m.firstColumn}:${m.lastColumn}';
      for (var i = 0; i < sheets.length; i++) {
        final lastRow = realPlan2025Sheets[i].rows.length;
        // The fixture leaves out the staff rows 6-11 and anything below
        // its last row.
        final ours = {
          for (final m in sheets[i].merges)
            if (!(m.firstRow >= 6 && m.firstRow <= 11) &&
                !(m.lastRow >= 6 && m.lastRow <= 11) &&
                m.firstRow <= lastRow)
              key(m),
        };
        expect(
          ours,
          {for (final m in realPlan2025Sheets[i].merges) key(m)},
          reason: sheets[i].name,
        );
      }
    });

    test('file → reader → parser gives exactly the reference rows', () {
      final parsed = const MicroPlanParser().parseWorkbook(sheets);
      expect(
        [
          for (final s in parsed) ...s.rows.map(_describe),
        ],
        realPlan2025ExpectedRows,
      );
    });
  });

  group('edge cases', () {
    final sheet = _reader.read(_fixture('edge_cases.xlsx')).single;

    test('sheet found through its relationship, prefixed namespace', () {
      expect(sheet.name, 'APRIL25');
    });

    test('strings: shared (spaces kept), rich text, inline, booleans', () {
      final row = sheet.rows[0];
      expect(row[0], ' LAGON ');
      expect(row[1], 'JAKHAURA-1+2');
      expect(row[2], 'INLINE & TEXT');
      expect(row[3], true);
      expect(row[4], 9370301901);
      expect(row[5], 2.5);
    });

    test('dates come from the number format; other numbers stay numbers', () {
      final row = sheet.rows[1];
      expect(row[0], DateTime.utc(2025, 1, 4)); // custom d/m/yyyy
      expect(row[1], DateTime.utc(2025, 4, 1, 12)); // built-in 14, half day
      expect((row[2]! as DateTime).day, 13); // ISO date cell
      expect(row[3], 7); // format 165 is not defined as a date
      expect(row[4], 'TUESDAY'); // formula: cached result
    });

    test('cells without r= follow on from the previous cell', () {
      expect(sheet.rows[2], [1, 2, 3]);
    });

    test('a stale value inside a merged range is not shown', () {
      expect(sheet.merges, hasLength(1));
      expect(sheet.merges.single.firstRow, 3);
      expect(sheet.merges.single.lastRow, 4);
      expect(sheet.merges.single.firstColumn, 13);
    });

    test('trailing formatted-but-empty rows are dropped', () {
      expect(sheet.rows, hasLength(3));
    });
  });

  test('a file that is not a workbook is refused in plain words', () {
    expect(
      () => _reader.read(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(
        isA<XlsxReadException>().having(
          (e) => e.message,
          'message',
          'This file is not an Excel .xlsx workbook.',
        ),
      ),
    );
  });
}
