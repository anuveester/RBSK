import 'package:referredline/data/local/database_connection.dart';

/// Test stand-in for the Android Keystore-backed store. [values] is exposed
/// so tests can inspect exactly what was persisted, e.g. to prove a raw PIN
/// never lands in storage.
class InMemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
