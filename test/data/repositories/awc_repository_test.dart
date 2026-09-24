import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/data/local/app_database.dart' as db;
import 'package:referredline/data/local/audit/business_audit_writer.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/repositories/drift_awc_repository.dart';
import 'package:referredline/domain/entities/awc.dart';
import 'package:referredline/domain/entities/master_list_query.dart';

import '../local/test_database.dart';

// Synthetic names and codes only.
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
  late DriftAwcRepository repo;

  setUp(() {
    database = openTestDatabase();
    repo = DriftAwcRepository(database);
  });
  tearDown(() => database.close());

  Future<List<db.AuditLogData>> audit() => (database.select(
    database.auditLog,
  )..orderBy([(a) => OrderingTerm.asc(a.occurredAt)])).get();

  Future<db.Awc> raw(String id) =>
      (database.select(database.awcs)..where((a) => a.id.equals(id))).getSingle();

  Future<Awc> make(
    String name, {
    String? village,
    int? subcentre,
    String? code,
    String? district,
    String? block,
  }) => repo.create(
    AwcInput(
      name: name,
      panchayatVillage: village,
      subcentreNo: subcentre,
      officialAwcCode: code,
      district: district,
      block: block,
    ),
  );

  test('creates with trimmed fields, no invented codes, row_version 1, and '
      'no user attribution', () async {
    final awc = await make(
      '  Test AWC One ',
      village: ' Test Village ',
      subcentre: 2,
      district: 'Test District',
    );
    expect(awc.name, 'Test AWC One');
    expect(awc.panchayatVillage, 'Test Village');
    expect(awc.subcentreNo, 2);
    expect(awc.officialAwcCode, isNull);
    expect(awc.sourcePlanAwcCode, isNull);
    expect(awc.rowVersion, 1);
    final row = await raw(awc.id);
    expect(row.createdBy, isNull);
    expect(row.updatedBy, isNull);
    expect((await repo.getById(awc.id))!.name, 'Test AWC One');
  });

  test('a name is required', () async {
    await expectLater(
      repo.create(const AwcInput(name: ' ')),
      throwsA(isA<NameRequiredFailure>()),
    );
  });

  test('blank official AWC codes are allowed repeatedly; a duplicate '
      'non-blank code is blocked', () async {
    await make('Test AWC One', code: '');
    await make('Test AWC Two');
    await make('Test AWC Three', code: 'SYN-AWC-1');
    await expectLater(
      make('Test AWC Four', code: 'SYN-AWC-1'),
      throwsA(
        isA<DuplicateOfficialCodeFailure>().having(
          (f) => f.message,
          'message',
          allOf(contains('AWC Code already exists'), contains('Test AWC Three')),
        ),
      ),
    );
    expect(await database.select(database.awcs).get(), hasLength(3));
  });

  test('the Micro Plan AWC code is not unique and is never written by '
      'manual edits', () async {
    final a = await make('Test AWC One');
    final b = await make('Test AWC Two');
    // As the Phase 1.6 import would store it: the same number on both.
    for (final id in [a.id, b.id]) {
      await (database.update(database.awcs)..where((r) => r.id.equals(id)))
          .write(const db.AwcsCompanion(sourcePlanAwcCode: Value('7')));
    }

    final edited = await repo.update(
      a.id,
      const AwcInput(name: 'Test AWC One Edited'),
    );

    expect(edited.sourcePlanAwcCode, '7');
    expect((await repo.getById(b.id))!.sourcePlanAwcCode, '7');
  });

  test('an edit writes only what changed and advances row_version; no '
      'change writes nothing', () async {
    final awc = await make('Test AWC One', village: 'Test Village');
    final auditBefore = (await audit()).length;

    final same = await repo.update(
      awc.id,
      const AwcInput(name: 'Test AWC One', panchayatVillage: ' Test Village '),
    );
    expect(same.rowVersion, 1);
    expect(await audit(), hasLength(auditBefore));

    final changed = await repo.update(
      awc.id,
      const AwcInput(name: 'Test AWC One', panchayatVillage: 'Test Village', subcentreNo: 3),
    );
    expect(changed.subcentreNo, 3);
    expect(changed.rowVersion, 2);
  });

  test('deactivate and reactivate keep the record stored', () async {
    final awc = await make('Test AWC One');
    expect((await repo.setActive(awc.id, active: false)).isActive, isFalse);
    expect(await database.select(database.awcs).get(), hasLength(1));
    final back = await repo.setActive(awc.id, active: true);
    expect(back.isActive, isTrue);
    expect(back.rowVersion, 3);
  });

  group('search and filters', () {
    setUp(() async {
      await make('Test AWC Alpha', village: 'Village North', code: 'SYN-AWC-7', district: 'District One', block: 'Block A');
      await make('Test AWC Beta', village: 'Village South', district: 'District One', block: 'Block B');
      final c = await make('Test AWC Gamma', village: 'Village North', district: 'District Two', block: 'Block C');
      await repo.setActive(c.id, active: false);
    });

    Future<List<String>> names(MasterListQuery q) async =>
        (await repo.search(q)).map((a) => a.name).toList();

    test('searches name, official code and village, case-insensitively',
        () async {
      expect(await names(const MasterListQuery(text: 'alpha')), ['Test AWC Alpha']);
      expect(await names(const MasterListQuery(text: 'syn-awc-7')), ['Test AWC Alpha']);
      expect(await names(const MasterListQuery(text: 'VILLAGE NORTH')), ['Test AWC Alpha']);
      expect(
        await names(const MasterListQuery(text: 'village north', status: ActiveFilter.all)),
        ['Test AWC Alpha', 'Test AWC Gamma'],
      );
    });

    test('filters by district, block and Active/Inactive/All', () async {
      expect(await names(const MasterListQuery(district: 'District One')), [
        'Test AWC Alpha',
        'Test AWC Beta',
      ]);
      expect(await names(const MasterListQuery(block: 'Block B')), ['Test AWC Beta']);
      expect(
        await names(const MasterListQuery(status: ActiveFilter.inactive)),
        ['Test AWC Gamma'],
      );
      expect(await names(const MasterListQuery(status: ActiveFilter.all)), hasLength(3));
      expect(await repo.districts(), ['District One', 'District Two']);
      expect(await repo.blocks(district: 'District Two'), ['Block C']);
    });
  });

  group('possible duplicates (D4)', () {
    test('same normalized name + village + subcentre is a possible '
        'duplicate', () async {
      final a = await make('Test  AWC', village: 'Test   Village', subcentre: 1);
      final found = await repo.possibleDuplicatesFor(
        const AwcInput(name: ' test awc ', panchayatVillage: 'TEST VILLAGE', subcentreNo: 1),
      );
      expect(found.map((x) => x.id), [a.id]);
    });

    test('a different subcentre or village is not a duplicate', () async {
      await make('Test AWC', village: 'Test Village', subcentre: 1);
      expect(
        await repo.possibleDuplicatesFor(
          const AwcInput(name: 'Test AWC', panchayatVillage: 'Test Village', subcentreNo: 2),
        ),
        isEmpty,
      );
      expect(
        await repo.possibleDuplicatesFor(
          const AwcInput(name: 'Test AWC', panchayatVillage: 'Other Village', subcentreNo: 1),
        ),
        isEmpty,
      );
    });

    test('a blank village matches a blank village; a blank subcentre '
        'matches a blank subcentre', () async {
      final a = await make('Test AWC');
      expect(
        (await repo.possibleDuplicatesFor(const AwcInput(name: 'test awc'))).map((x) => x.id),
        [a.id],
      );
      expect(
        await repo.possibleDuplicatesFor(const AwcInput(name: 'Test AWC', subcentreNo: 1)),
        isEmpty,
      );
    });

    test('inactive AWCs are included; an AWC is never its own duplicate',
        () async {
      final a = await make('Test AWC', village: 'Test Village');
      await repo.setActive(a.id, active: false);
      expect(
        await repo.possibleDuplicatesFor(const AwcInput(name: 'Test AWC', panchayatVillage: 'Test Village')),
        hasLength(1),
      );
      expect(
        await repo.possibleDuplicatesFor(
          const AwcInput(name: 'Test AWC', panchayatVillage: 'Test Village'),
          excludeId: a.id,
        ),
        isEmpty,
      );
    });

    test('no fuzzy matching', () async {
      await make('Test AWC Jakhaura', subcentre: 2);
      expect(
        await repo.possibleDuplicatesFor(const AwcInput(name: 'Test AWC Jakhora', subcentreNo: 2)),
        isEmpty,
      );
    });

    test('groups list matching AWCs; nothing is merged', () async {
      final a = await make('Test AWC', village: 'Test Village', subcentre: 1);
      final b = await make('TEST AWC', village: 'test village', subcentre: 1);
      await make('Test AWC', village: 'Test Village', subcentre: 2);

      final groups = await repo.possibleDuplicateGroups();
      expect(groups, hasLength(1));
      expect(groups.single.map((x) => x.id).toSet(), {a.id, b.id});
      expect(await database.select(database.awcs).get(), hasLength(3));
    });
  });

  group('audit (D1)', () {
    test('one audit row per insert and per update, with no actor', () async {
      final awc = await make('Test AWC', subcentre: 1);
      await repo.update(awc.id, const AwcInput(name: 'Test AWC', subcentreNo: 2));
      await repo.setActive(awc.id, active: false);

      final rows = await audit();
      expect(rows.map((r) => r.action), [
        AuditAction.INSERT,
        AuditAction.UPDATE,
        AuditAction.UPDATE,
      ]);
      expect(rows.every((r) => r.businessTableName == 'awcs'), isTrue);
      expect(rows.every((r) => r.recordId == awc.id), isTrue);
      expect(rows.every((r) => r.actorUserId == null), isTrue);
      expect(jsonDecode(rows[0].newValues!)['subcentre_no'], 1);
      expect(jsonDecode(rows[1].changedFields!), ['subcentre_no']);
      expect(jsonDecode(rows[1].oldValues!), {'subcentre_no': 1});
      expect(jsonDecode(rows[1].newValues!), {'subcentre_no': 2});
      expect(jsonDecode(rows[2].newValues!), {'is_active': false});
    });

    test('the change and its audit row are one transaction', () async {
      final failing = DriftAwcRepository(database, audit: const _FailingAudit());
      await expectLater(
        failing.create(const AwcInput(name: 'Test AWC')),
        throwsStateError,
      );
      expect(await database.select(database.awcs).get(), isEmpty);

      final awc = await make('Test AWC');
      await expectLater(
        failing.update(awc.id, const AwcInput(name: 'Renamed AWC')),
        throwsStateError,
      );
      expect((await raw(awc.id)).name, 'Test AWC');
      expect(await audit(), hasLength(1));
    });
  });
}
