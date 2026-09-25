import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_import_planner.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_import_preview.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_models.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_parser.dart';

import '../../../fixtures/micro_plan/real_plan_2025_26.dart';

const _parser = MicroPlanParser();
const _planner = MicroPlanImportPlanner();

/// A parsed sheet built directly (no workbook), for focused rule tests.
ParsedPlanSheet _sheet(List<ParsedPlanRow> rows) => ParsedPlanSheet(
  name: 'APRIL25',
  month: 4,
  year: 2025,
  header: const MicroPlanHeader(
    financialYearLabel: '2025-2026',
    district: 'laliptur',
    block: 'jakhura',
  ),
  rows: rows,
  sheetFlags: const [],
);

var _nextRow = 14;

ParsedPlanRow _school(
  String? name, {
  String? code,
  String? category = 'PS',
  int day = 15,
  String? contactPerson,
}) => ParsedPlanRow(
  sheetName: 'APRIL25',
  sourceRow: _nextRow++,
  kind: MicroPlanRowKind.school,
  flags: const [],
  name: name,
  schoolCode: code,
  schoolCategory: category,
  maleCount: 10,
  femaleCount: 20,
  totalCount: 30,
  contactPerson: contactPerson,
  visitDate: DateTime.utc(2025, 4, day),
);

ParsedPlanRow _awc(String name, {String? code, int day = 15}) => ParsedPlanRow(
  sheetName: 'APRIL25',
  sourceRow: _nextRow++,
  kind: MicroPlanRowKind.awc,
  flags: const [],
  name: name,
  awcCode: code,
  visitDate: DateTime.utc(2025, 4, day),
);

Map<String, bool> _answerAll(MicroPlanImportPreview preview, bool answer) => {
  for (final s in preview.suggestions) s.id: answer,
};

void main() {
  group('real 2025-26 workbook', () {
    final preview = _planner.buildPreview(
      _parser.parseWorkbook(realPlan2025Sheets),
    );

    test('counts match the reference rules', () {
      expect(preview.fileCandidates, hasLength(290));
      expect(
        preview.fileCandidates.where((c) => c.kind == MicroPlanRowKind.school),
        hasLength(143),
      );
      expect(preview.visits, hasLength(345));
      expect(preview.holidays, hasLength(25));
      expect(preview.skippedSundays, 49);
      expect(preview.skippedTreatmentDays, 49);
      expect(preview.attentionRows, hasLength(1));
      expect(preview.sheetProblems, isEmpty);
      expect(preview.financialYearLabel, '2025-2026');
    });

    test('61 suggestions for the MO, by reason', () {
      expect(preview.suggestions, hasLength(61));
      int count(MergeReason r) =>
          preview.suggestions.where((s) => s.reason == r).length;
      expect(count(MergeReason.awcSameCodeOverlappingName), 40);
      expect(count(MergeReason.awcSameNameDifferentCode), 8);
      expect(count(MergeReason.schoolSameNameAndCategory), 7);
      expect(count(MergeReason.schoolSameCode), 6);
    });

    test('LAGON / LAGAUN is suggested, never merged on its own', () {
      final lagon = MicroPlanImportPlanner.fileKey(
        MicroPlanRowKind.school,
        'LAGON',
        '9370301901',
      );
      final lagaun = MicroPlanImportPlanner.fileKey(
        MicroPlanRowKind.school,
        'LAGAUN',
        '9370301901',
      );
      final s = preview.suggestions.singleWhere(
        (s) =>
            {s.firstKey, s.secondKey}.containsAll([lagon, lagaun]),
      );
      expect(s.reason, MergeReason.schoolSameCode);
    });

    test('all "no": 290 institutions; 6 repeated school codes left blank', () {
      final plan = _planner.resolve(preview, _answerAll(preview, false));
      expect(plan.institutions, hasLength(290));
      expect(
        plan.institutions.where(
          (i) => (i.dataQualityNotes ?? '').contains('already used by'),
        ),
        hasLength(6),
      );
      final codes = [
        for (final i in plan.institutions)
          if (i.kind == MicroPlanRowKind.school && i.code != null) i.code,
      ];
      expect(codes.toSet(), hasLength(codes.length));
    });

    test('all "yes": 229 institutions and every visit still has one', () {
      final plan = _planner.resolve(preview, _answerAll(preview, true));
      expect(plan.institutions, hasLength(229));
      for (final visit in plan.visits) {
        expect(plan.institutionFor(visit), isNotNull);
      }
    });

    test('all text is in capital letters', () {
      for (final c in preview.fileCandidates) {
        expect(c.name, c.name.toUpperCase());
        expect(c.district, 'LALIPTUR');
        expect(c.block, 'JAKHURA');
      }
      for (final h in preview.holidays) {
        expect(h.name, h.name.toUpperCase());
      }
      for (final v in preview.visits) {
        final person = v.contactPerson;
        if (person != null) expect(person, person.toUpperCase());
      }
    });
  });

  group('rule 1: same name and code are one institution', () {
    test('repeated rows collapse, case and spaces ignored', () {
      final preview = _planner.buildPreview([
        _sheet([
          _school('Lagon', code: '9370301901', day: 1),
          _school('  LAGON ', code: '9370301901', day: 8),
        ]),
      ]);
      expect(preview.fileCandidates, hasLength(1));
      expect(preview.fileCandidates.single.name, 'LAGON');
      expect(preview.fileCandidates.single.sources, hasLength(2));
      expect(preview.visits, hasLength(2));
      expect(preview.suggestions, isEmpty);
    });

    test('an identical existing master record is reused', () {
      final preview = _planner.buildPreview(
        [
          _sheet([_school('LAGON', code: '9370301901')]),
        ],
        existing: const [
          ExistingInstitution(
            id: 'school-1',
            kind: MicroPlanRowKind.school,
            name: 'Lagon',
            code: '9370301901',
            category: 'PS',
          ),
        ],
      );
      expect(preview.fileCandidates.single.existingId, 'school-1');
      final plan = _planner.resolve(preview, const {});
      expect(plan.institutions.single.existingId, 'school-1');
      expect(plan.institutions.single.isNew, isFalse);
    });
  });

  group('rule 2: similar rows become suggestions', () {
    test('a "yes" joins them and keeps the name without "+"', () {
      final preview = _planner.buildPreview([
        _sheet([
          _awc('JAKHAURA-1+2', code: '1'),
          _awc('JAKHAURA-1', code: '1', day: 20),
        ]),
      ]);
      expect(preview.suggestions, hasLength(1));
      expect(
        preview.suggestions.single.reason,
        MergeReason.awcSameCodeOverlappingName,
      );

      final joined = _planner.resolve(preview, {'S1': true});
      expect(joined.institutions, hasLength(1));
      expect(joined.institutions.single.name, 'JAKHAURA-1');
      expect(
        joined.institutions.single.dataQualityNotes,
        contains('JAKHAURA-1+2'),
      );

      final apart = _planner.resolve(preview, {'S1': false});
      expect(apart.institutions, hasLength(2));
    });

    test('"JAKHAURA-1+2" code 2 is suggested with "JAKHAURA-2" code 2', () {
      final preview = _planner.buildPreview([
        _sheet([
          _awc('JAKHAURA-1+2', code: '2'),
          _awc('JAKHAURA-2', code: '2', day: 20),
          _awc('JAKHAURA-1', code: '1', day: 21),
        ]),
      ]);
      expect(preview.suggestions, hasLength(1));
    });

    test('an answer is needed for every suggestion', () {
      final preview = _planner.buildPreview([
        _sheet([
          _school('LAGON', code: '9370301901'),
          _school('LAGAUN', code: '9370301901', day: 20),
        ]),
      ]);
      expect(
        () => _planner.resolve(preview, const {}),
        throwsA(isA<ImportDecisionException>()),
      );
    });

    test('a similar existing record can be chosen', () {
      final preview = _planner.buildPreview(
        [
          _sheet([_school('LAGAUN', code: '9370301901')]),
        ],
        existing: const [
          ExistingInstitution(
            id: 'school-1',
            kind: MicroPlanRowKind.school,
            name: 'LAGON',
            code: '9370301901',
          ),
        ],
      );
      expect(preview.suggestions, hasLength(1));
      expect(preview.candidate('EXISTING|school-1').isExistingRecord, isTrue);

      final plan = _planner.resolve(preview, {'S1': true});
      expect(plan.institutions.single.existingId, 'school-1');
      expect(plan.institutions.single.name, 'LAGON');
    });

    test('answers that would join two existing records are refused', () {
      final preview = _planner.buildPreview(
        [
          _sheet([_school('LAGON', code: '9370301901')]),
        ],
        existing: const [
          ExistingInstitution(
            id: 'school-1',
            kind: MicroPlanRowKind.school,
            name: 'LAGON',
            code: '9370301901',
          ),
          ExistingInstitution(
            id: 'school-2',
            kind: MicroPlanRowKind.school,
            name: 'LAGAUN',
            code: '9370301901',
          ),
        ],
      );
      expect(
        () => _planner.resolve(preview, _answerAll(preview, true)),
        throwsA(isA<ImportDecisionException>()),
      );
    });
  });

  group('rules 3 and 4, and the unique school code', () {
    test('same name, different category (PS / UPS) is not suggested', () {
      final preview = _planner.buildPreview([
        _sheet([
          _school('KUMBHPUR', code: '9370300101'),
          _school('KUMBHPUR', code: '9370300102', category: 'UPS'),
        ]),
      ]);
      expect(preview.fileCandidates, hasLength(2));
      expect(preview.suggestions, isEmpty);
    });

    test('a school without a code gets its own flagged record', () {
      final preview = _planner.buildPreview([
        _sheet([_school('NAVEEN JAKHAURA')]),
      ]);
      final plan = _planner.resolve(preview, const {});
      expect(plan.institutions.single.code, isNull);
      expect(
        plan.institutions.single.dataQualityNotes,
        'No code in the Micro Plan',
      );
    });

    test('a code already in the master is never reused', () {
      final preview = _planner.buildPreview(
        [
          _sheet([_school('DURJANPURA', code: '9370314101')]),
        ],
        existing: const [
          ExistingInstitution(
            id: 'school-1',
            kind: MicroPlanRowKind.school,
            name: 'BANOLI',
            code: '9370314101',
          ),
        ],
      );
      final plan = _planner.resolve(preview, {'S1': false});
      final school = plan.institutions.single;
      expect(school.isNew, isTrue);
      expect(school.code, isNull);
      expect(
        school.dataQualityNotes,
        contains('School code 9370314101 is already used by BANOLI'),
      );
    });
  });

  group('capital letters and other rows', () {
    test('names and contact persons are stored in capitals', () {
      final preview = _planner.buildPreview([
        _sheet([
          _school('lagon', code: '9370301901', contactPerson: 'Rajesh sahu'),
        ]),
      ]);
      expect(preview.fileCandidates.single.name, 'LAGON');
      expect(preview.visits.single.contactPerson, 'RAJESH SAHU');
    });

    test('rows without a date or name wait for attention, not import', () {
      final preview = _planner.buildPreview([
        _sheet([
          const ParsedPlanRow(
            sheetName: 'APRIL25',
            sourceRow: 90,
            kind: MicroPlanRowKind.school,
            flags: [MicroPlanFlag.dateMissing],
            name: 'LAGON',
          ),
          const ParsedPlanRow(
            sheetName: 'APRIL25',
            sourceRow: 91,
            kind: MicroPlanRowKind.holiday,
            flags: [MicroPlanFlag.dateMissing],
            name: 'Ramnavmi',
          ),
          _school(null),
        ]),
      ]);
      expect(preview.fileCandidates, isEmpty);
      expect(preview.visits, isEmpty);
      expect(preview.attentionRows.map((a) => a.reason), [
        AttentionReason.institutionWithoutDate,
        AttentionReason.holidayWithoutDate,
        AttentionReason.institutionWithoutName,
      ]);
    });
  });
}
