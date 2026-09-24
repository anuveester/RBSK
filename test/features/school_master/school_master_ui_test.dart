import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/repositories/drift_school_repository.dart';
import 'package:referredline/domain/entities/master_list_query.dart';
import 'package:referredline/domain/entities/school.dart';
import 'package:referredline/features/school_master/presentation/screens/school_detail_screen.dart';
import 'package:referredline/features/school_master/presentation/screens/school_list_screen.dart';

import '../../support/master_app.dart';

// Synthetic names and codes only.
void main() {
  Future<void> addSchool(
    WidgetTester tester, {
    required String name,
    String code = '',
    String? type,
  }) async {
    await tester.tap(byKey('school-add'));
    await settle(tester, until: byKey('school-form-name'));
    await tester.enterText(byKey('school-form-name'), name);
    await tester.enterText(byKey('school-form-code'), code);
    if (type != null) {
      await tapVisible(tester, 'school-type-$type');
      await tester.pump();
    }
    await tapVisible(tester, 'school-form-save');
    await settle(tester);
  }

  Future<List<School>> stored(MasterApp app, WidgetTester tester) async =>
      (await tester.runAsync(
        () => DriftSchoolRepository(app.db)
            .search(const MasterListQuery(status: ActiveFilter.all)),
      ))!;

  testWidgets('More → School Master opens an empty list with Add and '
      'Possible duplicates', (tester) async {
    final app = MasterApp();
    await app.launch(tester);
    await openMaster(tester, 'more-schools');

    expect(find.byType(SchoolListScreen), findsOneWidget);
    expect(byKey('school-list-empty'), findsOneWidget);
    expect(byKey('school-add'), findsOneWidget);
    expect(byKey('school-duplicates'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('add a school with a blank code: it is saved, shows "No code", '
      'and the institution type offers exactly PS, UPS, COM and Blank',
      (tester) async {
    final app = MasterApp();
    await app.launch(tester);
    await openMaster(tester, 'more-schools');
    await tester.tap(byKey('school-add'));
    await settle(tester, until: byKey('school-form-name'));

    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((c) => (c.label as Text).data)
        .toList();
    expect(chips, ['PS', 'UPS', 'COM', 'Blank']);

    await tester.enterText(byKey('school-form-name'), 'Test School Alpha');
    await tapVisible(tester, 'school-type-UPS');
    await tester.pump();
    await tapVisible(tester, 'school-form-save');
    await settle(tester, until: find.byType(SchoolDetailScreen));

    expect(find.text('Test School Alpha'), findsWidgets);
    expect(find.text('No code'), findsOneWidget);
    final schools = await stored(app, tester);
    expect(schools.single.officialSchoolCode, isNull);
    expect(schools.single.institutionType, 'UPS');
    await app.dispose(tester);
  });

  testWidgets('a name is required', (tester) async {
    final app = MasterApp();
    await app.launch(tester);
    await openMaster(tester, 'more-schools');
    await tester.tap(byKey('school-add'));
    await settle(tester, until: byKey('school-form-name'));
    await tapVisible(tester, 'school-form-save');
    await tester.pump();

    expect(find.text('Please enter the name.'), findsOneWidget);
    expect(await stored(app, tester), isEmpty);
    await app.dispose(tester);
  });

  testWidgets('a school code already used cannot be saved; the message is '
      'plain', (tester) async {
    final app = MasterApp();
    await tester.runAsync(
      () => DriftSchoolRepository(app.db).create(
        const SchoolInput(name: 'Test School Alpha', officialSchoolCode: 'SYN-0001'),
      ),
    );
    await app.launch(tester);
    await openMaster(tester, 'more-schools');
    await addSchool(tester, name: 'Test School Other', code: 'SYN-0001');

    final error = tester.widget<Text>(byKey('school-form-error')).data!;
    expect(error, contains('School Code already exists'));
    expect(error, contains('Test School Alpha'));
    expect(error, isNot(contains('UNIQUE')));
    expect(await stored(app, tester), hasLength(1));
    await app.dispose(tester);
  });

  testWidgets('the same name shows "Possible duplicate found": Cancel saves '
      'nothing, Save anyway saves a separate school', (tester) async {
    final app = MasterApp();
    await tester.runAsync(
      () => DriftSchoolRepository(app.db).create(
        const SchoolInput(name: 'Test School Alpha', officialSchoolCode: 'SYN-0001'),
      ),
    );
    await app.launch(tester);
    await openMaster(tester, 'more-schools');

    await addSchool(tester, name: '  test  school alpha ', code: 'SYN-0002');
    expect(byKey('possible-duplicate-dialog'), findsOneWidget);
    expect(find.text('Possible duplicate found'), findsOneWidget);
    expect(find.text('Code: SYN-0001'), findsOneWidget);
    await tester.tap(byKey('duplicate-cancel'));
    await settle(tester);
    expect(await stored(app, tester), hasLength(1));

    await tapVisible(tester, 'school-form-save');
    await settle(tester, until: byKey('possible-duplicate-dialog'));
    await tester.tap(byKey('duplicate-save-anyway'));
    await settle(tester, until: find.byType(SchoolDetailScreen));
    expect(await stored(app, tester), hasLength(2), reason: 'never merged');
    await app.dispose(tester);
  });

  testWidgets('search, district filter and status filter narrow the list',
      (tester) async {
    final app = MasterApp();
    await tester.runAsync(() async {
      final repo = DriftSchoolRepository(app.db);
      await repo.create(const SchoolInput(name: 'Test School Alpha', officialSchoolCode: 'SYN-0001', district: 'District One'));
      await repo.create(const SchoolInput(name: 'Test School Beta', district: 'District Two'));
      final gamma = await repo.create(const SchoolInput(name: 'Test School Gamma'));
      await repo.setActive(gamma.id, active: false);
    });
    await app.launch(tester);
    await openMaster(tester, 'more-schools');

    expect(find.text('Test School Alpha'), findsOneWidget);
    expect(find.text('Test School Beta'), findsOneWidget);
    expect(find.text('Test School Gamma'), findsNothing, reason: 'inactive');

    await tester.enterText(byKey('master-search'), 'syn-0001');
    await settle(tester);
    expect(find.text('Test School Alpha'), findsOneWidget);
    expect(find.text('Test School Beta'), findsNothing);
    await tester.enterText(byKey('master-search'), '');
    await settle(tester);

    await tester.tap(byKey('master-filter-district'));
    await settle(tester);
    await tester.tap(find.text('District Two').last);
    await settle(tester);
    expect(find.text('Test School Beta'), findsOneWidget);
    expect(find.text('Test School Alpha'), findsNothing);

    await tester.tap(find.text('Inactive'));
    await settle(tester);
    expect(byKey('school-list-empty'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('edit a school, then mark it inactive and active again; there '
      'is no delete action anywhere', (tester) async {
    final app = MasterApp();
    await tester.runAsync(
      () => DriftSchoolRepository(app.db).create(
        const SchoolInput(name: 'Test School Alpha'),
      ),
    );
    await app.launch(tester);
    await openMaster(tester, 'more-schools');
    await tester.tap(find.text('Test School Alpha'));
    await settle(tester, until: find.byType(SchoolDetailScreen));
    expect(find.textContaining('Delete'), findsNothing);
    expect(find.byIcon(Icons.delete), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    await tapVisible(tester, 'school-edit');
    await settle(tester, until: byKey('school-form-name'));
    expect(find.textContaining('Delete'), findsNothing);
    await tester.enterText(byKey('school-form-name'), 'Test School Alpha Two');
    await tapVisible(tester, 'school-form-save');
    await settle(tester, until: byKey('school-detail-name'));
    expect(
      tester.widget<Text>(byKey('school-detail-name')).data,
      'Test School Alpha Two',
    );

    await tapVisible(tester, 'school-active-switch');
    await settle(tester, until: byKey('active-change-confirm'));
    await tester.tap(byKey('active-change-confirm'));
    await settle(tester);
    expect(find.text('Inactive'), findsOneWidget);
    expect((await stored(app, tester)).single.isActive, isFalse);

    await tapVisible(tester, 'school-active-switch');
    await settle(tester, until: byKey('active-change-confirm'));
    await tester.tap(byKey('active-change-confirm'));
    await settle(tester);
    final school = (await stored(app, tester)).single;
    expect(school.isActive, isTrue);
    expect(school.name, 'Test School Alpha Two');
    await app.dispose(tester);
  });

  testWidgets('the Possible duplicates screen lists same-name schools and '
      'offers no merge or delete', (tester) async {
    final app = MasterApp();
    await tester.runAsync(() async {
      final repo = DriftSchoolRepository(app.db);
      await repo.create(const SchoolInput(name: 'Test School Alpha', officialSchoolCode: 'SYN-0001'));
      await repo.create(const SchoolInput(name: 'TEST SCHOOL ALPHA'));
    });
    await app.launch(tester);
    await openMaster(tester, 'more-schools');
    await tester.tap(byKey('school-duplicates'));
    await settle(tester, until: byKey('school-duplicate-group'));

    expect(byKey('school-duplicate-group'), findsOneWidget);
    expect(find.text('No code'), findsOneWidget);
    expect(find.textContaining('Merge'), findsNothing);
    expect(find.textContaining('Delete'), findsNothing);
    await app.dispose(tester);
  });
}
