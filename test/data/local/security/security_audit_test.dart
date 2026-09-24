import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/security/security_audit.dart';

import '../test_database.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late PendingSecurityEventJournal journal;
  late File journalFile;

  setUp(() {
    db = openTestDatabase();
    dir = Directory.systemTemp.createTempSync('rbsk_audit_');
    journalFile = File('${dir.path}/journal.jsonl');
    journal = PendingSecurityEventJournal(() async => journalFile);
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<List<String>> storedEvents() async => [
    for (final r in await db.select(db.auditLog).get())
      (jsonDecode(r.newValues!) as Map)['event'] as String,
  ];

  group('journal replay', () {
    test('replaying the same journal twice (a crash between writing the rows '
        'and clearing the journal) stores each event once', () async {
      await journal.record(SecurityEvent(SecurityEventType.databaseKeyUnavailable));
      await journal.record(SecurityEvent(SecurityEventType.backupImportAttempted));
      final saved = journalFile.readAsStringSync();

      await DatabaseSecurityAuditLog(db).flushPending(journal);
      expect(journalFile.existsSync(), isFalse);
      // The crash case: the journal is still there after the rows were
      // committed.
      journalFile.writeAsStringSync(saved);
      await DatabaseSecurityAuditLog(db).flushPending(journal);

      expect(await storedEvents(), hasLength(2));
      expect(journalFile.existsSync(), isFalse);
    });

    test('lines journaled without an id (older app build) are also stored '
        'only once', () async {
      final line = jsonEncode({
        'event': SecurityEventType.databaseKeyUnavailable.name,
        'subjectUserId': null,
        'actorUserId': null,
        'details': {'reason': 'keyMissingForExistingDatabase'},
        'occurredAt': DateTime.utc(2026, 9, 1).toIso8601String(),
      });
      journalFile.writeAsStringSync('$line\n');
      await DatabaseSecurityAuditLog(db).flushPending(journal);
      journalFile.writeAsStringSync('$line\n');
      await DatabaseSecurityAuditLog(db).flushPending(journal);

      expect(await storedEvents(), hasLength(1));
    });

    test('an event recorded while the journal is being flushed is not lost',
        () async {
      await journal.record(SecurityEvent(SecurityEventType.databaseKeyUnavailable));
      final flushing = DatabaseSecurityAuditLog(db).flushPending(journal);
      final late = journal.record(
        SecurityEvent(SecurityEventType.backupImportAttempted),
      );
      await Future.wait([flushing, late]);

      final stored = await storedEvents();
      final pending = (await journal.readAll()).map((e) => e.type.name);
      expect(
        [...stored, ...pending],
        containsAll([
          SecurityEventType.databaseKeyUnavailable.name,
          SecurityEventType.backupImportAttempted.name,
        ]),
      );
    });

    test('a damaged journal line is skipped; the rest is kept', () async {
      await journal.record(SecurityEvent(SecurityEventType.databaseKeyUnavailable));
      journalFile.writeAsStringSync('{not json\n', mode: FileMode.append);
      await journal.record(SecurityEvent(SecurityEventType.backupImportAttempted));
      await DatabaseSecurityAuditLog(db).flushPending(journal);
      expect(await storedEvents(), hasLength(2));
    });
  });

  group('details allowlist', () {
    test('keys outside the allowlist are dropped before anything is written',
        () async {
      final event = SecurityEvent(
        SecurityEventType.backupExportFailed,
        details: {
          'reason': 'fileSystemError',
          'pin': '000000',
          'backupKey': 'BK-SYNTHETIC',
          'databaseKey': 'ab' * 32,
          'childName': 'Synthetic Child',
        },
      );
      expect(event.details, {'reason': 'fileSystemError'});

      await DatabaseSecurityAuditLog(db).record(event);
      final row = (await db.select(db.auditLog).get()).single;
      expect(row.newValues, isNot(contains('000000')));
      expect(row.newValues, isNot(contains('BK-SYNTHETIC')));
      expect(row.newValues, isNot(contains('Synthetic Child')));
    });

    test('values that look like paths or free text are dropped, even under '
        'an allowed key', () {
      final event = SecurityEvent(
        SecurityEventType.backupImportSucceeded,
        details: {
          'preservedDatabaseFile': '/data/user/0/app/rbsk.sqlite.preserved-1',
          'reason': r'C:\Users\someone\file',
          'context': 'has spaces in it',
          'packageId': 'x' * 81,
          'step': 'committed',
        },
      );
      expect(event.details, {'step': 'committed'});
    });

    test('the real values the app records pass unchanged', () {
      final details = {
        'preservedDatabaseFile':
            'rbsk_referred_line.sqlite.preserved-1727177000000000',
        'packageId': '3f2c9a1e-7b4d-4c8e-9f10-2a3b4c5d6e7f',
        'backupKeyId': '0123456789abcdef',
        'databaseBytes': '1048576',
        'iterations': '210000',
        'newRecoveryCodeSaved': 'true',
        'context': 'keyUnavailable',
        'reason': 'keyMissingForExistingDatabase',
        'operation': 'exportBackup',
        'outcome': 'rolledBack',
        'step': 'committed',
        'trigger': 'firstRunSetup',
      };
      expect(
        SecurityEvent(SecurityEventType.backupExportCreated, details: details)
            .details,
        details,
      );
      expect(details.keys.toSet(), securityEventDetailKeys);
    });
  });
}
