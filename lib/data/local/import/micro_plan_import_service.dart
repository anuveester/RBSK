import 'package:drift/drift.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/utils/id_generator.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/audit/business_audit_writer.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_import_planner.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_import_preview.dart';
import 'package:referredline/domain/services/micro_plan/micro_plan_models.dart';

/// What one successful import wrote.
class MicroPlanImportResult {
  const MicroPlanImportResult({
    required this.importId,
    required this.financialYearId,
    required this.newSchools,
    required this.newAwcs,
    required this.reusedInstitutions,
    required this.visits,
    required this.holidays,
  });

  final String importId;
  final String financialYearId;
  final int newSchools;
  final int newAwcs;
  final int reusedInstitutions;
  final int visits;
  final int holidays;
}

/// What an undo removed (soft delete only — nothing is ever hard-deleted).
class MicroPlanUndoResult {
  const MicroPlanUndoResult({
    required this.visits,
    required this.holidays,
    required this.schools,
    required this.awcs,
  });

  final int visits;
  final int holidays;
  final int schools;
  final int awcs;
}

/// Saves a Micro Plan import (docs/01_PRD.md FR-2.x) and can undo it.
///
/// * [preview] reads the School/AWC master so the planner can match rows.
/// * [commit] writes everything in ONE transaction: all or nothing.
/// * Only one live import per financial year; a second one is refused
///   [USER-DECIDED 2026-09-25, option A].
/// * [undo] soft-deletes an import's visits and holidays (and the schools
///   and AWCs it created, if nothing else uses them) — only while no work has
///   started on any of them. Field work is never erased.
/// * Every write gets an `audit_log` row with no actor (no authentication
///   yet); `plan_imports.imported_by` stays NULL (schema v2).
class MicroPlanImportService {
  MicroPlanImportService(
    this._db, {
    this._audit = const BusinessAuditWriter(),
    this._planner = const MicroPlanImportPlanner(),
  });

  final AppDatabase _db;
  final BusinessAuditWriter _audit;
  final MicroPlanImportPlanner _planner;

  static final RegExp _yearLabel = RegExp(r'(\d{4})\s*-\s*\d{2,4}');

  /// Tables whose rows mean "work has started on this visit".
  static const List<String> _visitWorkTables = [
    'visit_status_history',
    'screening_sessions',
    'school_screenings',
    'awc_screenings',
    'register_photos',
  ];

  // ---------------------------------------------------------------------------
  // Preview
  // ---------------------------------------------------------------------------

  Future<MicroPlanImportPreview> preview(List<ParsedPlanSheet> sheets) async {
    final schools = await _db.select(_db.schools).get();
    final awcs = await _db.select(_db.awcs).get();
    return _planner.buildPreview(
      sheets,
      existing: [
        for (final s in schools)
          if (!s.isDeleted)
            ExistingInstitution(
              id: s.id,
              kind: MicroPlanRowKind.school,
              name: s.name,
              code: s.officialSchoolCode,
              category: s.institutionType,
            ),
        for (final a in awcs)
          if (!a.isDeleted)
            ExistingInstitution(
              id: a.id,
              kind: MicroPlanRowKind.awc,
              name: a.name,
              code: a.sourcePlanAwcCode,
            ),
      ],
      reservedSchoolCodes: {
        for (final s in schools)
          if ((s.officialSchoolCode ?? '').trim().isNotEmpty)
            s.officialSchoolCode!: s.name,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Commit
  // ---------------------------------------------------------------------------

  /// Writes [plan]. Throws [FinancialYearNotFoundFailure] or
  /// [MicroPlanAlreadyImportedFailure] before writing anything.
  Future<MicroPlanImportResult> commit(
    MicroPlanImportPlan plan, {
    required String sourceFilename,
  }) async {
    final year = await _financialYearFor(plan.financialYearLabel);
    final liveImport = await liveImportId(year.id);
    if (liveImport != null) {
      throw MicroPlanAlreadyImportedFailure(year.label, liveImport);
    }

    final importId = generateUuidV4();
    final now = DateTime.now().toUtc();
    final newSchools = plan.institutions
        .where((i) => i.isNew && i.kind == MicroPlanRowKind.school)
        .length;
    final newAwcs = plan.institutions
        .where((i) => i.isNew && i.kind == MicroPlanRowKind.awc)
        .length;
    final reused = plan.institutions.length - newSchools - newAwcs;
    final notes =
        '$newSchools new schools, $newAwcs new AWCs, $reused already in the '
        'master; ${plan.visits.length} visits, ${plan.holidays.length} '
        'holidays';

    await _db.transaction(() async {
      await _db
          .into(_db.planImports)
          .insert(
            PlanImportsCompanion.insert(
              id: importId,
              financialYearId: year.id,
              sourceFilename: sourceFilename,
              importedAt: Value(now),
              rowCount: Value(plan.visits.length + plan.holidays.length),
              notes: Value(notes),
            ),
          );
      await _audit.recordInsert(
        _db,
        table: 'plan_imports',
        recordId: importId,
        values: {
          'financial_year_id': year.id,
          'source_filename': sourceFilename,
          'imported_by': null,
          'row_count': plan.visits.length + plan.holidays.length,
          'notes': notes,
        },
      );

      final institutionIds = <String>[];
      for (final institution in plan.institutions) {
        institutionIds.add(
          institution.isNew
              ? await _insertInstitution(institution, now)
              : institution.existingId!,
        );
      }

      for (final visit in plan.visits) {
        final index = plan.institutionIndexByCandidate[visit.candidateKey]!;
        final isSchool =
            plan.institutions[index].kind == MicroPlanRowKind.school;
        final institutionId = institutionIds[index];
        final id = generateUuidV4();
        await _db
            .into(_db.visitPlans)
            .insert(
              VisitPlansCompanion.insert(
                id: id,
                financialYearId: year.id,
                locationType: isSchool ? LocationType.SCHOOL : LocationType.AWC,
                schoolId: Value(isSchool ? institutionId : null),
                awcId: Value(isSchool ? null : institutionId),
                planImportId: Value(importId),
                originalPlannedDate: visit.plannedDate,
                plannedDate: visit.plannedDate,
                plannedMaleCount: Value(visit.maleCount),
                plannedFemaleCount: Value(visit.femaleCount),
                plannedTotalCount: Value(visit.totalCount),
                contactPerson: Value(visit.contactPerson),
                contactNumber: Value(visit.contactNumber),
                sourceSheet: Value(visit.source.sheetName),
                sourceRow: Value(visit.source.row),
                dataQualityNotes: Value(visit.dataQualityNotes),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        await _audit.recordInsert(
          _db,
          table: 'visit_plans',
          recordId: id,
          values: {
            'financial_year_id': year.id,
            'location_type': isSchool ? 'SCHOOL' : 'AWC',
            'school_id': isSchool ? institutionId : null,
            'awc_id': isSchool ? null : institutionId,
            'plan_import_id': importId,
            'original_planned_date': visit.plannedDate.toIso8601String(),
            'planned_date': visit.plannedDate.toIso8601String(),
            'status': 'PLANNED',
            'planned_male_count': visit.maleCount,
            'planned_female_count': visit.femaleCount,
            'planned_total_count': visit.totalCount,
            'contact_person': visit.contactPerson,
            'contact_number': visit.contactNumber,
            'source_sheet': visit.source.sheetName,
            'source_row': visit.source.row,
            'data_quality_notes': visit.dataQualityNotes,
          },
        );
      }

      for (final holiday in plan.holidays) {
        final id = generateUuidV4();
        final remarks = 'Micro Plan ${holiday.source}';
        await _db
            .into(_db.holidays)
            .insert(
              HolidaysCompanion.insert(
                id: id,
                holidayDate: holiday.date,
                name: holiday.name,
                financialYearId: Value(year.id),
                planImportId: Value(importId),
                remarks: Value(remarks),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        await _audit.recordInsert(
          _db,
          table: 'holidays',
          recordId: id,
          values: {
            'financial_year_id': year.id,
            'holiday_date': holiday.date.toIso8601String(),
            'name': holiday.name,
            'plan_import_id': importId,
            'remarks': remarks,
            'is_manual_addition': false,
          },
        );
      }
    });

    return MicroPlanImportResult(
      importId: importId,
      financialYearId: year.id,
      newSchools: newSchools,
      newAwcs: newAwcs,
      reusedInstitutions: reused,
      visits: plan.visits.length,
      holidays: plan.holidays.length,
    );
  }

  /// The import that still has live (not undone) visits or holidays in this
  /// financial year, or null.
  Future<String?> liveImportId(String financialYearId) async {
    final visit =
        await (_db.select(_db.visitPlans)
              ..where(
                (v) =>
                    v.financialYearId.equals(financialYearId) &
                    v.planImportId.isNotNull() &
                    v.isDeleted.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();
    if (visit != null) return visit.planImportId;
    final holiday =
        await (_db.select(_db.holidays)
              ..where(
                (h) =>
                    h.financialYearId.equals(financialYearId) &
                    h.planImportId.isNotNull() &
                    h.isDeleted.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();
    return holiday?.planImportId;
  }

  /// "2025-2026" or "2025-26" → the financial year starting April 2025.
  Future<FinancialYear> _financialYearFor(String? label) async {
    final match = label == null ? null : _yearLabel.firstMatch(label);
    if (match == null) throw FinancialYearNotFoundFailure(label);
    final startYear = int.parse(match.group(1)!);
    final years = await _db.select(_db.financialYears).get();
    final year = years
        .where((y) => y.startDate.year == startYear && y.startDate.month == 4)
        .firstOrNull;
    if (year == null) throw FinancialYearNotFoundFailure(label);
    return year;
  }

  Future<String> _insertInstitution(
    ResolvedInstitution institution,
    DateTime now,
  ) async {
    final id = generateUuidV4();
    if (institution.kind == MicroPlanRowKind.school) {
      await _db
          .into(_db.schools)
          .insert(
            SchoolsCompanion.insert(
              id: id,
              name: institution.name,
              officialSchoolCode: Value(institution.code),
              institutionType: Value(institution.category),
              district: Value(institution.district),
              block: Value(institution.block),
              dataQualityNotes: Value(institution.dataQualityNotes),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await _audit.recordInsert(
        _db,
        table: 'schools',
        recordId: id,
        values: {
          'name': institution.name,
          'official_school_code': institution.code,
          'institution_type': institution.category,
          'district': institution.district,
          'block': institution.block,
          'data_quality_notes': institution.dataQualityNotes,
          'is_active': true,
        },
      );
    } else {
      await _db
          .into(_db.awcs)
          .insert(
            AwcsCompanion.insert(
              id: id,
              name: institution.name,
              sourcePlanAwcCode: Value(institution.code),
              district: Value(institution.district),
              block: Value(institution.block),
              dataQualityNotes: Value(institution.dataQualityNotes),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await _audit.recordInsert(
        _db,
        table: 'awcs',
        recordId: id,
        values: {
          'name': institution.name,
          'source_plan_awc_code': institution.code,
          'district': institution.district,
          'block': institution.block,
          'data_quality_notes': institution.dataQualityNotes,
          'is_active': true,
        },
      );
    }
    return id;
  }

  // ---------------------------------------------------------------------------
  // Undo
  // ---------------------------------------------------------------------------

  /// Soft-deletes everything [importId] created, if no work has started on
  /// any of it. Schools/AWCs it created are removed only when no other visit
  /// uses them and they were never edited; a removed school's code is
  /// released so a later import can use it again.
  Future<MicroPlanUndoResult> undo(String importId) async {
    final planImport = await (_db.select(
      _db.planImports,
    )..where((p) => p.id.equals(importId))).getSingleOrNull();
    if (planImport == null) throw const MicroPlanImportNotFoundFailure();

    final visits = await (_db.select(_db.visitPlans)
          ..where(
            (v) => v.planImportId.equals(importId) & v.isDeleted.equals(false),
          ))
        .get();
    final holidays = await (_db.select(_db.holidays)
          ..where(
            (h) => h.planImportId.equals(importId) & h.isDeleted.equals(false),
          ))
        .get();
    if (visits.isEmpty && holidays.isEmpty) {
      throw const MicroPlanImportAlreadyUndoneFailure();
    }

    final touched = <String>{
      for (final v in visits)
        if (v.status != VisitStatus.PLANNED ||
            v.actualVisitDate != null ||
            v.plannedDate != v.originalPlannedDate ||
            v.rowVersion != 1)
          v.id,
      for (final h in holidays)
        if (h.rowVersion != 1) h.id,
      ...await _visitsWithWork([for (final v in visits) v.id]),
      ...await _holidaysInUse([for (final h in holidays) h.id]),
    };
    if (touched.isNotEmpty) throw MicroPlanUndoBlockedFailure(touched.length);

    final now = DateTime.now().toUtc();
    var schoolsRemoved = 0;
    var awcsRemoved = 0;

    await _db.transaction(() async {
      for (final v in visits) {
        await (_db.update(_db.visitPlans)..where((t) => t.id.equals(v.id)))
            .write(
              VisitPlansCompanion(
                isDeleted: const Value(true),
                updatedAt: Value(now),
                rowVersion: Value(v.rowVersion + 1),
              ),
            );
        await _audit.recordSoftDelete(
          _db,
          table: 'visit_plans',
          recordId: v.id,
        );
      }
      for (final h in holidays) {
        await (_db.update(_db.holidays)..where((t) => t.id.equals(h.id)))
            .write(
              HolidaysCompanion(
                isDeleted: const Value(true),
                updatedAt: Value(now),
                rowVersion: Value(h.rowVersion + 1),
              ),
            );
        await _audit.recordSoftDelete(
          _db,
          table: 'holidays',
          recordId: h.id,
        );
      }

      // Institutions this import created: same creation instant as the
      // import, never edited, and no live visit left pointing at them.
      final schools = await (_db.select(_db.schools)
            ..where(
              (s) =>
                  s.createdAt.equals(planImport.importedAt) &
                  s.rowVersion.equals(1) &
                  s.isDeleted.equals(false),
            ))
          .get();
      for (final s in schools) {
        if (await _hasLiveVisit(schoolId: s.id)) continue;
        await (_db.update(_db.schools)..where((t) => t.id.equals(s.id))).write(
          SchoolsCompanion(
            isDeleted: const Value(true),
            officialSchoolCode: const Value(null),
            updatedAt: Value(now),
            rowVersion: Value(s.rowVersion + 1),
          ),
        );
        await _audit.recordSoftDelete(
          _db,
          table: 'schools',
          recordId: s.id,
          otherOld: {'official_school_code': s.officialSchoolCode},
          otherNew: {'official_school_code': null},
        );
        schoolsRemoved++;
      }

      final awcs = await (_db.select(_db.awcs)
            ..where(
              (a) =>
                  a.createdAt.equals(planImport.importedAt) &
                  a.rowVersion.equals(1) &
                  a.isDeleted.equals(false),
            ))
          .get();
      for (final a in awcs) {
        if (await _hasLiveVisit(awcId: a.id)) continue;
        await (_db.update(_db.awcs)..where((t) => t.id.equals(a.id))).write(
          AwcsCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(now),
            rowVersion: Value(a.rowVersion + 1),
          ),
        );
        await _audit.recordSoftDelete(_db, table: 'awcs', recordId: a.id);
        awcsRemoved++;
      }

      final undoneNote = 'Undone ${now.toIso8601String()}';
      final notes = planImport.notes == null
          ? undoneNote
          : '${planImport.notes}; $undoneNote';
      await (_db.update(_db.planImports)..where((p) => p.id.equals(importId)))
          .write(PlanImportsCompanion(notes: Value(notes)));
      await _audit.recordUpdate(
        _db,
        table: 'plan_imports',
        recordId: importId,
        oldValues: {'notes': planImport.notes},
        newValues: {'notes': notes},
      );
    });

    return MicroPlanUndoResult(
      visits: visits.length,
      holidays: holidays.length,
      schools: schoolsRemoved,
      awcs: awcsRemoved,
    );
  }

  Future<Set<String>> _visitsWithWork(List<String> visitIds) async {
    final found = <String>{};
    if (visitIds.isEmpty) return found;
    final placeholders = List.filled(visitIds.length, '?').join(', ');
    for (final table in _visitWorkTables) {
      final rows = await _db
          .customSelect(
            'SELECT DISTINCT visit_plan_id AS id FROM $table '
            'WHERE visit_plan_id IN ($placeholders)',
            variables: [for (final id in visitIds) Variable.withString(id)],
          )
          .get();
      found.addAll(rows.map((r) => r.read<String>('id')));
    }
    return found;
  }

  Future<Set<String>> _holidaysInUse(List<String> holidayIds) async {
    if (holidayIds.isEmpty) return <String>{};
    final placeholders = List.filled(holidayIds.length, '?').join(', ');
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT related_holiday_id AS id FROM visit_status_history '
          'WHERE related_holiday_id IN ($placeholders)',
          variables: [for (final id in holidayIds) Variable.withString(id)],
        )
        .get();
    return {for (final r in rows) r.read<String>('id')};
  }

  Future<bool> _hasLiveVisit({String? schoolId, String? awcId}) async {
    final visit =
        await (_db.select(_db.visitPlans)
              ..where(
                (v) =>
                    (schoolId != null
                        ? v.schoolId.equals(schoolId)
                        : v.awcId.equals(awcId!)) &
                    v.isDeleted.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();
    return visit != null;
  }
}
