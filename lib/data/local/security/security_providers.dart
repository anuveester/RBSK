import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database_connection.dart';
import 'security_audit.dart';

/// General secure storage (credentials, sessions, lockout, recovery-code
/// and backup-key verifiers). Android Keystore-backed, and never resets
/// itself on error: see [FlutterSecureStorageKeyStore.general].
final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => const FlutterSecureStorageKeyStore.general(),
);

/// Security events that happen while the database can't be opened, kept in
/// app-private storage until the next successful open. Never contains
/// secrets (see [SecurityEvent]).
final securityEventJournalProvider = Provider<PendingSecurityEventJournal>(
  (ref) => PendingSecurityEventJournal(() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'security_events_pending.jsonl'));
  }),
);
