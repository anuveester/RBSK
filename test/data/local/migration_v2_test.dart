import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/enums.dart';

/// `plan_imports` exactly as schema version 1 created it: `imported_by`
/// NOT NULL. Used to build a real version-1 database file on disk.
const String _v1PlanImportsDdl =
    'CREATE TABLE "plan_imports" ('
    '"id" TEXT NOT NULL, '
    '"financial_year_id" TEXT NOT NULL REFERENCES financial_years (id), '
    '"source_filename" TEXT NOT NULL, '
    '"imported_by" TEXT NOT NULL REFERENCES users (id), '
    '"imported_at" TEXT NOT NULL, '
    '"row_count" INTEGER NULL, '
    '"notes" TEXT NULL, '
    'PRIMARY KEY ("id"))';

Future<bool> _importedByIsNotNull(AppDatabase db) async {
  final columns = await db
      .customSelect('PRAGMA table_info(plan_imports)')
      .get();
  final importedBy = columns.singleWhere(
    (c) => c.read<String>('name') == 'imported_by',
  );
  return importedBy.read<int>('notnull') == 1;
}

Future<int> _userVersion(AppDatabase db) =>
    db.customSelect('PRAGMA user_version').getSingle().then(
      (r) => r.read<int>('user_version'),
    );

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rbsk_migration_v2_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('a new database allows a plan import with no importer', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.financialYears).insert(
      FinancialYearsCompanion.insert(
        id: 'fy-1',
        label: '2025-26',
        startDate: DateTime.utc(2025, 4, 1),
        endDate: DateTime.utc(2026, 3, 31),
      ),
    );
    await db.into(db.planImports).insert(
      PlanImportsCompanion.insert(
        id: 'import-1',
        financialYearId: 'fy-1',
        sourceFilename: 'PLAN_25-26-B.xlsx',
      ),
    );

    final row = await db.select(db.planImports).getSingle();
    expect(row.importedBy, isNull);
    expect(await _importedByIsNotNull(db), isFalse);
  });

  test('upgrading a version-1 file keeps every row and makes imported_by '
      'nullable', () async {
    final file = File('${tempDir.path}/v1.sqlite');

    // Build a genuine version-1 file: current schema, then plan_imports put
    // back to its v1 shape with one row in it, and user_version set to 1.
    final v1 = AppDatabase(NativeDatabase(file));
    await v1.into(v1.financialYears).insert(
      FinancialYearsCompanion.insert(
        id: 'fy-1',
        label: '2025-26',
        startDate: DateTime.utc(2025, 4, 1),
        endDate: DateTime.utc(2026, 3, 31),
      ),
    );
    await v1.into(v1.users).insert(
      UsersCompanion.insert(
        id: 'user-1',
        displayName: 'Earlier importer',
        role: AppRole.ADMIN,
      ),
    );
    await v1.customStatement('PRAGMA foreign_keys = OFF');
    await v1.customStatement('DROP TABLE plan_imports');
    await v1.customStatement(_v1PlanImportsDdl);
    await v1.customStatement(
      'INSERT INTO plan_imports (id, financial_year_id, source_filename, '
      "imported_by, imported_at, row_count, notes) VALUES ('import-1', "
      "'fy-1', 'PLAN_25-26-B.xlsx', 'user-1', '2025-04-01T00:00:00.000Z', "
      "469, 'kept across the upgrade')",
    );
    await v1.customStatement('PRAGMA user_version = 1');
    expect(await _importedByIsNotNull(v1), isTrue);
    await v1.close();

    // Opening it with the current app runs the version-2 upgrade step.
    final v2 = AppDatabase(NativeDatabase(file));
    addTearDown(v2.close);

    expect(await _userVersion(v2), 2);
    expect(await _importedByIsNotNull(v2), isFalse);

    final kept = await v2.select(v2.planImports).getSingle();
    expect(kept.id, 'import-1');
    expect(kept.importedBy, 'user-1');
    expect(
      kept.importedAt.isAtSameMomentAs(DateTime.utc(2025, 4, 1)),
      isTrue,
    );
    expect(kept.rowCount, 469);
    expect(kept.notes, 'kept across the upgrade');

    await v2.into(v2.planImports).insert(
      PlanImportsCompanion.insert(
        id: 'import-2',
        financialYearId: 'fy-1',
        sourceFilename: 'PLAN_25-26-B.xlsx',
      ),
    );
    expect(await v2.select(v2.planImports).get(), hasLength(2));

    final brokenReferences = await v2
        .customSelect('PRAGMA foreign_key_check')
        .get();
    expect(brokenReferences, isEmpty);
  });
}
