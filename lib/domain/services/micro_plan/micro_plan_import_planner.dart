import 'micro_plan_import_preview.dart';
import 'micro_plan_models.dart';

/// Turns parsed Micro Plan sheets into a [MicroPlanImportPreview] and, once
/// the Medical Officer has answered every [MergeSuggestion], into a
/// [MicroPlanImportPlan]. Pure Dart, no database; see the matching rules at
/// the top of micro_plan_import_preview.dart.
class MicroPlanImportPlanner {
  const MicroPlanImportPlanner();

  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// "JAKHAURA-1+2" → base "JAKHAURA", numbers {1, 2}.
  static final RegExp _numberedName = RegExp(r'^(.*?)[\s-]*(\d+(?:\s*\+\s*\d+)*)$');
  static final RegExp _digits = RegExp(r'\d+');
  static final RegExp _edgeDashesAndSpaces = RegExp(r'^[\s-]+|[\s-]+$');

  // ---------------------------------------------------------------------------
  // Preview
  // ---------------------------------------------------------------------------

  MicroPlanImportPreview buildPreview(
    List<ParsedPlanSheet> sheets, {
    List<ExistingInstitution> existing = const [],
  }) {
    final builders = <String, _CandidateBuilder>{};
    final visits = <PlannedVisitDraft>[];
    final holidays = <PlannedHolidayDraft>[];
    final attention = <AttentionRow>[];
    final sheetProblems = <String, List<MicroPlanSheetFlag>>{};
    var sundays = 0;
    var treatmentDays = 0;
    String? financialYear;

    for (final sheet in sheets) {
      if (sheet.sheetFlags.isNotEmpty) {
        sheetProblems[sheet.name] = List.unmodifiable(sheet.sheetFlags);
      }
      financialYear ??= sheet.header.financialYearLabel;

      for (final row in sheet.rows) {
        final source = SourceRef(row.sheetName, row.sourceRow);
        switch (row.kind) {
          case MicroPlanRowKind.sunday:
            sundays++;
          case MicroPlanRowKind.event:
            treatmentDays++;
          case MicroPlanRowKind.other:
            attention.add(AttentionRow(row, AttentionReason.unrecognisedRow));
          case MicroPlanRowKind.holiday:
            final holidayDate = row.visitDate;
            if (holidayDate == null) {
              attention.add(
                AttentionRow(row, AttentionReason.holidayWithoutDate),
              );
            } else {
              holidays.add(
                PlannedHolidayDraft(
                  date: holidayDate,
                  name: upperText(row.name)!,
                  source: source,
                ),
              );
            }
          case MicroPlanRowKind.school:
          case MicroPlanRowKind.awc:
            final name = upperText(row.name);
            final visitDate = row.visitDate;
            if (name == null) {
              attention.add(
                AttentionRow(row, AttentionReason.institutionWithoutName),
              );
              continue;
            }
            if (visitDate == null) {
              attention.add(
                AttentionRow(row, AttentionReason.institutionWithoutDate),
              );
              continue;
            }
            final isSchool = row.kind == MicroPlanRowKind.school;
            final code = isSchool ? row.schoolCode : row.awcCode;
            final key = fileKey(row.kind, name, code);
            final builder = builders.putIfAbsent(
              key,
              () => _CandidateBuilder(
                key: key,
                kind: row.kind,
                name: name,
                code: code,
                district: upperText(sheet.header.district),
                block: upperText(sheet.header.block),
              ),
            );
            builder.sources.add(source);
            final category = isSchool ? upperText(row.schoolCategory) : null;
            if (category != null) builder.categories.add(category);
            visits.add(
              PlannedVisitDraft(
                candidateKey: key,
                source: source,
                plannedDate: visitDate,
                maleCount: row.maleCount,
                femaleCount: row.femaleCount,
                totalCount: row.totalCount,
                contactPerson: upperText(row.contactPerson),
                contactNumber: row.contactNumber,
                dataQualityNotes: row.dataQualityNotes,
              ),
            );
        }
      }
    }

    // Rule 1 against the master: same name and code = that existing record.
    for (final builder in builders.values) {
      for (final record in existing) {
        if (record.kind == builder.kind &&
            _matchText(record.name) == builder.name &&
            _matchText(record.code) == _matchText(builder.code)) {
          builder.existingId = record.id;
          break;
        }
      }
    }

    // Rule 2: suggestions, file × file then file × master.
    final fileBuilders = builders.values.toList();
    final existingBuilders = [
      for (final record in existing)
        _CandidateBuilder.existing(
          record,
          upperText(record.name) ?? '',
          upperText(record.category),
        ),
    ];
    final suggestions = <MergeSuggestion>[];
    final referencedExisting = <String>{};
    void suggest(_CandidateBuilder a, _CandidateBuilder b, MergeReason r) {
      suggestions.add(
        MergeSuggestion(
          id: 'S${suggestions.length + 1}',
          firstKey: a.key,
          secondKey: b.key,
          reason: r,
        ),
      );
    }

    for (var i = 0; i < fileBuilders.length; i++) {
      for (var j = i + 1; j < fileBuilders.length; j++) {
        final reason = _similarity(fileBuilders[i], fileBuilders[j]);
        if (reason != null) suggest(fileBuilders[i], fileBuilders[j], reason);
      }
    }
    for (final a in fileBuilders) {
      for (final b in existingBuilders) {
        if (a.existingId == b.existingId) continue;
        final reason = _similarity(a, b);
        if (reason != null) {
          suggest(a, b, reason);
          referencedExisting.add(b.key);
        }
      }
    }

    final existingSchoolCodes = <String, String>{
      for (final record in existing)
        if (record.kind == MicroPlanRowKind.school &&
            _matchText(record.code).isNotEmpty)
          _matchText(record.code): upperText(record.name) ?? '',
    };

    return MicroPlanImportPreview(
      candidates: List.unmodifiable([
        for (final b in fileBuilders) b.build(),
        for (final b in existingBuilders)
          if (referencedExisting.contains(b.key)) b.build(),
      ]),
      suggestions: List.unmodifiable(suggestions),
      visits: List.unmodifiable(visits),
      holidays: List.unmodifiable(holidays),
      attentionRows: List.unmodifiable(attention),
      sheetProblems: Map.unmodifiable(sheetProblems),
      skippedSundays: sundays,
      skippedTreatmentDays: treatmentDays,
      existingSchoolCodes: Map.unmodifiable(existingSchoolCodes),
      financialYearLabel: financialYear,
    );
  }

  /// Key of a file candidate: kind, name and code (rule 1).
  static String fileKey(MicroPlanRowKind kind, String name, String? code) =>
      '${kind.name.toUpperCase()}|${_matchText(name)}|${_matchText(code)}';

  /// CAPITAL letters, trimmed, inner spaces collapsed; blank → null.
  static String? upperText(String? value) {
    final text = value?.trim().replaceAll(_whitespaceRun, ' ');
    return text == null || text.isEmpty ? null : text.toUpperCase();
  }

  static String _matchText(String? value) => upperText(value) ?? '';

  /// Rule 2 / rule 3. Null means "not similar enough to ask".
  static MergeReason? _similarity(_CandidateBuilder a, _CandidateBuilder b) {
    if (a.kind != b.kind) return null;
    final codeA = _matchText(a.code);
    final codeB = _matchText(b.code);
    final sameCode = codeA.isNotEmpty && codeA == codeB;

    if (a.kind == MicroPlanRowKind.school) {
      if (sameCode) return MergeReason.schoolSameCode;
      if (a.name == b.name &&
          (a.categories.isEmpty ||
              b.categories.isEmpty ||
              a.categories.intersection(b.categories).isNotEmpty)) {
        return MergeReason.schoolSameNameAndCategory;
      }
      return null;
    }

    if (sameCode) {
      final partsA = _nameParts(a.name);
      final partsB = _nameParts(b.name);
      final overlapping = partsA.base == partsB.base &&
          partsA.numbers.intersection(partsB.numbers).isNotEmpty;
      if (overlapping || a.name.contains(b.name) || b.name.contains(a.name)) {
        return MergeReason.awcSameCodeOverlappingName;
      }
    }
    if (a.name == b.name && !a.name.contains('+')) {
      return MergeReason.awcSameNameDifferentCode;
    }
    return null;
  }

  static ({String base, Set<int> numbers}) _nameParts(String name) {
    final match = _numberedName.firstMatch(name);
    if (match == null) return (base: name, numbers: <int>{});
    return (
      base: match.group(1)!.replaceAll(_edgeDashesAndSpaces, ''),
      numbers: {
        for (final m in _digits.allMatches(match.group(2)!))
          int.parse(m.group(0)!),
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Resolve
  // ---------------------------------------------------------------------------

  /// Applies the MO's answers ([decisions]: suggestion id → yes/no).
  /// Every suggestion must be answered; answers that would join two
  /// institutions already in the master are refused.
  MicroPlanImportPlan resolve(
    MicroPlanImportPreview preview,
    Map<String, bool> decisions,
  ) {
    final unanswered = [
      for (final s in preview.suggestions)
        if (!decisions.containsKey(s.id)) s.id,
    ];
    if (unanswered.isNotEmpty) {
      throw ImportDecisionException(
        'Every suggestion needs a yes or no',
        unanswered,
      );
    }

    final parent = <String, String>{
      for (final c in preview.candidates) c.key: c.key,
    };
    String find(String key) {
      var root = key;
      while (parent[root] != root) {
        root = parent[root]!;
      }
      return root;
    }

    final accepted = [
      for (final s in preview.suggestions)
        if (decisions[s.id]!) s,
    ];
    for (final s in accepted) {
      final a = find(s.firstKey);
      final b = find(s.secondKey);
      if (a != b) parent[b] = a;
    }

    // Group candidates, keeping first-appearance order.
    final groups = <String, List<ImportCandidate>>{};
    for (final c in preview.candidates) {
      groups.putIfAbsent(find(c.key), () => []).add(c);
    }

    final institutions = <ResolvedInstitution>[];
    final indexByCandidate = <String, int>{};
    final usedSchoolCodes = Map<String, String>.of(preview.existingSchoolCodes);

    for (final members in groups.values) {
      final fileMembers = [
        for (final m in members)
          if (!m.isExistingRecord) m,
      ];
      if (fileMembers.isEmpty) continue; // an existing record nobody joined

      final existingIds = {
        for (final m in members)
          if (m.existingId != null) m.existingId!,
      };
      if (existingIds.length > 1) {
        final keys = {for (final m in members) m.key};
        throw ImportDecisionException(
          'These answers would join institutions that are already separate '
          'in the master',
          [
            for (final s in accepted)
              if (keys.contains(s.firstKey)) s.id,
          ],
        );
      }

      final existingRecord = members
          .where((m) => m.isExistingRecord)
          .firstOrNull;
      final chosen = existingRecord ?? _preferredName(fileMembers);
      final kind = chosen.kind;
      final notes = <String>[];

      final otherNames = {
        for (final m in members)
          if (m.name != chosen.name) m.name,
      };
      if (otherNames.isNotEmpty) {
        notes.add('Also written as: ${otherNames.join(', ')}');
      }

      String? code = chosen.code ??
          members.map((m) => m.code).whereType<String>().firstOrNull;
      final otherCodes = {
        for (final m in members)
          if (m.code != null && m.code != code) m.code!,
      };
      if (otherCodes.isNotEmpty) {
        notes.add('Other codes in the Micro Plan: ${otherCodes.join(', ')}');
      }
      if (code == null) notes.add('No code in the Micro Plan');

      final existingId = existingIds.firstOrNull;
      if (existingId == null &&
          kind == MicroPlanRowKind.school &&
          code != null) {
        final holder = usedSchoolCodes[code];
        if (holder != null) {
          notes.add(
            'School code $code is already used by $holder; left blank',
          );
          code = null;
        } else {
          usedSchoolCodes[code] = chosen.name;
        }
      }

      final categories = {
        for (final m in members)
          if (m.category != null) m.category!,
      };
      final category = chosen.category ?? categories.firstOrNull;
      if (categories.length > 1) {
        notes.add('Categories in the Micro Plan: ${categories.join(', ')}');
      }

      final index = institutions.length;
      institutions.add(
        ResolvedInstitution(
          kind: kind,
          candidateKeys: [for (final m in members) m.key],
          existingId: existingId,
          name: chosen.name,
          code: code,
          category: kind == MicroPlanRowKind.school ? category : null,
          district: chosen.district ?? fileMembers.first.district,
          block: chosen.block ?? fileMembers.first.block,
          sources: [for (final m in fileMembers) ...m.sources],
          dataQualityNotes: notes.isEmpty ? null : notes.join('; '),
        ),
      );
      for (final m in members) {
        indexByCandidate[m.key] = index;
      }
    }

    return MicroPlanImportPlan(
      institutions: List.unmodifiable(institutions),
      institutionIndexByCandidate: Map.unmodifiable(indexByCandidate),
      visits: preview.visits,
      holidays: preview.holidays,
      financialYearLabel: preview.financialYearLabel,
    );
  }

  /// The name kept when file candidates are joined: a name without "+"
  /// first, then the one used on the most rows, then the earliest.
  static ImportCandidate _preferredName(List<ImportCandidate> members) {
    var best = members.first;
    int rank(ImportCandidate c) => c.name.contains('+') ? 0 : 1;
    for (final m in members.skip(1)) {
      if (rank(m) > rank(best) ||
          (rank(m) == rank(best) && m.sources.length > best.sources.length)) {
        best = m;
      }
    }
    return best;
  }
}

class _CandidateBuilder {
  _CandidateBuilder({
    required this.key,
    required this.kind,
    required this.name,
    this.code,
    this.district,
    this.block,
  });

  _CandidateBuilder.existing(
    ExistingInstitution record,
    this.name,
    String? category,
  ) : key = 'EXISTING|${record.id}',
      kind = record.kind,
      code = MicroPlanImportPlanner.upperText(record.code),
      district = null,
      block = null,
      existingId = record.id {
    if (category != null) categories.add(category);
  }

  final String key;
  final MicroPlanRowKind kind;
  final String name;
  final String? code;
  final String? district;
  final String? block;
  String? existingId;
  final Set<String> categories = {};
  final List<SourceRef> sources = [];

  ImportCandidate build() => ImportCandidate(
    key: key,
    kind: kind,
    name: name,
    code: code,
    category: categories.firstOrNull,
    district: district,
    block: block,
    existingId: existingId,
    sources: List.unmodifiable(sources),
  );
}
