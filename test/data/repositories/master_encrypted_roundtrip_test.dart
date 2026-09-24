import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/repositories/drift_awc_repository.dart';
import 'package:referredline/data/repositories/drift_school_repository.dart';
import 'package:referredline/domain/entities/awc.dart';
import 'package:referredline/domain/entities/school.dart';

import '../../support/phone_fixture.dart';

void main() {
  test('a School and an AWC saved in the real encrypted database are there '
      'after reopening, with their audit rows; the file is not plaintext',
      () async {
    final phone = Phone('masters');
    addTearDown(phone.delete);

    var db = await phone.open();
    final school = await DriftSchoolRepository(db).create(
      const SchoolInput(name: 'Test School Encrypted', officialSchoolCode: 'SYN-9001'),
    );
    final awc = await DriftAwcRepository(db).create(
      const AwcInput(name: 'Test AWC Encrypted', subcentreNo: 1),
    );
    await db.close();

    final bytes = phone.dbFile.readAsBytesSync();
    expect(latin1.decode(bytes), isNot(contains('SQLite format 3')));
    expect(latin1.decode(bytes), isNot(contains('Test School Encrypted')));

    db = await phone.open();
    addTearDown(db.close);
    expect(
      (await DriftSchoolRepository(db).getById(school.id))!.officialSchoolCode,
      'SYN-9001',
    );
    expect((await DriftAwcRepository(db).getById(awc.id))!.subcentreNo, 1);
    final audit = await db.select(db.auditLog).get();
    expect(audit.map((r) => r.businessTableName).toSet(), {'schools', 'awcs'});
    expect(audit.every((r) => r.actorUserId == null), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
