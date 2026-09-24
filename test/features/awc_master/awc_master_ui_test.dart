import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart' as db;
import 'package:referredline/data/repositories/drift_awc_repository.dart';
import 'package:referredline/domain/entities/awc.dart';
import 'package:referredline/domain/entities/master_list_query.dart';
import 'package:referredline/features/awc_master/presentation/screens/awc_detail_screen.dart';
import 'package:referredline/features/awc_master/presentation/screens/awc_list_screen.dart';

import '../../support/master_app.dart';

// Synthetic names, villages and codes only.
void main() {
  Future<List<Awc>> stored(MasterApp app, WidgetTester tester) async =>
      (await tester.runAsync(
        () => DriftAwcRepository(app.db)
            .search(const MasterListQuery(status: ActiveFilter.all)),
      ))!;

  Future<void> fillAndSave(
    WidgetTester tester, {
    required String name,
    String village = '',
    String subcentre = '',
    String code = '',
  }) async {
    await tester.tap(byKey('awc-add'));
    await settle(tester, until: byKey('awc-form-name'));
    await tester.enterText(byKey('awc-form-name'), name);
    await tester.enterText(byKey('awc-form-village'), village);
    await tester.enterText(byKey('awc-form-subcentre'), subcentre);
    await tester.enterText(byKey('awc-form-code'), code);
    await tapVisible(tester, 'awc-form-save');
    await settle(tester);
  }

  testWidgets('More → AWC Master opens an empty list with Add and Possible '
      'duplicates', (tester) async {
    final app = MasterApp();
    await app.launch(tester);
    await openMaster(tester, 'more-awcs');

    expect(find.byType(AwcListScreen), findsOneWidget);
    expect(byKey('awc-list-empty'), findsOneWidget);
    expect(byKey('awc-add'), findsOneWidget);
    expect(byKey('awc-duplicates'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('add an AWC with a blank code: saved, shows "No code", and the '
      'form has no Micro Plan code field', (tester) async {
    final app = MasterApp();
    await app.launch(tester);
    await openMaster(tester, 'more-awcs');
    await tester.tap(byKey('awc-add'));
    await settle(tester, until: byKey('awc-form-name'));
    expect(find.textContaining('Micro Plan'), findsNothing);

    await tester.enterText(byKey('awc-form-name'), 'Test AWC Alpha');
    await tester.enterText(byKey('awc-form-village'), 'Test Village One');
    await tester.enterText(byKey('awc-form-subcentre'), '2');
    await tapVisible(tester, 'awc-form-save');
    await settle(tester, until: find.byType(AwcDetailScreen));

    expect(
      tester.widget<Text>(byKey('awc-detail-name')).data,
      'Test AWC Alpha',
    );
    expect(find.text('No code'), findsOneWidget);
    final awc = (await stored(app, tester)).single;
    expect(awc.officialAwcCode, isNull);
    expect(awc.sourcePlanAwcCode, isNull);
    expect(awc.subcentreNo, 2);
    expect(awc.panchayatVillage, 'Test Village One');
    await app.dispose(tester);
  });

  testWidgets('an official AWC code already used cannot be saved', (
    tester,
  ) async {
    final app = MasterApp();
    await tester.runAsync(
      () => DriftAwcRepository(app.db).create(
        const AwcInput(name: 'Test AWC Alpha', officialAwcCode: 'SYN-AWC-01'),
      ),
    );
    await app.launch(tester);
    await openMaster(tester, 'more-awcs');
    await fillAndSave(tester, name: 'Test AWC Other', code: 'SYN-AWC-01');

    final error = tester.widget<Text>(byKey('awc-form-error')).data!;
    expect(error, contains('AWC Code already exists'));
    expect(error, isNot(contains('UNIQUE')));
    expect(await stored(app, tester), hasLength(1));
    await app.dispose(tester);
  });

  testWidgets('the same name + village + subcentre shows "Possible duplicate '
      'found"; a different subcentre does not', (tester) async {
    final app = MasterApp();
    await tester.runAsync(
      () => DriftAwcRepository(app.db).create(
        const AwcInput(
          name: 'Test AWC Alpha',
          panchayatVillage: 'Test Village One',
          subcentreNo: 1,
        ),
      ),
    );
    await app.launch(tester);
    await openMaster(tester, 'more-awcs');

    await fillAndSave(
      tester,
      name: ' test awc  ALPHA ',
      village: 'test village one',
      subcentre: '1',
    );
    expect(byKey('possible-duplicate-dialog'), findsOneWidget);
    await tester.tap(byKey('duplicate-cancel'));
    await settle(tester);
    expect(await stored(app, tester), hasLength(1));

    await tester.enterText(byKey('awc-form-subcentre'), '2');
    await tapVisible(tester, 'awc-form-save');
    await settle(tester, until: find.byType(AwcDetailScreen));
    expect(byKey('possible-duplicate-dialog'), findsNothing);
    expect(await stored(app, tester), hasLength(2));
    await app.dispose(tester);
  });

  testWidgets('Save anyway keeps both AWCs (never merged)', (tester) async {
    final app = MasterApp();
    await tester.runAsync(
      () => DriftAwcRepository(
        app.db,
      ).create(const AwcInput(name: 'Test AWC Alpha')),
    );
    await app.launch(tester);
    await openMaster(tester, 'more-awcs');
    await fillAndSave(tester, name: 'TEST AWC ALPHA');
    expect(byKey('possible-duplicate-dialog'), findsOneWidget);
    await tester.tap(byKey('duplicate-save-anyway'));
    await settle(tester, until: find.byType(AwcDetailScreen));
    expect(await stored(app, tester), hasLength(2));
    await app.dispose(tester);
  });

  testWidgets('search finds an AWC by village; the status filter shows '
      'inactive AWCs', (tester) async {
    final app = MasterApp();
    await tester.runAsync(() async {
      final repo = DriftAwcRepository(app.db);
      await repo.create(
        const AwcInput(
          name: 'Test AWC Alpha',
          panchayatVillage: 'Test Village One',
        ),
      );
      await repo.create(
        const AwcInput(
          name: 'Test AWC Beta',
          panchayatVillage: 'Test Village Two',
        ),
      );
      final gamma = await repo.create(const AwcInput(name: 'Test AWC Gamma'));
      await repo.setActive(gamma.id, active: false);
    });
    await app.launch(tester);
    await openMaster(tester, 'more-awcs');

    expect(find.text('Test AWC Alpha'), findsOneWidget);
    expect(find.text('Test AWC Beta'), findsOneWidget);
    expect(find.text('Test AWC Gamma'), findsNothing);

    await tester.enterText(byKey('master-search'), 'village two');
    await settle(tester);
    expect(find.text('Test AWC Beta'), findsOneWidget);
    expect(find.text('Test AWC Alpha'), findsNothing);
    await tester.enterText(byKey('master-search'), '');
    await settle(tester);

    await tester.tap(find.text('Inactive'));
    await settle(tester);
    expect(find.text('Test AWC Gamma'), findsOneWidget);
    expect(find.text('Test AWC Alpha'), findsNothing);

    await tester.tap(find.text('All'));
    await settle(tester);
    expect(find.text('Test AWC Alpha'), findsOneWidget);
    expect(find.text('Test AWC Gamma'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('the Micro Plan code is shown read-only as reference, kept on '
      'edit, and there is no delete; Active/Inactive works', (tester) async {
    final app = MasterApp();
    final id = (await tester.runAsync(() async {
      final awc = await DriftAwcRepository(
        app.db,
      ).create(const AwcInput(name: 'Test AWC Alpha'));
      await (app.db.update(app.db.awcs)..where((a) => a.id.equals(awc.id)))
          .write(
            const db.AwcsCompanion(sourcePlanAwcCode: Value('PLAN-SYN-7')),
          );
      return awc.id;
    }))!;
    await app.launch(tester);
    await openMaster(tester, 'more-awcs');
    await tester.tap(find.text('Test AWC Alpha'));
    await settle(tester, until: find.byType(AwcDetailScreen));

    expect(byKey('awc-reference-section'), findsOneWidget);
    expect(find.text('PLAN-SYN-7'), findsOneWidget);
    expect(
      find.text('No code'),
      findsOneWidget,
      reason: 'the Micro Plan code is not the official code',
    );
    expect(find.textContaining('Delete'), findsNothing);
    expect(find.byIcon(Icons.delete), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    await tapVisible(tester, 'awc-edit');
    await settle(tester, until: byKey('awc-form-name'));
    expect(find.text('PLAN-SYN-7'), findsNothing, reason: 'not editable');
    expect(find.textContaining('Delete'), findsNothing);
    await tester.enterText(byKey('awc-form-name'), 'Test AWC Alpha Two');
    await tapVisible(tester, 'awc-form-save');
    await settle(tester, until: byKey('awc-detail-name'));
    expect(
      tester.widget<Text>(byKey('awc-detail-name')).data,
      'Test AWC Alpha Two',
    );

    await tapVisible(tester, 'awc-active-switch');
    await settle(tester, until: byKey('active-change-confirm'));
    await tester.tap(byKey('active-change-confirm'));
    await settle(tester);
    expect(find.text('Inactive'), findsOneWidget);
    var awc = (await stored(app, tester)).single;
    expect(awc.isActive, isFalse);

    await tapVisible(tester, 'awc-active-switch');
    await settle(tester, until: byKey('active-change-confirm'));
    await tester.tap(byKey('active-change-confirm'));
    await settle(tester);
    awc = (await stored(app, tester)).single;
    expect(awc.id, id);
    expect(awc.isActive, isTrue);
    expect(awc.name, 'Test AWC Alpha Two');
    expect(awc.sourcePlanAwcCode, 'PLAN-SYN-7');
    await app.dispose(tester);
  });

  testWidgets('the Possible duplicates screen groups AWCs by name, village '
      'and subcentre, with no merge or delete', (tester) async {
    final app = MasterApp();
    await tester.runAsync(() async {
      final repo = DriftAwcRepository(app.db);
      await repo.create(
        const AwcInput(
          name: 'Test AWC Alpha',
          panchayatVillage: 'Test Village One',
        ),
      );
      await repo.create(
        const AwcInput(
          name: 'test awc alpha',
          panchayatVillage: 'TEST VILLAGE ONE',
        ),
      );
      await repo.create(
        const AwcInput(
          name: 'Test AWC Alpha',
          panchayatVillage: 'Test Village Two',
        ),
      );
    });
    await app.launch(tester);
    await openMaster(tester, 'more-awcs');
    await tester.tap(byKey('awc-duplicates'));
    await settle(tester, until: byKey('awc-duplicate-group'));

    expect(byKey('awc-duplicate-group'), findsOneWidget);
    expect(find.textContaining('Merge'), findsNothing);
    expect(find.textContaining('Delete'), findsNothing);
    await app.dispose(tester);
  });
}
