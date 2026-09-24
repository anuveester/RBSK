import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/database_provider.dart';
import 'package:referredline/data/local/recovery/backup_key_store.dart';
import 'package:referredline/data/local/recovery/database_recovery_service.dart';
import 'package:referredline/data/local/recovery/recovery_package.dart';
import 'package:referredline/data/local/recovery/restore_transaction.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:referredline/data/local/security/security_providers.dart';

import '../../../support/phone_fixture.dart';

// Synthetic test PIN only.
const _pin = '530827';
const _timeout = Timeout(Duration(minutes: 3));

/// "A failed restore must never destroy the currently usable database."
///
/// Phone B has its own usable database (first run, some data, no accounts
/// yet — the only state a restore is allowed over besides "locked"), its
/// own database key, and its own Backup Recovery Key material. A restore of
/// phone A's package is made to fail, or the phone "loses power", before
/// every step. Afterwards phone B must be exactly as it was and open
/// normally.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Phone a;
  late Phone b;
  late SecretCode backupKey;
  late File package;

  late List<int> bDatabase;
  late String bKey;
  late String bBackupMaterial;

  setUpAll(() async {
    a = Phone('a');
    final db = await a.open();
    await a.auth(db).setupBootstrapAdmin(displayName: 'Admin A', pin: _pin);
    await db
        .into(db.financialYears)
        .insert(
          FinancialYearsCompanion.insert(
            id: 'fy-a',
            label: 'A-MARKER',
            startDate: DateTime.utc(2025, 4, 1),
            endDate: DateTime.utc(2026, 3, 31),
          ),
        );
    backupKey = await a.service().createBackupKey(
      auth: a.auth(db),
      currentPin: _pin,
      audit: DatabaseSecurityAuditLog(db),
    );
    final made = await a.service().createPackage(
      db,
      auth: a.auth(db),
      currentPin: _pin,
      audit: DatabaseSecurityAuditLog(db),
    );
    await db.close();
    package = await made.copy('${a.dir.path}/package.rbskrp');
  });

  tearDownAll(() => a.delete());

  setUp(() async {
    b = Phone('b');
    final db = await b.open();
    await db
        .into(db.financialYears)
        .insert(
          FinancialYearsCompanion.insert(
            id: 'fy-b',
            label: 'B-MARKER',
            startDate: DateTime.utc(2025, 4, 1),
            endDate: DateTime.utc(2026, 3, 31),
          ),
        );
    await db.close();
    await b.backupKeys.write(
      BackupKeyMaterial.derive(
        SecretCode.generate(SecretCodeKind.backupRecovery),
      ),
    );
    bDatabase = b.dbFile.readAsBytesSync();
    bKey = b.dbKeys.values[databaseKeyStorageName]!;
    bBackupMaterial = b.appKeys.values[BackupKeyStore.storageKey]!;
  });

  tearDown(() => b.delete());

  DatabaseRecoveryService serviceWithHook(void Function(RestoreStep) hook) =>
      DatabaseRecoveryService(
        keyManager: b.keyManager,
        backupKeys: b.backupKeys,
        databaseFileLocator: () async => b.dbFile,
        workDirectory: () async => Directory('${b.dir.path}/work'),
        preOpenAudit: b.journal,
        beforeRestoreStep: hook,
      );

  Future<VerifiedRestore> verified() => b.service().verify(
    package,
    backupKey.formatted,
    context: RestoreContext.newDevice,
  );

  List<String> dbFolder() =>
      Directory(b.dbDir).listSync().map((f) => f.uri.pathSegments.last).toList()
        ..sort();

  Future<List<String>> labelsOnB() async {
    final db = await b.open();
    try {
      return [for (final r in await db.select(db.financialYears).get()) r.label];
    } finally {
      await db.close();
    }
  }

  Future<void> expectPhoneBUnchanged() async {
    expect(b.dbFile.readAsBytesSync(), bDatabase, reason: 'same database file');
    expect(b.dbKeys.values[databaseKeyStorageName], bKey, reason: 'same key');
    expect(
      b.appKeys.values[BackupKeyStore.storageKey],
      bBackupMaterial,
      reason: 'same backup-key material',
    );
    expect(dbFolder(), [databaseFileName], reason: 'nothing left over');
    expect(await labelsOnB(), ['B-MARKER'], reason: 'B opens normally');
  }

  final stepsBeforeCommit = [
    for (final s in RestoreStep.values)
      if (s != RestoreStep.finish) s,
  ];

  group('a failure at any step is rolled back before install returns', () {
    for (final step in stepsBeforeCommit) {
      test('failure before ${step.name}', () async {
        final restore = await verified();
        final service = serviceWithHook((s) {
          if (s == step) {
            throw StateError('injected failure');
          }
        });

        await expectLater(
          service.install(restore, confirmedByUser: true),
          throwsStateError,
        );
        await expectPhoneBUnchanged();
        expect(
          b.journalFile.readAsStringSync(),
          contains(SecurityEventType.backupImportRejected.name),
        );
      }, timeout: _timeout);
    }
  });

  group('power loss at any step is undone at the next start', () {
    for (final step in stepsBeforeCommit) {
      test('power lost before ${step.name}', () async {
        final restore = await verified();
        final service = serviceWithHook((s) {
          if (s == step) {
            throw const SimulatedPowerLoss();
          }
        });
        await expectLater(
          service.install(restore, confirmedByUser: true),
          throwsA(isA<SimulatedPowerLoss>()),
        );

        // Next start: a fresh service, as the app would build it.
        final outcome = await b.service().resolveInterruptedRestore();
        await b.service().removeLeftoverFiles();

        final nothingChangedYet =
            step == RestoreStep.saveRollbackPoint ||
            step == RestoreStep.writeMarker;
        expect(
          outcome,
          nothingChangedYet
              ? InterruptedRestoreOutcome.none
              : InterruptedRestoreOutcome.rolledBack,
        );
        await expectPhoneBUnchanged();
      }, timeout: _timeout);
    }

    test('power lost after the commit: the restore is kept and finished; '
        'B\'s own database is kept aside, not deleted', () async {
      final restore = await verified();
      final service = serviceWithHook((s) {
        if (s == RestoreStep.finish) {
          throw const SimulatedPowerLoss();
        }
      });
      await expectLater(
        service.install(restore, confirmedByUser: true),
        throwsA(isA<SimulatedPowerLoss>()),
      );

      expect(
        await b.service().resolveInterruptedRestore(),
        InterruptedRestoreOutcome.completed,
      );
      expect(await labelsOnB(), ['A-MARKER']);
      expect((await b.backupKeys.read())!.matches(backupKey), isTrue);
      final preserved = Directory(b.dbDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.preserved-'))
          .single;
      expect(preserved.readAsBytesSync(), bDatabase);
      expect(
        b.dbKeys.values.entries
            .where((e) => e.key.contains('.preserved.'))
            .map((e) => e.value),
        contains(bKey),
      );
      expect(File('${b.dbFile.path}.restore-marker').existsSync(), isFalse);
    }, timeout: _timeout);

    test('running the start-up check again changes nothing', () async {
      final restore = await verified();
      final service = serviceWithHook((s) {
        if (s == RestoreStep.installBackupKey) {
          throw const SimulatedPowerLoss();
        }
      });
      await expectLater(
        service.install(restore, confirmedByUser: true),
        throwsA(isA<SimulatedPowerLoss>()),
      );
      await b.service().resolveInterruptedRestore();
      expect(
        await b.service().resolveInterruptedRestore(),
        InterruptedRestoreOutcome.none,
      );
      await expectPhoneBUnchanged();
    }, timeout: _timeout);
  });

  group('real storage failures', () {
    test('the database key cannot be saved: rolled back, B unchanged',
        () async {
      final restore = await verified();
      var failed = false;
      b.dbKeys.failWritesWhere = (k) {
        if (k == databaseKeyStorageName && !failed) {
          failed = true;
          return true;
        }
        return false;
      };
      await expectLater(
        b.service().install(restore, confirmedByUser: true),
        throwsA(isA<DatabaseKeyUnavailableException>()),
      );
      b.dbKeys.failWritesWhere = null;
      await expectPhoneBUnchanged();
    }, timeout: _timeout);

    test('the backup-key material cannot be saved: rolled back, B unchanged '
        '(the restored key is kept aside, not discarded)', () async {
      final restore = await verified();
      var failed = false;
      b.appKeys.failWritesWhere = (k) {
        if (k == BackupKeyStore.storageKey && !failed) {
          failed = true;
          return true;
        }
        return false;
      };
      await expectLater(
        b.service().install(restore, confirmedByUser: true),
        throwsA(isA<SecureStorageUnavailableException>()),
      );
      b.appKeys.failWritesWhere = null;
      await expectPhoneBUnchanged();
    }, timeout: _timeout);

    test('secure storage stops working mid-restore and stays broken: the '
        'marker stays, start-up refuses to guess, and once storage works '
        'again the restore is undone', () async {
      final restore = await verified();
      final service = serviceWithHook((s) {
        if (s == RestoreStep.installBackupKey) {
          // From here on, every secure-storage write fails.
          b.dbKeys.failWritesWhere = (_) => true;
          b.appKeys.failWritesWhere = (_) => true;
        }
      });
      await expectLater(
        service.install(restore, confirmedByUser: true),
        throwsA(isA<SecureStorageUnavailableException>()),
      );
      expect(File('${b.dbFile.path}.restore-marker').existsSync(), isTrue);
      // B's own database is already back in place, never deleted.
      expect(b.dbFile.readAsBytesSync(), bDatabase);

      // Start-up while storage is still broken: resolution fails, so the
      // app does not open anything half-restored.
      await expectLater(
        b.service().resolveInterruptedRestore(),
        throwsA(anything),
      );

      b.dbKeys.failWritesWhere = null;
      b.appKeys.failWritesWhere = null;
      expect(
        await b.service().resolveInterruptedRestore(),
        InterruptedRestoreOutcome.rolledBack,
      );
      await expectPhoneBUnchanged();
    }, timeout: _timeout);

    test('not enough space to unpack the backup: refused before anything on '
        'the phone changes', () async {
      // Stand-in for a full disk: the staging file cannot be created.
      Directory('${b.dbFile.path}.restore-staged').createSync();
      await expectLater(
        verified(),
        throwsA(
          isA<RecoveryPackageException>().having(
            (e) => e.reason,
            'reason',
            RecoveryPackageError.couldNotSave,
          ),
        ),
      );
      Directory('${b.dbFile.path}.restore-staged').deleteSync();
      await expectPhoneBUnchanged();
    }, timeout: _timeout);
  });

  test('a damaged marker never leads to a database file being deleted',
      () async {
    final restore = await verified();
    final service = serviceWithHook((s) {
      if (s == RestoreStep.verifyInstalled) {
        throw const SimulatedPowerLoss();
      }
    });
    await expectLater(
      service.install(restore, confirmedByUser: true),
      throwsA(isA<SimulatedPowerLoss>()),
    );
    final restoredCopy = b.dbFile.readAsBytesSync();
    File('${b.dbFile.path}.restore-marker').writeAsStringSync('{garbage');

    await b.service().resolveInterruptedRestore();

    final contents = [
      for (final f in Directory(b.dbDir).listSync().whereType<File>())
        f.readAsBytesSync(),
    ];
    expect(contents, contains(equals(bDatabase)), reason: 'B kept');
    expect(contents, contains(equals(restoredCopy)), reason: 'copy kept');
    expect(b.dbKeys.values[databaseKeyStorageName], bKey);
  }, timeout: _timeout);

  test('leftover files from interrupted operations are removed at start-up, '
      'but never the database', () async {
    final work = Directory('${b.dir.path}/work')..createSync(recursive: true);
    File('${work.path}/export-1.snapshot').writeAsStringSync('x');
    File('${work.path}/import-1.rbskrp').writeAsStringSync('x');
    final staged = File('${b.dbFile.path}.restore-staged')
      ..writeAsStringSync('x');

    await b.service().removeLeftoverFiles();

    expect(work.existsSync(), isFalse);
    expect(staged.existsSync(), isFalse);
    await expectPhoneBUnchanged();
  }, timeout: _timeout);

  test('a staged database is not removed while a restore still needs '
      'resolving', () async {
    final staged = File('${b.dbFile.path}.restore-staged')
      ..writeAsStringSync('x');
    final marker = File('${b.dbFile.path}.restore-marker')
      ..writeAsStringSync('{"version":1,"phase":"installing"}');
    await b.service().removeLeftoverFiles();
    expect(staged.existsSync(), isTrue);
    marker.deleteSync();
    staged.deleteSync();
  }, timeout: _timeout);

  test('the start-up path of the app (the database provider) undoes an '
      'interrupted restore before opening, and opens the data B had', () async {
    final restore = await verified();
    final service = serviceWithHook((s) {
      if (s == RestoreStep.installBackupKey) {
        throw const SimulatedPowerLoss();
      }
    });
    await expectLater(
      service.install(restore, confirmedByUser: true),
      throwsA(isA<SimulatedPowerLoss>()),
    );

    // The app's real providers, with only the platform locations and the
    // secure stores pointed at phone B.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
      'getApplicationDocumentsDirectory' => b.dbDir,
      'getApplicationSupportDirectory' => b.dir.path,
      'getTemporaryDirectory' => b.dir.path,
      _ => null,
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final container = ProviderContainer(
      overrides: [
        databaseKeyManagerProvider.overrideWithValue(b.keyManager),
        secureKeyStoreProvider.overrideWithValue(b.appKeys),
      ],
    );
    addTearDown(container.dispose);

    final db = await container.read(appDatabaseProvider.future);
    final labels = [
      for (final r in await db.select(db.financialYears).get()) r.label,
    ];
    await closeAppDatabase(db);

    expect(labels, ['B-MARKER']);
    expect(File('${b.dbFile.path}.restore-marker').existsSync(), isFalse);
    expect(b.appKeys.values[BackupKeyStore.storageKey], bBackupMaterial);
  }, timeout: _timeout);
}
