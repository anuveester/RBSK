/// What a Micro Plan import would do, shown to the Medical Officer before
/// anything is written (docs/01_PRD.md FR-2.3). Pure Dart: no database.
///
/// Matching rules [USER-DECIDED 2026-09-25]:
/// 1. Rows whose name AND code are the same (ignoring case and extra spaces)
///    are one institution — no question asked.
/// 2. Anything merely similar becomes a [MergeSuggestion]; the MO answers
///    yes or no. Nothing is ever merged without a yes.
/// 3. Schools with the same name but a different category (PS vs UPS) are
///    different schools and are not suggested.
/// 4. Rows without a code get their own record, flagged for review.
/// All stored text is in CAPITAL letters [USER-DECIDED 2026-09-25].
library;

import 'micro_plan_models.dart';

/// Where a row came from in the workbook.
class SourceRef {
  const SourceRef(this.sheetName, this.row);

  final String sheetName;
  final int row;

  @override
  String toString() => '$sheetName row $row';

  @override
  bool operator ==(Object other) =>
      other is SourceRef && other.sheetName == sheetName && other.row == row;

  @override
  int get hashCode => Object.hash(sheetName, row);
}

/// A school or AWC already in the master, as the import sees it.
class ExistingInstitution {
  const ExistingInstitution({
    required this.id,
    required this.kind,
    required this.name,
    this.code,
    this.category,
  });

  final String id;

  /// [MicroPlanRowKind.school] or [MicroPlanRowKind.awc].
  final MicroPlanRowKind kind;
  final String name;

  /// School: `official_school_code`. AWC: `source_plan_awc_code`.
  final String? code;

  /// Schools only: PS / UPS / COM.
  final String? category;
}

/// One distinct institution found in the file (rule 1 already applied), or
/// an existing master record that a suggestion points at.
class ImportCandidate {
  const ImportCandidate({
    required this.key,
    required this.kind,
    required this.name,
    required this.sources,
    this.code,
    this.category,
    this.district,
    this.block,
    this.existingId,
  });

  /// Stable id within one preview. File candidates: `SCHOOL|NAME|CODE`;
  /// existing records: `EXISTING|<id>`.
  final String key;
  final MicroPlanRowKind kind;

  /// CAPITAL letters, spaces collapsed.
  final String name;
  final String? code;
  final String? category;
  final String? district;
  final String? block;

  /// Set when this candidate IS an existing master record, or when a file
  /// candidate matched one exactly under rule 1.
  final String? existingId;

  /// Rows of the file that name this candidate (empty for a bare existing
  /// record).
  final List<SourceRef> sources;

  bool get isExistingRecord => key.startsWith('EXISTING|');
}

enum MergeReason {
  /// School: same code, different name (e.g. LAGON / LAGAUN).
  schoolSameCode(
    'Same school code, different name',
  ),

  /// School: same name and category, different code.
  schoolSameNameAndCategory(
    'Same name and category, different school code',
  ),

  /// AWC: same code and one name is part of the other
  /// (e.g. JAKHAURA-1 / JAKHAURA-1+2).
  awcSameCodeOverlappingName(
    'Same AWC code, one name is part of the other',
  ),

  /// AWC: same name (not a combined "1+2" name), different code.
  awcSameNameDifferentCode(
    'Same AWC name, different code',
  );

  const MergeReason(this.description);

  final String description;
}

/// "Are these two the same institution?" — answered yes/no by the MO.
class MergeSuggestion {
  const MergeSuggestion({
    required this.id,
    required this.firstKey,
    required this.secondKey,
    required this.reason,
  });

  /// Stable within one preview: `S1`, `S2`, …
  final String id;
  final String firstKey;
  final String secondKey;
  final MergeReason reason;
}

/// One planned visit: a school/AWC row with a date.
class PlannedVisitDraft {
  const PlannedVisitDraft({
    required this.candidateKey,
    required this.source,
    required this.plannedDate,
    this.maleCount,
    this.femaleCount,
    this.totalCount,
    this.contactPerson,
    this.contactNumber,
    this.dataQualityNotes,
  });

  final String candidateKey;
  final SourceRef source;
  final DateTime plannedDate;
  final int? maleCount;
  final int? femaleCount;
  final int? totalCount;

  /// CAPITAL letters.
  final String? contactPerson;
  final String? contactNumber;
  final String? dataQualityNotes;
}

/// One holiday row with a date.
class PlannedHolidayDraft {
  const PlannedHolidayDraft({
    required this.date,
    required this.name,
    required this.source,
  });

  final DateTime date;

  /// CAPITAL letters.
  final String name;
  final SourceRef source;
}

/// Why a row cannot be imported as it stands.
enum AttentionReason {
  institutionWithoutDate('School/AWC row has no usable visit date'),
  institutionWithoutName('School/AWC row has no name'),
  holidayWithoutDate('Holiday row has no usable date'),
  unrecognisedRow('Row is not a school, AWC, holiday, Sunday or treatment day');

  const AttentionReason(this.description);

  final String description;
}

class AttentionRow {
  const AttentionRow(this.row, this.reason);

  final ParsedPlanRow row;
  final AttentionReason reason;
}

/// Everything the MO reviews before saying "Import".
class MicroPlanImportPreview {
  const MicroPlanImportPreview({
    required this.candidates,
    required this.suggestions,
    required this.visits,
    required this.holidays,
    required this.attentionRows,
    required this.sheetProblems,
    required this.skippedSundays,
    required this.skippedTreatmentDays,
    this.existingSchoolCodes = const {},
    this.financialYearLabel,
  });

  /// File candidates first (in order of first appearance), then any existing
  /// master records that suggestions point at.
  final List<ImportCandidate> candidates;
  final List<MergeSuggestion> suggestions;
  final List<PlannedVisitDraft> visits;
  final List<PlannedHolidayDraft> holidays;
  final List<AttentionRow> attentionRows;

  /// Sheet name → problems. A sheet listed here contributed no rows.
  final Map<String, List<MicroPlanSheetFlag>> sheetProblems;
  final int skippedSundays;
  final int skippedTreatmentDays;

  /// School codes already in the master (code → school name). A new school
  /// never takes a code that is already in use (unique index); it is left
  /// blank with a note instead.
  final Map<String, String> existingSchoolCodes;
  final String? financialYearLabel;

  ImportCandidate candidate(String key) =>
      candidates.firstWhere((c) => c.key == key);

  Iterable<ImportCandidate> get fileCandidates =>
      candidates.where((c) => !c.isExistingRecord);
}

/// The final institution after the MO's answers: several candidates that
/// were confirmed as the same become one.
class ResolvedInstitution {
  const ResolvedInstitution({
    required this.kind,
    required this.candidateKeys,
    required this.name,
    required this.sources,
    this.existingId,
    this.code,
    this.category,
    this.district,
    this.block,
    this.dataQualityNotes,
  });

  final MicroPlanRowKind kind;

  /// Every candidate folded into this institution.
  final List<String> candidateKeys;

  /// Use this existing master record instead of creating a new one.
  final String? existingId;
  final String name;
  final String? code;
  final String? category;
  final String? district;
  final String? block;
  final List<SourceRef> sources;
  final String? dataQualityNotes;

  bool get isNew => existingId == null;
}

/// The preview with every suggestion answered: ready for the database step.
class MicroPlanImportPlan {
  const MicroPlanImportPlan({
    required this.institutions,
    required this.institutionIndexByCandidate,
    required this.visits,
    required this.holidays,
    this.financialYearLabel,
  });

  final List<ResolvedInstitution> institutions;

  /// Candidate key → index into [institutions].
  final Map<String, int> institutionIndexByCandidate;
  final List<PlannedVisitDraft> visits;
  final List<PlannedHolidayDraft> holidays;
  final String? financialYearLabel;

  ResolvedInstitution institutionFor(PlannedVisitDraft visit) =>
      institutions[institutionIndexByCandidate[visit.candidateKey]!];
}

/// Thrown by `resolve` when the answers cannot be applied as given.
class ImportDecisionException implements Exception {
  const ImportDecisionException(this.message, this.suggestionIds);

  final String message;
  final List<String> suggestionIds;

  @override
  String toString() =>
      'ImportDecisionException: $message (${suggestionIds.join(', ')})';
}
