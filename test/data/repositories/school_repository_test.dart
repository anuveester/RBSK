import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/data/local/app_database.dart' as db;
import 'package:referredline/data/local/audit/business_audit_writer.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/local/sqlite_errors.dart';
import 'package:referredline/data/repositories/drift_school_repository.dart';
import 'package:referredline/domain/entities/master_list_query.dart';
import 'package:referredline/domain/entities/school.dart';

import '../local/test_database.dart';

// Synthetic names and codes only — never real school codes.
final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

class _FailingAudit extends BusinessAuditWriter {
  const _FailingAudit();

  @override
  Future<void> recordInsert(
    db.AppDatabase db, {
    required String table,
    required String recordId,
    required Map<String, Object?> values,
  }) async => throw StateError('audit write failed');

  @override
  Future<void> recordUpdate(
    db.AppDatabase db, {
    required String table,
    required String recordId,
    required Map<String, Object?> oldValues,
    required Map<String, Object?> newValues,
  }) async => throw StateError('audit write failed');
}

void main() {
  late db.AppDatabase database;
  late DriftSchoolRepository repo;

  setUp(() {
    database = openTestDatabase();
    repo = DriftSchoolRepository(database);
  });
  tearDown(() => database.close());

  Future<List<db.AuditLogData>> audit() => (database.select(
    database.auditLog,
  )..orderBy([(a) => OrderingTerm.asc(a.occurredAt)])).get();

  Future<db.School> raw(String id) => (database.select(
    database.schools,
  )..where((s) => s.id.equals(id))).getSingle();

  Future<School> make(
    String name, {
    String? code,
    String? district,
    String? block,
    String? village,
  }) => repo.create(
    SchoolInput(
      name: name,
      officialSchoolCode: code,
      district: district,
      block: block,
      panchayatVillage: village,
    ),
  );

  group('create and read', () {
    test('creates with a UUIDv4 id, trimmed fields, row_version 1, active, '
        'and no user attribution', () async {
      final school = await repo.create(
        const SchoolInput(
          name: '  Test School Alpha  ',
          officialSchoolCode: ' SYN-0001 ',
          institutionType: 'PS',
          district: ' Test District ',
          block: 'Test Block',
          panchayatVillage: 'Test Village',
          address: 'Synthetic address 1',
        ),
      );

      expect(school.id, matches(_uuidV4));
      expect(school.name, 'Test School Alpha');
      expect(school.officialSchoolCode, 'SYN-0001');
      expect(school.institutionType, 'PS');
      expect(school.district, 'Test District');
      expect(school.isActive, isTrue);
      expect(school.rowVersion, 1);
      final row = await raw(school.id);
      expect(row.createdBy, isNull);
      expect(row.updatedBy, isNull);
      expect(row.isDeleted, isFalse);
      expect((await repo.getById(school.id))!.name, 'Test School Alpha');
    });

    test('a name is required', () async {
      await expectLater(
        repo.create(const SchoolInput(name: '   ')),
        throwsA(isA<NameRequiredFailure>()),
      );
      expect(await database.select(database.schools).get(), isEmpty);
      expect(await audit(), isEmpty);
    });

    test('getById returns null for an unknown id', () async {
      expect(await repo.getById('no-such-id'), isNull);
    });
  });

  group('official school code', () {
    test('a blank or whitespace code is stored blank (null), never invented, '
        'and many schools may have no code', () async {
      final a = await make('Test School A', code: '');
      final b = await make('Test School B', code: '   ');
      final c = await make('Test School C');
      for (final s in [a, b, c]) {
        expect(s.officialSchoolCode, isNull);
        expect((await raw(s.id)).officialSchoolCode, isNull);
      }
    });

    test('a non-blank code already used blocks the save, names the other '
        'school, and writes nothing', () async {
      await make('Test School A', code: 'SYN-0001');
      final auditBefore = (await audit()).length;

      await expectLater(
        make('Test School B', code: 'SYN-0001'),
        throwsA(
          isA<DuplicateOfficialCodeFailure>().having(
            (f) => f.message,
            'message',
            allOf(contains('School Code already exists'), contains('Test School A')),
          ),
        ),
      );
      expect(await database.select(database.schools).get(), hasLength(1));
      expect(await audit(), hasLength(auditBefore));
    });

    test('changing a code to one already used is blocked; keeping its own '
        'code is fine', () async {
      await make('Test School A', code: 'SYN-0001');
      final b = await make('Test School B', code: 'SYN-0002');

      await expectLater(
        repo.update(
          b.id,
          const SchoolInput(name: 'Test School B', officialSchoolCode: 'SYN-0001'),
        ),
        throwsA(isA<DuplicateOfficialCodeFailure>()),
      );
      final renamed = await repo.update(
        b.id,
        const SchoolInput(name: 'Test School B2', officialSchoolCode: 'SYN-0002'),
      );
      expect(renamed.name, 'Test School B2');
      expect((await raw(b.id)).officialSchoolCode, 'SYN-0002');
    });

    test('the unique index is recognised as a duplicate code', () async {
      await make('Test School A', code: 'SYN-0001');
      Object? error;
      try {
        await database
            .into(database.schools)
            .insert(
              db.SchoolsCompanion.insert(
                id: 'direct',
                name: 'Direct insert',
                officialSchoolCode: const Value('SYN-0001'),
              ),
            );
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(isUniqueConstraintViolation(error!), isTrue);
      expect(isUniqueConstraintViolation(StateError('other')), isFalse);
    });
  });

  group('update, row_version and Active/Inactive', () {
    test('an edit writes only what changed, advances updated_at and '
        'row_version, and leaves the record active', () async {
      final school = await make('Test School A', code: 'SYN-0001');
      final before = await raw(school.id);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final updated = await repo.update(
        school.id,
        const SchoolInput(
          name: 'Test School A',
          officialSchoolCode: 'SYN-0001',
          block: 'Test Block',
        ),
      );

      expect(updated.block, 'Test Block');
      expect(updated.rowVersion, 2);
      expect(updated.updatedAt.isAfter(before.updatedAt), isTrue);
      expect(updated.createdAt, before.createdAt);
    });

    test('saving without a change writes nothing and adds no audit row',
        () async {
      final school = await make('Test School A', code: 'SYN-0001');
      final auditBefore = (await audit()).length;

      final same = await repo.update(
        school.id,
        const SchoolInput(name: ' Test School A ', officialSchoolCode: 'SYN-0001'),
      );

      expect(same.rowVersion, 1);
      expect(await audit(), hasLength(auditBefore));
    });

    test('deactivate and reactivate: the record stays stored, row_version '
        'rises each time', () async {
      final school = await make('Test School A');

      final inactive = await repo.setActive(school.id, active: false);
      expect(inactive.isActive, isFalse);
      expect(inactive.rowVersion, 2);
      expect(await database.select(database.schools).get(), hasLength(1));

      final active = await repo.setActive(school.id, active: true);
      expect(active.isActive, isTrue);
      expect(active.rowVersion, 3);
    });

    test('an unknown id cannot be updated or deactivated', () async {
      await expectLater(
        repo.update('missing', const SchoolInput(name: 'X')),
        throwsA(isA<MasterRecordNotFoundFailure>()),
      );
      await expectLater(
        repo.setActive('missing', active: false),
        throwsA(isA<MasterRecordNotFoundFailure>()),
      );
    });
  });

  group('search and filters', () {
    setUp(() async {
      await make('Test School Alpha', code: 'SYN-1001', district: 'District One', block: 'Block North');
      await make('test school beta', code: 'SYN-1002', district: 'District One', block: 'Block South');
      await make('Gamma 100% Model', code: 'SYN-2001', district: 'District Two', block: 'Block East');
      final inactive = await make('Delta_Inactive School', district: 'District Two');
      await repo.setActive(inactive.id, active: false);
    });

    Future<List<String>> names(MasterListQuery q) async =>
        (await repo.search(q)).map((s) => s.name).toList();

    test('lists active schools by default, sorted by name', () async {
      expect(await names(const MasterListQuery()), [
        'Gamma 100% Model',
        'Test School Alpha',
        'test school beta',
      ]);
    });

    test('searches the name case-insensitively (substring, no fuzzy match)',
        () async {
      expect(await names(const MasterListQuery(text: 'SCHOOL')), [
        'Test School Alpha',
        'test school beta',
      ]);
      expect(await names(const MasterListQuery(text: '  alpha ')), [
        'Test School Alpha',
      ]);
      expect(await names(const MasterListQuery(text: 'alfa')), isEmpty);
    });

    test('searches the official code', () async {
      expect(await names(const MasterListQuery(text: 'syn-1002')), [
        'test school beta',
      ]);
      expect(await names(const MasterListQuery(text: 'SYN-1')), [
        'Test School Alpha',
        'test school beta',
      ]);
    });

    test('takes % and _ literally', () async {
      expect(await names(const MasterListQuery(text: '100%')), [
        'Gamma 100% Model',
      ]);
      expect(await names(const MasterListQuery(text: '%')), [
        'Gamma 100% Model',
      ]);
      expect(
        await names(const MasterListQuery(text: '_', status: ActiveFilter.all)),
        ['Delta_Inactive School'],
      );
    });

    test('filters by district and block', () async {
      expect(await names(const MasterListQuery(district: 'District One')), [
        'Test School Alpha',
        'test school beta',
      ]);
      expect(
        await names(
          const MasterListQuery(district: 'District One', block: 'Block South'),
        ),
        ['test school beta'],
      );
    });

    test('filters Inactive and All', () async {
      expect(
        await names(const MasterListQuery(status: ActiveFilter.inactive)),
        ['Delta_Inactive School'],
      );
      expect(
        await names(const MasterListQuery(status: ActiveFilter.all)),
        hasLength(4),
      );
    });

    test('filter options are the distinct stored values only', () async {
      expect(await repo.districts(), ['District One', 'District Two']);
      expect(await repo.blocks(), ['Block East', 'Block North', 'Block South']);
      expect(await repo.blocks(district: 'District One'), [
        'Block North',
        'Block South',
      ]);
    });
  });

  group('soft-deleted rows', () {
    test('never appear in search, getById, filters or duplicate checks',
        () async {
      final school = await make('Test School Hidden', district: 'Hidden District');
      await (database.update(database.schools)
            ..where((s) => s.id.equals(school.id)))
          .write(const db.SchoolsCompanion(isDeleted: Value(true)));

      expect(await repo.search(const MasterListQuery(status: ActiveFilter.all)), isEmpty);
      expect(await repo.getById(school.id), isNull);
      expect(await repo.districts(), isEmpty);
      expect(
        await repo.possibleDuplicatesFor(const SchoolInput(name: 'Test School Hidden')),
        isEmpty,
      );
    });
  });

  group('possible duplicates (D4)', () {
    test('the same name after trimming, space-collapsing and case-folding, '
        'with a different code, is a possible duplicate', () async {
      final a = await make('Test  School   Alpha', code: 'SYN-0001');

      for (final variant in [
        'Test School Alpha',
        '  test school alpha  ',
        'TEST SCHOOL\tALPHA',
      ]) {
        final found = await repo.possibleDuplicatesFor(
          SchoolInput(name: variant, officialSchoolCode: 'SYN-0002'),
        );
        expect(found.map((s) => s.id), [a.id], reason: variant);
      }
    });

    test('one or both codes blank is still a possible duplicate', () async {
      final a = await make('Test School Alpha');
      expect(
        (await repo.possibleDuplicatesFor(
          const SchoolInput(name: 'Test School Alpha'),
        )).map((s) => s.id),
        [a.id],
      );
      expect(
        (await repo.possibleDuplicatesFor(
          const SchoolInput(name: 'Test School Alpha', officialSchoolCode: 'SYN-0009'),
        )).map((s) => s.id),
        [a.id],
      );
    });

    test('inactive schools are included', () async {
      final a = await make('Test School Alpha');
      await repo.setActive(a.id, active: false);
      expect(
        await repo.possibleDuplicatesFor(const SchoolInput(name: 'test school alpha')),
        hasLength(1),
      );
    });

    test('no fuzzy matching: similar spellings are not duplicates', () async {
      await make('Test School Lagaun');
      expect(
        await repo.possibleDuplicatesFor(const SchoolInput(name: 'Test School Lagon')),
        isEmpty,
      );
    });

    test('a school is never its own duplicate when edited', () async {
      final a = await make('Test School Alpha');
      expect(
        await repo.possibleDuplicatesFor(
          const SchoolInput(name: 'Test School Alpha'),
          excludeId: a.id,
        ),
        isEmpty,
      );
    });

    test('groups list every set of two or more matching schools; nothing '
        'is merged or changed', () async {
      final a = await make('Test School Alpha', code: 'SYN-0001');
      final b = await make('TEST SCHOOL ALPHA', code: 'SYN-0002');
      await make('Test School Beta');
      final before = await database.select(database.schools).get();

      final groups = await repo.possibleDuplicateGroups();

      expect(groups, hasLength(1));
      expect(groups.single.map((s) => s.id).toSet(), {a.id, b.id});
      expect(await database.select(database.schools).get(), before);
    });
  });

  group('audit (D1)', () {
    test('an insert writes exactly one audit row: table, record, action, '
        'values, and no actor', () async {
      final school = await make('Test School Alpha', code: 'SYN-0001');
      final rows = await audit();

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.businessTableName, 'schools');
      expect(row.recordId, school.id);
      expect(row.action, AuditAction.INSERT);
      expect(row.actorUserId, isNull);
      expect(row.changedFields, isNull);
      expect(row.oldValues, isNull);
      final values = jsonDecode(row.newValues!) as Map<String, dynamic>;
      expect(values['name'], 'Test School Alpha');
      expect(values['official_school_code'], 'SYN-0001');
      expect(values['is_active'], true);
    });

    test('an update writes exactly one audit row with only the changed '
        'fields', () async {
      final school = await make('Test School Alpha', code: 'SYN-0001');
      await repo.update(
        school.id,
        const SchoolInput(name: 'Test School Alpha', officialSchoolCode: 'SYN-0001', block: 'Test Block'),
      );

      final rows = await audit();
      expect(rows, hasLength(2));
      final row = rows.last;
      expect(row.action, AuditAction.UPDATE);
      expect(row.recordId, school.id);
      expect(row.actorUserId, isNull);
      expect(jsonDecode(row.changedFields!), ['block']);
      expect(jsonDecode(row.oldValues!), {'block': null});
      expect(jsonDecode(row.newValues!), {'block': 'Test Block'});
    });

    test('Active/Inactive changes are audited as updates', () async {
      final school = await make('Test School Alpha');
      await repo.setActive(school.id, active: false);

      final row = (await audit()).last;
      expect(row.action, AuditAction.UPDATE);
      expect(jsonDecode(row.changedFields!), ['is_active']);
      expect(jsonDecode(row.oldValues!), {'is_active': true});
      expect(jsonDecode(row.newValues!), {'is_active': false});
    });

    test('the change and its audit row are one transaction: if the audit '
        'write fails, the change is not saved either', () async {
      final failing = DriftSchoolRepository(database, audit: const _FailingAudit());

      await expectLater(
        failing.create(const SchoolInput(name: 'Test School Alpha')),
        throwsStateError,
      );
      expect(await database.select(database.schools).get(), isEmpty);

      final school = await make('Test School Beta');
      await expectLater(
        failing.update(school.id, const SchoolInput(name: 'Test School Gamma')),
        throwsStateError,
      );
      await expectLater(
        failing.setActive(school.id, active: false),
        throwsStateError,
      );
      final row = await raw(school.id);
      expect(row.name, 'Test School Beta');
      expect(row.isActive, isTrue);
      expect(row.rowVersion, 1);
      expect(await audit(), hasLength(1), reason: 'only the successful insert');
    });
  });
}
