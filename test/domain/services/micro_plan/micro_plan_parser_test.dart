import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_models.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_parser.dart';

import '../../../fixtures/micro_plan/real_plan_2025_26.dart';
import '../../../fixtures/micro_plan/real_plan_2025_26_expected.dart';

const _parser = MicroPlanParser();

/// Same one-line shape as the generated expectations:
/// sheet|row|kind|date|flags (flags sorted).
String _describe(ParsedPlanRow row) {
  final date = row.visitDate == null
      ? '-'
      : row.visitDate!.toIso8601String().substring(0, 10);
  final flags = row.flags.map((f) => f.name).toList()..sort();
  return '${row.sheetName}|${row.sourceRow}|${row.kind.name}|$date|'
      '${flags.join(',')}';
}

/// A small sheet in the real layout: location lines, the two header rows,
/// then [dataRows]. The first data row is Excel row 5.
MicroPlanSheetInput _sheet(
  List<List<Object?>> dataRows, {
  String name = 'APRIL25',
  List<MicroPlanMerge> merges = const [],
  List<Object?>? headerRow,
}) {
  return MicroPlanSheetInput(
    name: name,
    rows: [
      ['MICRO PLAN/ACTION PLAN OF  YEAR 2025-2026'],
      ['District :  ', null, 'laliptur', null, 'Block : ', null, 'jakhura'],
      headerRow ??
          [
            'S.No.',
            'Name of Institution ',
            ' School/        Anganwadi',
            'Anganwadi Code',
            'School Code ',
            'Category of School',
            'Category of Standard',
            'Number of children in institution ',
            null,
            null,
            'School/Anganwadi Contact',
            null,
            'Visit date ',
            'Day',
          ],
      [null, null, null, null, null, null, null, 'Male ', 'Female ', 'Total '],
      ...dataRows,
    ],
    merges: merges,
  );
}

/// A clean school row dated Tuesday 15 April 2025.
List<Object?> _school({
  Object? serial = 1,
  Object? name = 'LAGON',
  Object? type = 'SCHOOL',
  Object? awcCode,
  Object? schoolCode = 9370301901,
  Object? male = 10,
  Object? female = 20,
  Object? total = 30,
  Object? contactPerson = 'TEACHER',
  Object? phone = 9876543210,
  Object? date = const _Default(),
  Object? day = 'TUESDAY',
}) => [
  serial,
  name,
  type,
  awcCode,
  schoolCode,
  'PS',
  '6yTO10y',
  male,
  female,
  total,
  contactPerson,
  phone,
  date is _Default ? DateTime(2025, 4, 15) : date,
  day,
];

class _Default {
  const _Default();
}

/// A SUNDAY / treatment-day / holiday row: text in B, date in M, day in N.
List<Object?> _marker(int serial, String text, Object? date, String day) => [
  serial,
  text,
  ...List<Object?>.filled(10, null),
  date,
  day,
];

ParsedPlanRow _onlyRow(MicroPlanSheetInput sheet) {
  final rows = _parser.parseSheet(sheet).rows;
  expect(rows, hasLength(1));
  return rows.single;
}

void main() {
  group('real 2025-26 workbook', () {
    final sheets = _parser.parseWorkbook(realPlan2025Sheets);
    final allRows = [for (final s in sheets) ...s.rows];

    test('every row matches the reference rules exactly', () {
      expect(allRows.map(_describe).toList(), realPlan2025ExpectedRows);
    });

    test('reads all 12 month sheets with no sheet-level problems', () {
      expect(sheets, hasLength(12));
      expect(sheets.expand((s) => s.sheetFlags), isEmpty);
      expect(
        [for (final s in sheets) '${s.month}/${s.year}'],
        [
          '4/2025',
          '5/2025',
          '6/2025',
          '7/2025',
          '8/2025',
          '9/2025',
          '10/2025',
          '11/2025',
          '12/2025',
          '1/2026',
          '2/2026',
          '3/2026',
        ],
      );
    });

    test('classifies rows: 149 school, 196 AWC, 25 holiday', () {
      int count(MicroPlanRowKind k) => allRows.where((r) => r.kind == k).length;
      expect(count(MicroPlanRowKind.school), 149);
      expect(count(MicroPlanRowKind.awc), 196);
      expect(count(MicroPlanRowKind.sunday), 49);
      expect(count(MicroPlanRowKind.event), 49);
      expect(count(MicroPlanRowKind.holiday), 25);
      expect(count(MicroPlanRowKind.other), 1);
    });

    test('every school/AWC row has a visit date in its sheet month', () {
      for (final sheet in sheets) {
        for (final row in sheet.rows.where((r) => r.isInstitution)) {
          expect(row.visitDate, isNotNull, reason: _describe(row));
          expect(row.visitDate!.month, sheet.month, reason: _describe(row));
          expect(row.visitDate!.year, sheet.year, reason: _describe(row));
        }
      }
    });

    test('keeps header values exactly as written', () {
      final header = sheets.first.header;
      expect(header.financialYearLabel, '2025-2026');
      expect(header.district, 'laliptur');
      expect(header.block, 'jakhura');
      expect(header.panchayatVillage, 'jakhaura');
      expect(header.teamUid, 'Team - B');
    });

    test('APRIL25 row 14 (LAGON) is read field by field', () {
      final row = sheets.first.rows.firstWhere((r) => r.sourceRow == 14);
      expect(row.kind, MicroPlanRowKind.school);
      expect(row.serialNo, 1);
      expect(row.name, 'LAGON');
      expect(row.schoolCode, '9370301901');
      expect(row.awcCode, isNull);
      expect(row.schoolCategory, 'PS');
      expect(row.standardCategory, '6yTO10y');
      expect(row.maleCount, 83);
      expect(row.femaleCount, 130);
      // 83 + 130 is 213, not 255: stored as given and flagged, never fixed.
      expect(row.totalCount, 255);
      expect(row.flags, contains(MicroPlanFlag.countTotalMismatch));
      // Excel stored 1 April as 4 January.
      expect(row.visitDate, DateTime.utc(2025, 4, 1));
      expect(row.flags, contains(MicroPlanFlag.dateDayMonthSwapped));
      expect(row.dayName, 'TUESDAY');
    });

    test('a second institution on the same day shares the merged date', () {
      final april = sheets.first;
      final row16 = april.rows.firstWhere((r) => r.sourceRow == 16);
      expect(row16.name, 'RAIPUR');
      expect(row16.visitDate, DateTime.utc(2025, 4, 2));
    });

    test('MAY25: two AWCs under one merged name cell', () {
      final may = sheets[1];
      final row15 = may.rows.firstWhere((r) => r.sourceRow == 15);
      expect(row15.kind, MicroPlanRowKind.awc);
      expect(row15.name, 'JAKHAURA-1+2');
      expect(row15.awcCode, '2');
      expect(row15.flags, contains(MicroPlanFlag.nameSharedWithRowAbove));
    });

    test('dates after the 12th arrive as text and are read as D/M/YYYY', () {
      final may = sheets[1];
      final row33 = may.rows.firstWhere((r) => r.sourceRow == 33);
      expect(row33.name, 'CHHIPAI');
      expect(row33.visitDate, DateTime.utc(2025, 5, 13));
      expect(row33.flags, isEmpty);
      expect(row33.dataQualityNotes, isNull);
    });

    test('holiday and marker rows carry no institution fields', () {
      for (final row in allRows.where((r) => !r.isInstitution)) {
        expect(row.schoolCode, isNull);
        expect(row.awcCode, isNull);
        expect(row.totalCount, isNull);
        expect(row.contactNumber, isNull);
      }
    });
  });

  group('sheet names', () {
    test('month sheets are recognised, with or without a space', () {
      expect(MicroPlanParser.sheetMonth('APRIL25'), (month: 4, year: 2025));
      expect(MicroPlanParser.sheetMonth('JAN 26'), (month: 1, year: 2026));
      expect(MicroPlanParser.sheetMonth('MARCH 26'), (month: 3, year: 2026));
      expect(MicroPlanParser.sheetMonth(' feb26 '), (month: 2, year: 2026));
    });

    test('anything else is not a month', () {
      expect(MicroPlanParser.sheetMonth('Sheet1'), isNull);
      expect(MicroPlanParser.sheetMonth('SEPT25'), isNull);
      expect(MicroPlanParser.sheetMonth('APRIL'), isNull);
    });

    test('an unrecognised sheet name is flagged and rows lose their dates', () {
      final sheet = _parser.parseSheet(_sheet([_school()], name: 'Sheet1'));
      expect(sheet.sheetFlags, [MicroPlanSheetFlag.sheetNameNotAMonth]);
      expect(sheet.rows.single.visitDate, isNull);
      expect(sheet.rows.single.flags, contains(MicroPlanFlag.dateMissing));
    });
  });

  group('sheet structure', () {
    test('no S.No. header row → no rows, flagged', () {
      final sheet = _parser.parseSheet(
        const MicroPlanSheetInput(
          name: 'APRIL25',
          rows: [
            ['something else'],
            [1, 'LAGON', 'SCHOOL'],
          ],
        ),
      );
      expect(sheet.rows, isEmpty);
      expect(sheet.sheetFlags, [MicroPlanSheetFlag.headerRowNotFound]);
    });

    test('shifted columns → no rows, flagged (never guess positions)', () {
      final sheet = _parser.parseSheet(
        _sheet(
          [_school()],
          headerRow: ['S.No.', 'School Code', 'Name of Institution'],
        ),
      );
      expect(sheet.rows, isEmpty);
      expect(sheet.sheetFlags, [MicroPlanSheetFlag.columnLayoutUnexpected]);
    });

    test('blank rows are skipped; source rows stay 1-based Excel rows', () {
      final sheet = _parser.parseSheet(
        _sheet([
          _school(),
          [null, '  ', null],
          _school(serial: 2, name: 'RAIPUR'),
        ]),
      );
      expect(sheet.rows.map((r) => r.sourceRow), [5, 7]);
    });

    test('only single-column vertical merges carry values down', () {
      final sheet = _parser.parseSheet(
        _sheet(
          [
            _school(),
            _school(serial: null, name: null, date: null, day: null),
          ],
          merges: const [
            MicroPlanMerge(
              firstRow: 5,
              lastRow: 6,
              firstColumn: 2,
              lastColumn: 2,
            ),
            MicroPlanMerge(
              firstRow: 5,
              lastRow: 6,
              firstColumn: 13,
              lastColumn: 14,
            ),
          ],
        ),
      );
      final second = sheet.rows[1];
      expect(second.name, 'LAGON');
      expect(second.flags, contains(MicroPlanFlag.nameSharedWithRowAbove));
      // The M:N merge spans two columns, so it is not carried down.
      expect(second.visitDate, isNull);
      expect(second.flags, contains(MicroPlanFlag.dateMissing));
    });
  });

  group('row kinds', () {
    test('SCHOOL and AWC come from column C, any case', () {
      expect(
        _onlyRow(_sheet([_school(type: 'school')])).kind,
        MicroPlanRowKind.school,
      );
      expect(
        _onlyRow(_sheet([_school(type: 'AWC', awcCode: 3)])).kind,
        MicroPlanRowKind.awc,
      );
    });

    test('an unknown column C value is "other" and flagged', () {
      final row = _onlyRow(_sheet([_school(type: 'PHC')]));
      expect(row.kind, MicroPlanRowKind.other);
      expect(row.flags, contains(MicroPlanFlag.unknownInstitutionType));
    });

    test('SUNDAY, treatment day and holiday rows', () {
      final rows = _parser
          .parseSheet(
            _sheet([
              _marker(1, 'SUNDAY', DateTime(2025, 4, 13), 'SUNDAY'),
              _marker(
                2,
                'PHC REFERRED CHILDREN TREATMENT',
                '19/4/2025',
                'SATURDAY',
              ),
              // Stored by Excel as 4 June = 6 April, a Sunday.
              _marker(3, 'RAMNAVMI', DateTime(2025, 6, 4), 'SUNDAY'),
            ]),
          )
          .rows;
      expect(rows.map((r) => r.kind), [
        MicroPlanRowKind.sunday,
        MicroPlanRowKind.event,
        MicroPlanRowKind.holiday,
      ]);
      expect(rows.map((r) => r.visitDate), [
        DateTime.utc(2025, 4, 13),
        DateTime.utc(2025, 4, 19),
        DateTime.utc(2025, 4, 6),
      ]);
      expect(rows[0].flags, isEmpty);
      expect(rows[2].name, 'RAMNAVMI');
    });

    test('a row with values but no name or type is flagged', () {
      final row = _onlyRow(
        _sheet([
          [null, null, null, null, null, null, null, 6],
        ]),
      );
      expect(row.kind, MicroPlanRowKind.other);
      expect(row.flags, [MicroPlanFlag.unrecognisedRow]);
    });
  });

  group('visit dates', () {
    test('a date already in the sheet month is used as is', () {
      final row = _onlyRow(_sheet([_school()]));
      expect(row.visitDate, DateTime.utc(2025, 4, 15));
      expect(row.flags, isEmpty);
    });

    test('a day/month-swapped date is corrected and flagged', () {
      final row = _onlyRow(
        _sheet([_school(date: DateTime(2025, 3, 4), day: 'THURSDAY')]),
      );
      expect(row.visitDate, DateTime.utc(2025, 4, 3));
      expect(row.flags, [MicroPlanFlag.dateDayMonthSwapped]);
    });

    test('text dates are D/M/YYYY', () {
      final row = _onlyRow(_sheet([_school(date: '15/4/2025')]));
      expect(row.visitDate, DateTime.utc(2025, 4, 15));
      expect(row.flags, isEmpty);
    });

    test('a date outside the sheet month is not guessed', () {
      final row = _onlyRow(_sheet([_school(date: '15/5/2025')]));
      expect(row.visitDate, isNull);
      expect(row.flags, [MicroPlanFlag.dateOutsideSheetMonth]);
    });

    test('unreadable date text is flagged', () {
      final row = _onlyRow(_sheet([_school(date: 'next week')]));
      expect(row.visitDate, isNull);
      expect(row.flags, [MicroPlanFlag.dateUnreadable]);
    });

    test('an impossible text date (31/4) is not rolled into May', () {
      final row = _onlyRow(_sheet([_school(date: '31/4/2025')]));
      expect(row.visitDate, isNull);
      expect(row.flags, [MicroPlanFlag.dateOutsideSheetMonth]);
    });

    test('a Day column that disagrees with the date is flagged', () {
      final row = _onlyRow(_sheet([_school(day: 'FRIDAY')]));
      expect(row.visitDate, DateTime.utc(2025, 4, 15));
      expect(row.flags, [MicroPlanFlag.dayNameMismatch]);
    });

    test('a missing date is flagged', () {
      final row = _onlyRow(_sheet([_school(date: null, day: null)]));
      expect(row.flags, [MicroPlanFlag.dateMissing]);
    });
  });

  group('institution fields', () {
    test('numbers stored as doubles keep their digits', () {
      final row = _onlyRow(
        _sheet([
          _school(
            schoolCode: 9370301901.0,
            male: 10.0,
            female: '20',
            total: 30.0,
            phone: 9876543210.0,
          ),
        ]),
      );
      expect(row.schoolCode, '9370301901');
      expect(row.maleCount, 10);
      expect(row.femaleCount, 20);
      expect(row.totalCount, 30);
      expect(row.contactNumber, '9876543210');
      expect(row.flags, isEmpty);
    });

    test('text is trimmed and line breaks collapsed, nothing else', () {
      final row = _onlyRow(
        _sheet([_school(name: '  laGon  ', contactPerson: 'RAJESH \nSADHAY')]),
      );
      expect(row.name, 'laGon');
      expect(row.contactPerson, 'RAJESH SADHAY');
    });

    test('counts are stored as given and mismatches flagged', () {
      final row = _onlyRow(
        _sheet([_school(male: 83, female: 130, total: 255)]),
      );
      expect(row.totalCount, 255);
      expect(row.flags, [MicroPlanFlag.countTotalMismatch]);
      expect(
        row.dataQualityNotes,
        MicroPlanFlag.countTotalMismatch.description,
      );
    });

    test('a blank count is flagged, not treated as zero', () {
      final row = _onlyRow(
        _sheet([_school(male: null, female: null, total: 0)]),
      );
      expect(row.maleCount, isNull);
      expect(row.totalCount, 0);
      expect(row.flags, [MicroPlanFlag.countMissing]);
    });

    test('contact numbers that are not 10 digits are flagged', () {
      for (final phone in <Object>[95984171464, 991915391, 0]) {
        final row = _onlyRow(_sheet([_school(phone: phone)]));
        expect(row.flags, [MicroPlanFlag.contactNumberNot10Digits]);
      }
    });

    test('school code: blank and non-10-digit are flagged', () {
      expect(
        _onlyRow(_sheet([_school(schoolCode: null)])).flags,
        [MicroPlanFlag.schoolCodeMissing],
      );
      expect(
        _onlyRow(_sheet([_school(schoolCode: 93703310901)])).flags,
        [MicroPlanFlag.schoolCodeUnusual],
      );
    });

    test('AWC code is kept as text; blank is flagged', () {
      final awc = _onlyRow(_sheet([_school(type: 'AWC', awcCode: 22)]));
      expect(awc.awcCode, '22');
      expect(awc.flags, isEmpty);
      final blank = _onlyRow(_sheet([_school(type: 'AWC', schoolCode: null)]));
      expect(blank.flags, [MicroPlanFlag.awcCodeMissing]);
    });

    test('a school/AWC row with no name is flagged', () {
      final row = _onlyRow(_sheet([_school(name: null)]));
      expect(row.flags, [MicroPlanFlag.nameMissing]);
    });
  });
}
