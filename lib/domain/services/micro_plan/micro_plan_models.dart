/// Plain models for reading the annual Micro Plan workbook
/// (docs/MICRO_PLAN_FILE_FORMAT_SPEC.md). Pure Dart: no Flutter, no Drift,
/// no Excel package. The workbook reader (a later step) turns an .xlsx file
/// into [MicroPlanSheetInput]s; the parser turns those into
/// [ParsedPlanSheet]s for the review screen and the import step.
library;

/// One worksheet as a plain grid of cell values.
///
/// `rows[0]` is Excel row 1 and `rows[r][0]` is column A. A cell value is
/// whatever the reader produced: `String`, `int`, `double`, `DateTime`,
/// `bool` or `null`. Rows may be shorter than the widest row.
class MicroPlanSheetInput {
  const MicroPlanSheetInput({
    required this.name,
    required this.rows,
    this.merges = const [],
  });

  final String name;
  final List<List<Object?>> rows;
  final List<MicroPlanMerge> merges;
}

/// A merged cell range, 1-based and inclusive, as Excel shows it
/// (e.g. `M22:M23` is firstRow 22, lastRow 23, firstColumn 13, lastColumn 13).
/// Only the top-left cell of a merged range holds a value.
class MicroPlanMerge {
  const MicroPlanMerge({
    required this.firstRow,
    required this.lastRow,
    required this.firstColumn,
    required this.lastColumn,
  });

  final int firstRow;
  final int lastRow;
  final int firstColumn;
  final int lastColumn;
}

/// What a data row is (docs/01_PRD.md FR-2.1): never treat a non-school/AWC
/// row as a school.
enum MicroPlanRowKind {
  /// Column C says SCHOOL.
  school,

  /// Column C says AWC.
  awc,

  /// A "SUNDAY" marker row.
  sunday,

  /// A named holiday (e.g. RAMNAVMI, DEEPAWALI).
  holiday,

  /// "PHC REFERRED CHILDREN TREATMENT" — Saturday treatment/follow-up day.
  /// Not imported as a visit or a holiday (docs/04 §2.3).
  event,

  /// Anything the rules do not recognise. Always carries a flag.
  other,
}

/// Row-level findings, kept for human review (`data_quality_notes`).
/// The parser never corrects source values silently and never drops a
/// school/AWC row because of a flag.
enum MicroPlanFlag {
  dateDayMonthSwapped(
    'Visit date was stored by Excel with day and month swapped; '
    'corrected using the sheet month',
  ),
  dayNameMismatch('The Day column does not match the visit date'),
  dateMissing('No visit date'),
  dateUnreadable('Visit date text could not be read'),
  dateOutsideSheetMonth('Visit date does not fall in this sheet\'s month'),
  nameMissing('Institution name is blank'),
  nameSharedWithRowAbove(
    'Institution name comes from a merged cell shared with the row above',
  ),
  countMissing('Male, female or total count is blank'),
  countTotalMismatch('Male + female does not equal total'),
  contactNumberNot10Digits('Contact number is not 10 digits'),
  schoolCodeMissing('School code is blank'),
  schoolCodeUnusual('School code is not 10 digits'),
  awcCodeMissing('Anganwadi code is blank'),
  unknownInstitutionType('Column C is neither SCHOOL nor AWC'),
  unrecognisedRow('Row does not match any known row type');

  const MicroPlanFlag(this.description);

  final String description;
}

/// Sheet-level problems. A sheet with [headerRowNotFound] or
/// [columnLayoutUnexpected] yields no rows at all: guessing column positions
/// could put counts or codes in the wrong field.
enum MicroPlanSheetFlag {
  sheetNameNotAMonth('Sheet name is not a month like APRIL25 or JAN 26'),
  headerRowNotFound('No "S.No." header row found'),
  columnLayoutUnexpected('Header columns are not in the expected positions');

  const MicroPlanSheetFlag(this.description);

  final String description;
}

/// Location details from the top of a sheet, exactly as written
/// (including source spelling such as "laliptur").
class MicroPlanHeader {
  const MicroPlanHeader({
    this.financialYearLabel,
    this.district,
    this.block,
    this.panchayatVillage,
    this.teamUid,
  });

  /// e.g. "2025-2026".
  final String? financialYearLabel;
  final String? district;
  final String? block;
  final String? panchayatVillage;
  final String? teamUid;
}

/// One classified data row. Text is trimmed with inner whitespace
/// (including line breaks) collapsed to one space; nothing else is changed.
/// Counts are exactly as given — never reconciled (docs/04 §2.3).
class ParsedPlanRow {
  const ParsedPlanRow({
    required this.sheetName,
    required this.sourceRow,
    required this.kind,
    required this.flags,
    this.serialNo,
    this.name,
    this.awcCode,
    this.schoolCode,
    this.schoolCategory,
    this.standardCategory,
    this.maleCount,
    this.femaleCount,
    this.totalCount,
    this.contactPerson,
    this.contactNumber,
    this.visitDate,
    this.dayName,
  });

  final String sheetName;

  /// 1-based Excel row number, for traceability (`visit_plans.source_row`).
  final int sourceRow;
  final MicroPlanRowKind kind;
  final List<MicroPlanFlag> flags;
  final int? serialNo;

  /// Institution name, or the holiday/marker text for other kinds.
  final String? name;

  /// Column D. For AWCs this is the non-authoritative plan code
  /// (`awcs.source_plan_awc_code`), never an identity.
  final String? awcCode;

  /// Column E, digits as written.
  final String? schoolCode;

  /// Column F as written (e.g. PS, UPS, COM; some sheets put an age band here).
  final String? schoolCategory;

  /// Column G as written (e.g. 6yTO10y, 6MTO6Y).
  final String? standardCategory;
  final int? maleCount;
  final int? femaleCount;
  final int? totalCount;
  final String? contactPerson;
  final String? contactNumber;

  /// Date only, as UTC midnight. Null when missing or unreadable (flagged).
  final DateTime? visitDate;
  final String? dayName;

  bool get isInstitution =>
      kind == MicroPlanRowKind.school || kind == MicroPlanRowKind.awc;

  /// Human-readable notes for `data_quality_notes`; null when clean.
  String? get dataQualityNotes => flags.isEmpty
      ? null
      : flags.map((f) => f.description).join('; ');
}

/// One parsed worksheet.
class ParsedPlanSheet {
  const ParsedPlanSheet({
    required this.name,
    required this.header,
    required this.rows,
    required this.sheetFlags,
    this.month,
    this.year,
  });

  final String name;

  /// Calendar month 1–12 taken from the sheet name; null if unreadable.
  final int? month;
  final int? year;
  final MicroPlanHeader header;
  final List<ParsedPlanRow> rows;
  final List<MicroPlanSheetFlag> sheetFlags;

  Iterable<ParsedPlanRow> ofKind(MicroPlanRowKind kind) =>
      rows.where((r) => r.kind == kind);
}
