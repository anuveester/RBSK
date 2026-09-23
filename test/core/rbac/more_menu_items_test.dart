import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/rbac/more_menu_items.dart';
import 'package:referredline/data/local/enums.dart';

List<String> _labels(AppRole role) =>
    moreMenuItemsFor(role).map((i) => i.label).toList();

void main() {
  test('ADMIN sees the Admin-only entries (docs/04 §3: backup export / '
      'audit log are ADMIN only)', () {
    expect(_labels(AppRole.ADMIN), ['Backup Export', 'Audit Log']);
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
