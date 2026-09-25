import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/local/import/micro_plan_import_service.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_import_planner.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_import_preview.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_models.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_parser.dart';

import '../../../fixtures/micro_plan/real_plan_2025_26.dart';
import '../test_database.dart';

const _planner = MicroPlanImportPlanner();

/// Every suggestion answered the same way.
Map<String, bool> _answerAll(MicroPlanImportPreview preview, bool answer) => {
  for (final s in preview.suggestions) s.id: answer,
};

ParsedPlanSheet _sheet(List<ParsedPlanRow> rows, {String fy = '2025-2026'}) =>
    ParsedPlanSheet(
      name: 'APRIL25',
      month: 4,
      year: 2025,
      header: MicroPlanHeader(
        financialYearLabel: fy,
        district: 'laliptur',
        block: 'jakhura',
      ),
      rows: rows,
      sheetFlags: const [],
    );

ParsedPlanRow _school(String name, String? code, int row, {int day = 15}) =>
    ParsedPlanRow(
      sheetName: 'APRIL25',
      sourceRow: row,
      kind: MicroPlanRowKind.school,
      flags: const [],
      name: name,
      schoolCode: code,
      schoolCategory: 'PS',
      maleCount: 10,
      femaleCount: 20,
      totalCount: 30,
      visitDate: DateTime.utc(2025, 4, day),
    );

ParsedPlanRow _holiday(String name, int row, {int day = 6}) => ParsedPlanRow(
  sheetName: 'APRIL25',
  sourceRow: row,
  kind: MicroPlanRowKind.holiday,
  flags: const [],
  name: name,
  visitDate: DateTime.utc(2025, 4, day),
);

Future<int> _count(AppDatabase db, String table, {bool liveOnly = false}) =>
    db
        .customSelect(
          'SELECT count(*) AS c FROM $table'
          '${liveOnly ? ' WHERE is_deleted = 0' : ''}',
        )
        .getSingle()
        .then((r) => r.read<int>('c'));

void main() {
  late AppDatabase db;
  late MicroPlanImportService service;

  setUp(() async {
    db = openTestDatabase();
    await Seeds(db).financialYear();
    service = MicroPlanImportService(db);
  });

  tearDown(() => db.close());

  /// Preview + resolve + commit for a small sheet, all suggestions "no".
  Future<MicroPlanImportResult> importRows(
    List<ParsedPlanRow> rows, {
    String fy = '2025-2026',
  }) async {
    final preview = await service.preview([_sheet(rows, fy: fy)]);
    final plan = _planner.resolve(preview, _answerAll(preview, false));
    return service.commit(plan, sourceFilename: 'plan.xlsx');
  }

  group('the real 2025-26 workbook', () {
    test('imports everything in one go', () async {
      final sheets = const MicroPlanParser().parseWorkbook(realPlan2025Sheets);
      final preview = await service.preview(sheets);
      final plan = _planner.resolve(preview, _answerAll(preview, false));

      final result = await service.commit(
        plan,
        sourceFilename: 'PLAN_25-26-B__Repaired__1.xlsx',
      );

      expect(result.financialYearId, 'fy-2025-26');
      expect(result.newSchools, 143);
      expect(result.newAwcs, 147);
      expect(result.visits, 345);
      expect(result.holidays, 25);
      expect(await _count(db, 'schools'), 143);
      expect(await _count(db, 'awcs'), 147);
      expect(await _count(db, 'visit_plans'), 345);
      expect(await _count(db, 'holidays'), 25);
      // 1 import + 290 institutions + 345 visits + 25 holidays.
      expect(await _count(db, 'audit_log'), 661);

      final planImport = await db.select(db.planImports).getSingle();
      expect(planImport.importedBy, isNull);
      expect(planImport.rowCount, 370);

      final visits = await db.select(db.visitPlans).get();
      expect(visits.every((v) => v.planImportId == result.importId), isTrue);
      expect(visits.every((v) => v.status == VisitStatus.PLANNED), isTrue);
      expect(
        visits.every((v) => v.plannedDate == v.originalPlannedDate),
        isTrue,
      );
      final lagon = visits.firstWhere(
        (v) => v.sourceSheet == 'APRIL25' && v.sourceRow == 14,
      );
      expect(
        lagon.plannedDate.isAtSameMomentAs(DateTime.utc(2025, 4, 1)),
        isTrue,
      );
      expect(lagon.plannedTotalCount, 255);
    });

    test('a second import for the same year is refused, nothing written',
        () async {
      final sheets = const MicroPlanParser().parseWorkbook(realPlan2025Sheets);
      final preview = await service.preview(sheets);
      final plan = _planner.resolve(preview, _answerAll(preview, false));
      await service.commit(plan, sourceFilename: 'first.xlsx');

      await expectLater(
        service.commit(plan, sourceFilename: 'second.xlsx'),
        throwsA(isA<MicroPlanAlreadyImportedFailure>()),
      );
      expect(await _count(db, 'plan_imports'), 1);
      expect(await _count(db, 'visit_plans'), 345);
    });
  });

  group('commit', () {
    test('an identical school already in the master is reused', () async {
      await Seeds(
        db,
      ).school(id: 'school-1', name: 'Lagon', officialSchoolCode: '9370301901');

      final result = await importRows([_school('LAGON', '9370301901', 14)]);

      expect(result.newSchools, 0);
      expect(result.reusedInstitutions, 1);
      final visit = await db.select(db.visitPlans).getSingle();
      expect(visit.schoolId, 'school-1');
      expect(await _count(db, 'schools'), 1);
    });

    test('names are stored in capital letters', () async {
      await importRows([_school('lagon', '9370301901', 14)]);
      final school = await db.select(db.schools).getSingle();
      expect(school.name, 'LAGON');
      expect(school.district, 'LALIPTUR');
    });

    test('an unknown financial year is refused before writing', () async {
      await expectLater(
        importRows([_school('LAGON', '9370301901', 14)], fy: '2030-2031'),
        throwsA(isA<FinancialYearNotFoundFailure>()),
      );
      expect(await _count(db, 'plan_imports'), 0);
    });

    test('a failure part-way leaves nothing behind', () async {
      // A plan built by hand with a code the database already holds: the
      // unique index fails on the school insert, after plan_imports.
      await Seeds(
        db,
      ).school(id: 'school-1', name: 'OTHER', officialSchoolCode: '123');
      final plan = MicroPlanImportPlan(
        institutions: const [
          ResolvedInstitution(
            kind: MicroPlanRowKind.school,
            candidateKeys: ['k'],
            name: 'LAGON',
            code: '123',
            sources: [],
          ),
        ],
        institutionIndexByCandidate: const {'k': 0},
        visits: [
          PlannedVisitDraft(
            candidateKey: 'k',
            source: const SourceRef('APRIL25', 14),
            plannedDate: DateTime.utc(2025, 4, 1),
          ),
        ],
        holidays: const [],
        financialYearLabel: '2025-2026',
      );

      await expectLater(
        service.commit(plan, sourceFilename: 'plan.xlsx'),
        throwsA(anything),
      );
      expect(await _count(db, 'plan_imports'), 0);
      expect(await _count(db, 'visit_plans'), 0);
      expect(await _count(db, 'schools'), 1);
      expect(await _count(db, 'audit_log'), 0);
    });
  });

  group('undo', () {
    test('removes the import and its new schools; a new import is then '
        'allowed', () async {
      await Seeds(db).school(id: 'school-1', name: 'OLD SCHOOL');
      final first = await importRows([
        _school('LAGON', '9370301901', 14),
        _holiday('RAMNAVMI', 20),
      ]);

      final undone = await service.undo(first.importId);

      expect(undone.visits, 1);
      expect(undone.holidays, 1);
      expect(undone.schools, 1);
      expect(await _count(db, 'visit_plans', liveOnly: true), 0);
      expect(await _count(db, 'holidays', liveOnly: true), 0);
      // The school that was there before the import is untouched.
      expect(await _count(db, 'schools', liveOnly: true), 1);
      final removed = await (db.select(
        db.schools,
      )..where((s) => s.name.equals('LAGON'))).getSingle();
      expect(removed.isDeleted, isTrue);
      expect(removed.officialSchoolCode, isNull); // code released
      expect(await service.liveImportId('fy-2025-26'), isNull);

      // The same code can be imported again.
      final second = await importRows([_school('LAGON', '9370301901', 14)]);
      expect(second.newSchools, 1);
      final lagon = await (db.select(db.schools)
            ..where((s) => s.isDeleted.equals(false) & s.name.equals('LAGON')))
          .getSingle();
      expect(lagon.officialSchoolCode, '9370301901');
    });

    test('is refused once work has started on any visit', () async {
      final result = await importRows([
        _school('LAGON', '9370301901', 14),
        _school('RAIPUR', '9370300404', 15, day: 16),
      ]);
      final visit = await (db.select(
        db.visitPlans,
      )..where((v) => v.sourceRow.equals(15))).getSingle();
      await (db.update(db.visitPlans)..where((v) => v.id.equals(visit.id)))
          .write(const VisitPlansCompanion(status: Value(VisitStatus.COMPLETED)));

      await expectLater(
        service.undo(result.importId),
        throwsA(
          isA<MicroPlanUndoBlockedFailure>().having(
            (f) => f.touchedCount,
            'touchedCount',
            1,
          ),
        ),
      );
      expect(await _count(db, 'visit_plans', liveOnly: true), 2);
    });

    test('cannot be done twice', () async {
      final result = await importRows([_school('LAGON', '9370301901', 14)]);
      await service.undo(result.importId);
      await expectLater(
        service.undo(result.importId),
        throwsA(isA<MicroPlanImportAlreadyUndoneFailure>()),
      );
    });

    test('an unknown import id is reported', () async {
      await expectLater(
        service.undo('no-such-import'),
        throwsA(isA<MicroPlanImportNotFoundFailure>()),
      );
    });
  });
}
