import 'dart:io';

import 'package:referredline/data/local/app_database.dart';
import 'package:referredline/data/local/auth/credential_hasher.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/recovery/backup_key_store.dart';
import 'package:referredline/data/local/recovery/database_recovery_service.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:referredline/data/repositories/drift_user_repository.dart';
import 'package:referredline/data/repositories/local_auth_repository.dart';

import 'in_memory_secure_key_store.dart';

/// Lighter than production for speed where the iteration count is not what
/// is being tested (production parameters are covered elsewhere).
const fastKdf = CredentialKdfPolicy(iterations: 10000);

/// One simulated phone: its own files (real encrypted SQLite) and its own
/// secure stores. Cleaned up by [delete].
class Phone {
  Phone(String name)
    : dir = Directory.systemTemp.createTempSync('rbsk_phone_${name}_');

  final Directory dir;
  final appKeys = InMemorySecureKeyStore();
  final dbKeys = InMemorySecureKeyStore();
  DateTime now = DateTime.utc(2026, 9, 24, 12);

  String get dbDir => '${dir.path}/db';
  File get dbFile => File('$dbDir/$databaseFileName');
  File get journalFile => File('${dir.path}/journal.jsonl');

  DatabaseKeyManager get keyManager => DatabaseKeyManager(store: dbKeys);
  BackupKeyStore get backupKeys => BackupKeyStore(appKeys);
  PendingSecurityEventJournal get journal =>
      PendingSecurityEventJournal(() async => journalFile);

  DatabaseRecoveryService service() => DatabaseRecoveryService(
    keyManager: keyManager,
    backupKeys: backupKeys,
    databaseFileLocator: () async => dbFile,
    workDirectory: () async => Directory('${dir.path}/work'),
    preOpenAudit: journal,
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

  LocalAuthRepository auth(AppDatabase db) => LocalAuthRepository(
    userRepository: DriftUserRepository(db),
    keyStore: appKeys,
    audit: DatabaseSecurityAuditLog(db, fallback: journal),
    backupKeys: backupKeys,
    kdfPolicy: fastKdf,
    clock: () => now,
  );

  void delete() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}
