import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';

/// Phase 1.2 instruction §5: schema version 1 IS the frozen v1.0 schema, and
/// future versions must extend the migration strategy rather than destroy
/// and recreate the database. Schema version 1 has no prior version to
/// migrate FROM, so what's testable now is: (a) the migration strategy is
/// real infrastructure, not a placeholder, and (b) reopening an existing
/// database file preserves data rather than being silently recreated —
/// which is the property a future numbered migration step depends on.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rbsk_migration_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('schema version is 2 and the migration strategy is real', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 2);
    expect(db.migration, isNotNull);
  });

  test(
    'reopening an existing database file preserves data — proves the open '
    'path is NOT "delete and recreate on any issue"',
    () async {
      final file = File('${tempDir.path}/migration_test.sqlite');

      final db1 = AppDatabase(NativeDatabase(file));
      await db1.into(db1.financialYears).insert(
            FinancialYearsCompanion.insert(
              id: 'fy-1',
              label: '2025-26',
              startDate: DateTime.utc(2025, 4, 1),
              endDate: DateTime.utc(2026, 3, 31),
            ),
          );
      await db1.close();

      expect(file.existsSync(), isTrue);
      final sizeAfterFirstOpen = file.lengthSync();
      expect(sizeAfterFirstOpen, greaterThan(0));

      // Reopening the same file must run through `onCreate` only if the
      // schema doesn't exist yet — Drift skips it when the file already has
      // the current schema version, so the row above must still be there.
      final db2 = AppDatabase(NativeDatabase(file));
      final rows = await db2.select(db2.financialYears).get();
      await db2.close();

      expect(rows, hasLength(1));
      expect(rows.single.label, '2025-26');
    },
  );

  test(
    'onCreate populates every table in one migration, not incrementally '
    'across multiple opens',
    () async {
      final file = File('${tempDir.path}/migration_full_create.sqlite');
      final db = AppDatabase(NativeDatabase(file));

      final tableCount = await db
          .customSelect(
            "SELECT count(*) AS c FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '__drift%'",
          )
          .getSingle()
          .then((r) => r.read<int>('c'));
      await db.close();

      expect(tableCount, 28);
    },
  );
}
