import 'dart:convert';

import 'package:referredline/data/local/database_connection.dart';

import 'recovery_package.dart';

/// Keeps this phone's [BackupKeyMaterial] (derived from the Backup Recovery
/// Key; never the key itself) in the general [SecureKeyStore].
class BackupKeyStore {
  BackupKeyStore(this._store);

  final SecureKeyStore _store;

  static const String storageKey = 'rbsk_backup_recovery_key_v1';

  /// Null if no backup key is set up (or the stored value is unreadable).
  /// Throws [SecureStorageUnavailableException] if the store can't be read.
  Future<BackupKeyMaterial?> read() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final kekSalt = base64Decode(map['kekSalt'] as String);
      final wrappingKey = base64Decode(map['wrappingKey'] as String);
      final keyId = map['keyId'] as String;
      if (kekSalt.length != 16 ||
          wrappingKey.length != 32 ||
          !RegExp(r'^[0-9a-f]{16}$').hasMatch(keyId)) {
        return null;
      }
      return BackupKeyMaterial(
        kekSalt: kekSalt,
        wrappingKey: wrappingKey,
        keyId: keyId,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static const String _rollbackSlot = '$storageKey.restore-rollback';
  static const String _nothing = '-';

  /// Before a restore replaces the material: remembers what is stored now.
  Future<void> saveRollbackPoint() async {
    final current = await _store.read(storageKey);
    final value = (current == null || current.isEmpty) ? _nothing : current;
    await _store.write(_rollbackSlot, value);
    if (await _store.read(_rollbackSlot) != value) {
      throw const SecureStorageUnavailableException('write');
    }
  }

  /// Puts back what [saveRollbackPoint] remembered. Does nothing if no
  /// rollback point was saved.
  Future<void> rollBackToSavedPoint() async {
    final saved = await _store.read(_rollbackSlot);
    if (saved == null || saved.isEmpty) {
      return;
    }
    final value = saved == _nothing ? '' : saved;
    if ((await _store.read(storageKey) ?? '') == value) {
      return; // Never changed.
    }
    await _store.write(storageKey, value);
    if (await _store.read(storageKey) != value) {
      throw const SecureStorageUnavailableException('write');
    }
  }

  Future<void> clearRollbackPoint() async {
    try {
      await _store.write(_rollbackSlot, '');
    } on SecureStorageUnavailableException {
      // Harmless leftover: it is overwritten before the next restore.
    }
  }

  Future<void> write(BackupKeyMaterial material) => _store.write(
    storageKey,
    jsonEncode({
      'kekSalt': base64Encode(material.kekSalt),
      'wrappingKey': base64Encode(material.wrappingKey),
      'keyId': material.keyId,
      'createdAt': material.createdAt.toUtc().toIso8601String(),
    }),
  );
}
