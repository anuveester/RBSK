import 'package:referredline/data/local/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';

import 'test_database.dart';

void main() {
  group('AppDatabase — opening and schema creation', () {
    test('opens successfully against an in-memory executor', () async {
      final db = openTestDatabase();
      addTearDown(db.close);

      // A trivial query only succeeds if the connection is live and the
      // schema was created without error.
      final result = await db.customSelect('SELECT 1 AS one').getSingle();
      expect(result.read<int>('one'), 1);
    });

    test('reports schema version 1 (the frozen v1.0 baseline)', () async {
      final db = openTestDatabase();
      addTearDown(db.close);

      expect(db.schemaVersion, 1);
    });

    test('creates all 28 tables from the frozen schema', () async {
      final db = openTestDatabase();
      addTearDown(db.close);

      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '__drift%'",
          )
          .get();
      final tableNames = rows.map((r) => r.read<String>('name')).toSet();

      const expected = {
        'financial_years',
        'staff',
        'staff_assignments',
        'users',
        'devices',
        'schools',
        'awcs',
        'plan_imports',
        'visit_plans',
        'holidays',
        'visit_status_history',
        'disease_master',
        'disease_aliases',
        'screening_sessions',
        'school_screenings',
        'school_screening_findings',
        'awc_screenings',
        'awc_screening_findings',
        'awc_checklist_items',
        'awc_screening_checklist_responses',
        'referral_destinations',
        'referral_destination_contexts',
        'treatment_records',
        'register_photos',
        'register_photo_derivatives',
        'ocr_jobs',
        'ocr_results',
        'audit_log',
      };

      expect(expected.difference(tableNames), isEmpty,
          reason: 'missing tables from the frozen schema');
      expect(tableNames.length, 28,
          reason: 'unexpected extra table — schema should have exactly 28');
    });

    test('enables foreign key enforcement on open', () async {
      final db = openTestDatabase();
      addTearDown(db.close);

      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(row.read<int>('foreign_keys'), 1);
    });
  });

  group('AppDatabase — primary keys', () {
    test('rejects a duplicate primary key', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);
      final fyId = await seeds.financialYear();

      expect(
        () => seeds.financialYear(id: fyId),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('AppDatabase — foreign keys', () {
    test('rejects a visit_plans row pointing at a non-existent school',
        () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);
      final fyId = await seeds.financialYear();

      expect(
        () => seeds.visitPlanForSchool(
          financialYearId: fyId,
          schoolId: 'does-not-exist',
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('allows a valid foreign key reference', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);
      final fyId = await seeds.financialYear();
      final schoolId = await seeds.school();

      final visitId = await seeds.visitPlanForSchool(
        financialYearId: fyId,
        schoolId: schoolId,
      );

      final visit = await (db.select(
        db.visitPlans,
      )..where((t) => t.id.equals(visitId))).getSingle();
      expect(visit.schoolId, schoolId);
    });

    test('the school-XOR-awc CHECK constraint rejects both being null',
        () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);
      final fyId = await seeds.financialYear();

      expect(
        () => db.into(db.visitPlans).insert(
              VisitPlansCompanion.insert(
                id: 'bad-visit',
                financialYearId: fyId,
                locationType: LocationType.SCHOOL,
                originalPlannedDate: DateTime.utc(2026, 4, 1),
                plannedDate: DateTime.utc(2026, 4, 1),
                // school_id intentionally omitted — violates the CHECK
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('AppDatabase — nullable official codes', () {
    test('a school with no official code inserts successfully', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      final id = await seeds.school(id: 's-blank', officialSchoolCode: null);

      final row =
          await (db.select(db.schools)..where((t) => t.id.equals(id)))
              .getSingle();
      expect(row.officialSchoolCode, isNull);
    });

    test('two schools may both have a blank official code', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      await seeds.school(id: 's-blank-1', officialSchoolCode: null);
      // Must not throw — uniqueness applies only to non-blank codes.
      await seeds.school(id: 's-blank-2', officialSchoolCode: null);

      final count = await db.schools.count().getSingle();
      expect(count, 2);
    });

    test('a non-blank official school code must be unique', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      await seeds.school(id: 's-1', officialSchoolCode: '9370301901');

      expect(
        () => seeds.school(id: 's-2', officialSchoolCode: '9370301901'),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('AppDatabase — timestamps and audit fields', () {
    test('created_at and row_version default correctly on insert', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      final id = await seeds.school();
      final row =
          await (db.select(db.schools)..where((t) => t.id.equals(id)))
              .getSingle();

      expect(row.rowVersion, 1);
      expect(row.createdAt, isNotNull);
      expect(row.updatedAt, isNotNull);
      expect(row.createdBy, isNull); // not supplied — stays null, not invented
    });

    test('updating a row lets the app advance row_version and updated_at',
        () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);
      final id = await seeds.school();
      final before =
          await (db.select(db.schools)..where((t) => t.id.equals(id)))
              .getSingle();

      final newTimestamp = before.updatedAt.add(const Duration(minutes: 1));
      await (db.update(db.schools)..where((t) => t.id.equals(id))).write(
        SchoolsCompanion(
          name: const Value('Renamed School'),
          rowVersion: Value(before.rowVersion + 1),
          updatedAt: Value(newTimestamp),
        ),
      );

      final after =
          await (db.select(db.schools)..where((t) => t.id.equals(id)))
              .getSingle();
      expect(after.name, 'Renamed School');
      expect(after.rowVersion, before.rowVersion + 1);
      expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
    });
  });

  group('AppDatabase — soft delete', () {
    test('is_deleted defaults to false and can be set without a hard delete',
        () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);
      final id = await seeds.school();

      final before =
          await (db.select(db.schools)..where((t) => t.id.equals(id)))
              .getSingle();
      expect(before.isDeleted, isFalse);

      await (db.update(db.schools)..where((t) => t.id.equals(id))).write(
        const SchoolsCompanion(isDeleted: Value(true)),
      );

      final after =
          await (db.select(db.schools)..where((t) => t.id.equals(id)))
              .getSingle();
      expect(after.isDeleted, isTrue);
      // The row still physically exists — this was never a DELETE statement.
      final stillPresent = await db.schools.count().getSingle();
      expect(stillPresent, 1);
    });
  });

  group('AppDatabase — history tables preserve multiple records', () {
    test('visit_status_history accumulates rows rather than overwriting',
        () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);
      final fyId = await seeds.financialYear();
      final schoolId = await seeds.school();
      final userId = await seeds.user();
      final visitId = await seeds.visitPlanForSchool(
        financialYearId: fyId,
        schoolId: schoolId,
      );

      for (final transition in [
        (VisitStatus.PLANNED, VisitStatus.MISSED),
        (VisitStatus.MISSED, VisitStatus.RESCHEDULED),
        (VisitStatus.RESCHEDULED, VisitStatus.COMPLETED),
      ]) {
        await db.into(db.visitStatusHistory).insert(
              VisitStatusHistoryCompanion.insert(
                id: 'history-${transition.$2.name}',
                visitPlanId: visitId,
                toStatus: transition.$2,
                fromStatus: Value(transition.$1),
                changedBy: userId,
              ),
            );
      }

      final history = await (db.select(db.visitStatusHistory)
            ..where((t) => t.visitPlanId.equals(visitId))
            ..orderBy([(t) => OrderingTerm(expression: t.changedAt)]))
          .get();

      expect(history, hasLength(3));
      expect(history.map((h) => h.toStatus), [
        VisitStatus.MISSED,
        VisitStatus.RESCHEDULED,
        VisitStatus.COMPLETED,
      ]);
    });

    test('staff_assignments preserves a closed assignment when a new one starts',
        () async {
      final db = openTestDatabase();
      addTearDown(db.close);

      await db.into(db.staff).insert(
            StaffCompanion.insert(id: 'staff-a', fullName: 'Outgoing'),
          );
      await db.into(db.staffAssignments).insert(
            StaffAssignmentsCompanion.insert(
              id: 'assign-1',
              staffId: 'staff-a',
              roleInTeam: 'Medical Officer',
              startDate: DateTime.utc(2025, 4, 1),
              endDate: Value(DateTime.utc(2025, 8, 15)),
            ),
          );
      await db.into(db.staff).insert(
            StaffCompanion.insert(id: 'staff-b', fullName: 'Incoming'),
          );
      await db.into(db.staffAssignments).insert(
            StaffAssignmentsCompanion.insert(
              id: 'assign-2',
              staffId: 'staff-b',
              roleInTeam: 'Medical Officer',
              startDate: DateTime.utc(2025, 8, 16),
            ),
          );

      final all = await db.select(db.staffAssignments).get();
      expect(all, hasLength(2));
      final closed = all.firstWhere((a) => a.staffId == 'staff-a');
      expect(closed.endDate, isNotNull); // never overwritten to null
    });
  });

  group('AppDatabase — basic CRUD', () {
    test('insert, read, update round-trip on disease_master', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final seeds = Seeds(db);

      final id = await seeds.diseaseMasterRow();
      final inserted =
          await (db.select(db.diseaseMaster)..where((t) => t.id.equals(id)))
              .getSingle();
      expect(inserted.name, 'Vitamin A Deficiency');
      expect(inserted.officialCode, '11');

      await (db.update(db.diseaseMaster)..where((t) => t.id.equals(id)))
          .write(const DiseaseMasterCompanion(isActive: Value(false)));

      final updated =
          await (db.select(db.diseaseMaster)..where((t) => t.id.equals(id)))
              .getSingle();
      expect(updated.isActive, isFalse);
    });
  });
}
