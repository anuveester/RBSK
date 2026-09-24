import 'dart:io';

import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/recovery/backup_key_store.dart';
import 'package:referredline/data/local/recovery/database_recovery_service.dart';
import 'package:referredline/data/local/recovery/restore_transaction.dart';
import 'package:referredline/data/local/security/security_audit.dart';

import 'in_memory_secure_key_store.dart';

/// One simulated phone: its own files (real encrypted SQLite) and its own
/// secure stores. Cleaned up by [delete].
class Phone {
  Phone(String name)
    : dir = Directory.systemTemp.createTempSync('rbsk_phone_${name}_');

  final Directory dir;
  final appKeys = InMemorySecureKeyStore();
  final dbKeys = InMemorySecureKeyStore();

  String get dbDir => '${dir.path}/db';
  File get dbFile => File('$dbDir/$databaseFileName');
  File get journalFile => File('${dir.path}/journal.jsonl');

  DatabaseKeyManager get keyManager => DatabaseKeyManager(store: dbKeys);
  BackupKeyStore get backupKeys => BackupKeyStore(appKeys);
  PendingSecurityEventJournal get journal =>
      PendingSecurityEventJournal(() async => journalFile);

  DatabaseRecoveryService service({
    void Function(RestoreStep step)? beforeRestoreStep,
    DateTime Function()? clock,
  }) => DatabaseRecoveryService(
    keyManager: keyManager,
    backupKeys: backupKeys,
    databaseFileLocator: () async => dbFile,
    workDirectory: () async => Directory('${dir.path}/work'),
    preOpenAudit: journal,
    beforeRestoreStep: beforeRestoreStep,
    clock: clock,
  );

  Future<AppDatabase> open() async {
    Directory(dbDir).createSync(recursive: true);
    return AppDatabase(
      await openEncryptedDatabase(
        keyManager: keyManager,
        overrideDirectoryPath: dbDir,
        overrideTempDirectoryPath: dir.path,
      ),
    );
  }

  void delete() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}
