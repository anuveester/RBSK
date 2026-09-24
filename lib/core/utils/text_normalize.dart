/// Text rules for School/AWC master data (docs/35_PHASE_1_5_PLAN.md §7).
library;

final RegExp _whitespaceRun = RegExp(r'\s+');

/// The value compared when looking for possible duplicates: surrounding
/// whitespace removed, inner runs of whitespace collapsed to one space,
/// case ignored. Nothing else — no fuzzy, phonetic or punctuation matching.
/// Null and blank both become the empty string, so blank matches blank.
String normalizeForMatch(String? value) =>
    (value ?? '').trim().replaceAll(_whitespaceRun, ' ').toLowerCase();

/// What is stored for an optional text field: surrounding whitespace
/// removed, otherwise exactly as entered. Blank becomes null — a blank
/// official code stays blank and is never invented.
String? blankToNull(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
