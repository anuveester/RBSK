import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/rbac/more_menu_items.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/data/local/enums.dart';

List<String> _labels(AppRole role) =>
    moreMenuItemsFor(role).map((i) => i.label).toList();

void main() {
  test('ADMIN sees the Admin-only entries (docs/04 §3: users manage, '
      'backup export / audit log are ADMIN only)', () {
    expect(_labels(AppRole.ADMIN), [
      'Admin Recovery Code',
      'Backup Export',
      'Audit Log',
    ]);
  });

  test('the recovery-code and backup entries open Admin-only routes; the '
      'audit log is still an inert label', () {
    final items = {for (final i in moreMenuItemsFor(AppRole.ADMIN)) i.label: i.route};
    expect(items['Admin Recovery Code'], Routes.moreRecoveryCode);
    expect(items['Backup Export'], Routes.moreBackup);
    expect(items['Audit Log'], isNull);
    expect(
      Routes.adminOnly,
      containsAll([Routes.moreRecoveryCode, Routes.moreBackup]),
    );
  });

  test('MEDICAL_OFFICER sees no Admin-only entries', () {
    expect(_labels(AppRole.MEDICAL_OFFICER), isEmpty);
  });

  test('TEAM_MEMBER sees no Admin-only entries', () {
    expect(_labels(AppRole.TEAM_MEMBER), isEmpty);
  });

  test('covers exactly the three roles in the existing AppRole enum', () {
    expect(AppRole.values, [
      AppRole.ADMIN,
      AppRole.MEDICAL_OFFICER,
      AppRole.TEAM_MEMBER,
    ]);
  });
}
