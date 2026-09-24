import 'micro_plan_models.dart';

/// Turns Micro Plan worksheets into classified rows
/// (docs/MICRO_PLAN_FILE_FORMAT_SPEC.md). Stateless and side-effect free:
/// nothing here touches the database. Every rule was first checked against
/// the real 2025-26 workbook.
class MicroPlanParser {
  const MicroPlanParser();

  // 0-based column indexes (A = 0).
  static const int _colSerial = 0; // A
  static const int _colName = 1; // B
  static const int _colType = 2; // C
  static const int _colAwcCode = 3; // D
  static const int _colSchoolCode = 4; // E
  static const int _colSchoolCategory = 5; // F
  static const int _colStandard = 6; // G
  static const int _colMale = 7; // H
  static const int _colFemale = 8; // I
  static const int _colTotal = 9; // J
  static const int _colContactPerson = 10; // K
  static const int _colContactNumber = 11; // L
  static const int _colVisitDate = 12; // M
  static const int _colDay = 13; // N
  static const int _columnCount = 14;

  /// Columns whose vertically merged cells carry down to the rows below
  /// (several institutions visited on the same day share S.No., date, day,
  /// and sometimes the name cell).
  static const Set<int> _carryDownColumns = {
    _colSerial,
    _colName,
    _colVisitDate,
    _colDay,
  };

  static const int _headerSearchLimit = 30;

  static const Map<String, int> _monthNames = {
    'JAN': 1,
    'FEB': 2,
    'MARCH': 3,
    'APRIL': 4,
    'MAY': 5,
    'JUNE': 6,
    'JULY': 7,
    'AUG': 8,
    'SEP': 9,
    'OCT': 10,
    'NOV': 11,
    'DEC': 12,
  };

  static const List<String> _dayNames = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];

  static const String _sundayMarker = 'SUNDAY';
  static const String _treatmentEventMarker = 'PHC REFERRED CHILDREN TREATMENT';

  static final RegExp _whitespaceRun = RegExp(r'\s+');
  static final RegExp _sheetNamePattern = RegExp(r'^([A-Z]+)\s*(\d{2})$');
  static final RegExp _integerText = RegExp(r'^-?\d+$');
  static final RegExp _tenDigits = RegExp(r'^\d{10}$');
  static final RegExp _dateText = RegExp(
    r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})$',
  );
  static final RegExp _financialYear = RegExp(r'(\d{4})\s*-\s*(\d{4})');

  /// Parses every sheet, in workbook order.
  List<ParsedPlanSheet> parseWorkbook(List<MicroPlanSheetInput> sheets) =>
      [for (final sheet in sheets) parseSheet(sheet)];

  ParsedPlanSheet parseSheet(MicroPlanSheetInput input) {
    final sheetFlags = <MicroPlanSheetFlag>[];
    final monthYear = sheetMonth(input.name);
    if (monthYear == null) {
      sheetFlags.add(MicroPlanSheetFlag.sheetNameNotAMonth);
    }

    final header = _parseHeader(input.rows);
    final headerRowIndex = _findHeaderRow(input.rows);
    if (headerRowIndex == null) {
      sheetFlags.add(MicroPlanSheetFlag.headerRowNotFound);
      return ParsedPlanSheet(
        name: input.name,
        month: monthYear?.month,
        year: monthYear?.year,
        header: header,
        rows: const [],
        sheetFlags: sheetFlags,
      );
    }
    if (!_headerLayoutOk(input.rows[headerRowIndex])) {
      sheetFlags.add(MicroPlanSheetFlag.columnLayoutUnexpected);
      return ParsedPlanSheet(
        name: input.name,
        month: monthYear?.month,
        year: monthYear?.year,
        header: header,
        rows: const [],
        sheetFlags: sheetFlags,
      );
    }

    // The header takes two rows (the second holds Male/Female/Total/Person/
    // Contact No.); data starts right after.
    final firstDataIndex = headerRowIndex + 2;
    final grid = _gridWithCarriedMerges(input, firstDataIndex);

    final rows = <ParsedPlanRow>[];
    for (var i = firstDataIndex; i < grid.cells.length; i++) {
      final cells = grid.cells[i];
      if (cells.every((c) => _text(c) == null)) continue;
      rows.add(
        _parseRow(
          sheetName: input.name,
          rowIndex: i,
          cells: cells,
          nameCarried: grid.carriedNameRows.contains(i),
          monthYear: monthYear,
        ),
      );
    }

    return ParsedPlanSheet(
      name: input.name,
      month: monthYear?.month,
      year: monthYear?.year,
      header: header,
      rows: rows,
      sheetFlags: sheetFlags,
    );
  }

  /// "APRIL25" → (4, 2025); "JAN 26" → (1, 2026); anything else → null.
  static ({int month, int year})? sheetMonth(String sheetName) {
    final match = _sheetNamePattern.firstMatch(
      sheetName.trim().toUpperCase(),
    );
    if (match == null) return null;
    final month = _monthNames[match.group(1)];
    if (month == null) return null;
    return (month: month, year: 2000 + int.parse(match.group(2)!));
  }

  // ---------------------------------------------------------------------------
  // Row rules
  // ---------------------------------------------------------------------------

  ParsedPlanRow _parseRow({
    required String sheetName,
    required int rowIndex,
    required List<Object?> cells,
    required bool nameCarried,
    required ({int month, int year})? monthYear,
  }) {
    final flags = <MicroPlanFlag>[];
    void flag(MicroPlanFlag f) {
      if (!flags.contains(f)) flags.add(f);
    }

    final name = _text(cells[_colName]);
    final type = _text(cells[_colType])?.toUpperCase();
    final nameUpper = name?.toUpperCase();

    final MicroPlanRowKind kind;
    if (type == 'SCHOOL') {
      kind = MicroPlanRowKind.school;
    } else if (type == 'AWC') {
      kind = MicroPlanRowKind.awc;
    } else if (type != null) {
      kind = MicroPlanRowKind.other;
      flag(MicroPlanFlag.unknownInstitutionType);
    } else if (nameUpper == _sundayMarker) {
      kind = MicroPlanRowKind.sunday;
    } else if (nameUpper == _treatmentEventMarker) {
      kind = MicroPlanRowKind.event;
    } else if (name != null) {
      kind = MicroPlanRowKind.holiday;
    } else {
      kind = MicroPlanRowKind.other;
      flag(MicroPlanFlag.unrecognisedRow);
    }

    final dayName = _text(cells[_colDay]);
    final visitDate = monthYear == null
        ? null
        : _resolveDate(
            cells[_colVisitDate],
            monthYear.month,
            monthYear.year,
            dayName,
            flag,
          );
    if (visitDate == null &&
        kind != MicroPlanRowKind.other &&
        !flags.contains(MicroPlanFlag.dateUnreadable) &&
        !flags.contains(MicroPlanFlag.dateOutsideSheetMonth)) {
      flag(MicroPlanFlag.dateMissing);
    }

    final isInstitution =
        kind == MicroPlanRowKind.school || kind == MicroPlanRowKind.awc;
    final male = _int(cells[_colMale]);
    final female = _int(cells[_colFemale]);
    final total = _int(cells[_colTotal]);
    final contactNumber = _text(cells[_colContactNumber]);
    final schoolCode = _text(cells[_colSchoolCode]);
    final awcCode = _text(cells[_colAwcCode]);

    if (isInstitution) {
      if (name == null) flag(MicroPlanFlag.nameMissing);
      if (nameCarried) flag(MicroPlanFlag.nameSharedWithRowAbove);
      if (male == null || female == null || total == null) {
        flag(MicroPlanFlag.countMissing);
      } else if (male + female != total) {
        flag(MicroPlanFlag.countTotalMismatch);
      }
      if (contactNumber != null && !_tenDigits.hasMatch(contactNumber)) {
        flag(MicroPlanFlag.contactNumberNot10Digits);
      }
      if (kind == MicroPlanRowKind.school) {
        if (schoolCode == null) {
          flag(MicroPlanFlag.schoolCodeMissing);
        } else if (!_tenDigits.hasMatch(schoolCode)) {
          flag(MicroPlanFlag.schoolCodeUnusual);
        }
      } else if (awcCode == null) {
        flag(MicroPlanFlag.awcCodeMissing);
      }
    }

    return ParsedPlanRow(
      sheetName: sheetName,
      sourceRow: rowIndex + 1,
      kind: kind,
      flags: List.unmodifiable(flags),
      serialNo: _int(cells[_colSerial]),
      name: name,
      awcCode: isInstitution ? awcCode : null,
      schoolCode: isInstitution ? schoolCode : null,
      schoolCategory: isInstitution ? _text(cells[_colSchoolCategory]) : null,
      standardCategory: isInstitution ? _text(cells[_colStandard]) : null,
      maleCount: isInstitution ? male : null,
      femaleCount: isInstitution ? female : null,
      totalCount: isInstitution ? total : null,
      contactPerson: isInstitution ? _text(cells[_colContactPerson]) : null,
      contactNumber: isInstitution ? contactNumber : null,
      visitDate: visitDate,
      dayName: dayName,
    );
  }

  /// Picks the reading of the visit-date cell that falls in the sheet's
  /// month. Excel stored dates up to the 12th as month/day (day and month
  /// swapped) and left later dates as "D/M/YYYY" text; both are handled.
  DateTime? _resolveDate(
    Object? raw,
    int month,
    int year,
    String? dayName,
    void Function(MicroPlanFlag) flag,
  ) {
    final candidates = <DateTime>[];
    DateTime? asStored;
    if (raw is DateTime) {
      asStored = _validDate(raw.year, raw.month, raw.day);
      final swapped = _validDate(raw.year, raw.day, raw.month);
      if (asStored != null) candidates.add(asStored);
      if (swapped != null) candidates.add(swapped);
    } else if (raw != null) {
      final text = _text(raw);
      if (text == null) return null;
      final match = _dateText.firstMatch(text);
      if (match == null) {
        flag(MicroPlanFlag.dateUnreadable);
        return null;
      }
      final parsed = _validDate(
        int.parse(match.group(3)!),
        int.parse(match.group(2)!),
        int.parse(match.group(1)!),
      );
      if (parsed != null) candidates.add(parsed);
    } else {
      return null;
    }

    final inMonth = candidates
        .where((d) => d.month == month && d.year == year)
        .toList();
    if (inMonth.isEmpty) {
      flag(MicroPlanFlag.dateOutsideSheetMonth);
      return null;
    }
    final date = inMonth.first;
    if (asStored != null && asStored != date) {
      flag(MicroPlanFlag.dateDayMonthSwapped);
    }
    final day = dayName?.toUpperCase();
    if (day != null &&
        _dayNames.contains(day) &&
        _dayNames[date.weekday - 1] != day) {
      flag(MicroPlanFlag.dayNameMismatch);
    }
    return date;
  }

  /// A real calendar date, or null (DateTime.utc would silently roll
  /// 31/2 over into March).
  static DateTime? _validDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final d = DateTime.utc(year, month, day);
    return d.year == year && d.month == month && d.day == day ? d : null;
  }

  // ---------------------------------------------------------------------------
  // Sheet structure
  // ---------------------------------------------------------------------------

  int? _findHeaderRow(List<List<Object?>> rows) {
    final limit = rows.length < _headerSearchLimit
        ? rows.length
        : _headerSearchLimit;
    for (var i = 0; i < limit; i++) {
      final first = _text(_cellAt(rows[i], _colSerial))?.toUpperCase();
      if (first != null && first.startsWith('S.NO')) return i;
    }
    return null;
  }

  bool _headerLayoutOk(List<Object?> headerRow) {
    String label(int col) =>
        (_text(_cellAt(headerRow, col)) ?? '').toUpperCase();
    return label(_colName).startsWith('NAME OF INSTITUTION') &&
        label(_colAwcCode).contains('ANGANWADI CODE') &&
        label(_colSchoolCode).contains('SCHOOL CODE') &&
        label(_colVisitDate).contains('VISIT DATE') &&
        label(_colDay).startsWith('DAY');
  }

  /// Location details above the table: each label's value is the next
  /// non-blank cell to its right on the same row.
  MicroPlanHeader _parseHeader(List<List<Object?>> rows) {
    String? financialYear;
    String? district;
    String? block;
    String? panchayat;
    String? team;
    final limit = rows.length < _headerSearchLimit
        ? rows.length
        : _headerSearchLimit;
    rowLoop:
    for (var r = 0; r < limit; r++) {
      final row = rows[r];
      for (var c = 0; c < row.length; c++) {
        final text = _text(row[c]);
        if (text == null) continue;
        final upper = text.toUpperCase();
        // The table header ends the location block.
        if (upper.startsWith('S.NO')) break rowLoop;
        if (financialYear == null && upper.contains('PLAN OF')) {
          final m = _financialYear.firstMatch(text);
          if (m != null) financialYear = '${m.group(1)}-${m.group(2)}';
        } else if (upper.startsWith('DISTRICT')) {
          district ??= _valueRightOf(row, c);
        } else if (upper.startsWith('BLOCK')) {
          block ??= _valueRightOf(row, c);
        } else if (upper.startsWith('PANCHAYAT')) {
          panchayat ??= _valueRightOf(row, c);
        } else if (upper.startsWith('DEDICATED TEAM')) {
          team ??= _valueRightOf(row, c);
        }
      }
    }
    return MicroPlanHeader(
      financialYearLabel: financialYear,
      district: district,
      block: block,
      panchayatVillage: panchayat,
      teamUid: team,
    );
  }

  String? _valueRightOf(List<Object?> row, int col) {
    for (var c = col + 1; c < row.length; c++) {
      final text = _text(row[c]);
      if (text != null) return text;
    }
    return null;
  }

  /// A copy of the data area, padded to 14 columns, where each single-column
  /// vertical merge in a carry-down column has its top value copied into the
  /// rows below. Also reports which rows got their name that way.
  ({List<List<Object?>> cells, Set<int> carriedNameRows}) _gridWithCarriedMerges(
    MicroPlanSheetInput input,
    int firstDataIndex,
  ) {
    final cells = [
      for (final row in input.rows)
        [for (var c = 0; c < _columnCount; c++) _cellAt(row, c)],
    ];
    final carriedNameRows = <int>{};
    for (final merge in input.merges) {
      if (merge.firstColumn != merge.lastColumn) continue;
      final col = merge.firstColumn - 1;
      if (!_carryDownColumns.contains(col)) continue;
      final top = merge.firstRow - 1;
      if (top < 0 || top >= cells.length) continue;
      final value = cells[top][col];
      for (var r = merge.firstRow; r < merge.lastRow; r++) {
        if (r < firstDataIndex || r >= cells.length) continue;
        cells[r][col] = value;
        if (col == _colName) carriedNameRows.add(r);
      }
    }
    return (cells: cells, carriedNameRows: carriedNameRows);
  }

  // ---------------------------------------------------------------------------
  // Cell helpers
  // ---------------------------------------------------------------------------

  static Object? _cellAt(List<Object?> row, int col) =>
      col < row.length ? row[col] : null;

  /// Trimmed text with whitespace runs (including line breaks) collapsed;
  /// blank → null. Whole-number doubles print without ".0" so codes and
  /// phone numbers stored as numbers keep their digits.
  static String? _text(Object? value) {
    if (value == null) return null;
    final String raw;
    if (value is double && value == value.truncateToDouble()) {
      raw = value.toInt().toString();
    } else if (value is DateTime) {
      raw = value.toIso8601String();
    } else {
      raw = value.toString();
    }
    final text = raw.trim().replaceAll(_whitespaceRun, ' ');
    return text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value == null || value is bool) return null;
    if (value is int) return value;
    if (value is double) {
      return value == value.truncateToDouble() ? value.toInt() : null;
    }
    final text = _text(value);
    if (text == null || !_integerText.hasMatch(text)) return null;
    return int.tryParse(text);
  }
}
