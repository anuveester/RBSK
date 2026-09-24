import 'package:referredline/data/local/database_connection.dart';

/// Test stand-in for the Android Keystore-backed store. [values] is exposed
/// so tests can inspect exactly what was persisted, e.g. to prove a raw PIN
/// never lands in storage.
///
/// [failReads] / [failWritesWhere] simulate the platform store failing (as
/// `FlutterSecureStorageKeyStore` reports it: a
/// [SecureStorageUnavailableException]) — e.g. a Keystore key that can no
/// longer unwrap the stored data.
class InMemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = {};
  bool failReads = false;
  bool Function(String key)? failWritesWhere;
  int writeCount = 0;

  @override
  Future<String?> read(String key) async {
    if (failReads) {
      throw const SecureStorageUnavailableException('read');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWritesWhere?.call(key) ?? false) {
      throw const SecureStorageUnavailableException('write');
    }
    writeCount++;
    values[key] = value;
  }
}
