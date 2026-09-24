import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' show InvalidCipherTextException;
import 'package:referredline/core/security/crypto_utils.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/recovery/recovery_package.dart';

Uint8List _hex(String h) => hexToBytes(h);

bool _containsBytes(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}

void main() {
  group('primitive known-answer tests', () {
    test('HKDF-SHA256 matches RFC 5869 test case 1', () {
      final okm = hkdfSha256(
        Uint8List.fromList(List.filled(22, 0x0b)),
        Uint8List.fromList(List.generate(13, (i) => i)),
        Uint8List.fromList(List.generate(10, (i) => 0xf0 + i)),
        42,
      );
      expect(
        bytesToHex(okm),
        '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
        '34007208d5b887185865',
      );
    });

    // Reference output produced independently by Python `cryptography`
    // (OpenSSL) AESGCM with the same fixed, non-secret inputs.
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final nonce = Uint8List.fromList(List.generate(12, (i) => i));
    final aad = Uint8List.fromList(utf8.encode('rbsk-aad'));
    final plain = Uint8List.fromList(utf8.encode('rbsk gcm known answer'));
    const expected =
        '3560a570e582a176ad2af9e4c687580ceda5f051825e42dab0e227904102f1e05d4c46911f';

    test('AES-256-GCM encryption matches an independent implementation', () {
      final ct = aes256Gcm(
        encrypt: true,
        key: key,
        nonce: nonce,
        aad: aad,
        input: plain,
      );
      expect(bytesToHex(ct), expected);
    });

    test('AES-256-GCM decrypts it, and rejects a changed tag or AAD', () {
      final ct = _hex(expected);
      expect(
        aes256Gcm(encrypt: false, key: key, nonce: nonce, aad: aad, input: ct),
        plain,
      );
      final badTag = Uint8List.fromList(ct)..[ct.length - 1] ^= 1;
      expect(
        () => aes256Gcm(
          encrypt: false,
          key: key,
          nonce: nonce,
          aad: aad,
          input: badTag,
        ),
        throwsA(isA<InvalidCipherTextException>()),
      );
      expect(
        () => aes256Gcm(
          encrypt: false,
          key: key,
          nonce: nonce,
          aad: Uint8List.fromList(utf8.encode('other')),
          input: ct,
        ),
        throwsA(isA<InvalidCipherTextException>()),
      );
    });
  });

  group('BackupKeyMaterial', () {
    test('matches only the key it came from', () {
      final code = SecretCode.generate(SecretCodeKind.backupRecovery);
      final material = BackupKeyMaterial.derive(code);

      expect(material.matches(code), isTrue);
      expect(
        material.matches(SecretCode.generate(SecretCodeKind.backupRecovery)),
        isFalse,
      );
      expect(material.wrappingKey, hasLength(32));
      expect(material.keyId, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(material.toString(), isNot(contains(bytesToHex(material.wrappingKey))));
    });
  });

  group('package round trip and tampering', () {
    late Directory dir;
    late File snapshot;
    late File package;
    late SecretCode code;
    late BackupKeyMaterial material;
    late String dbKey;
    late Uint8List dbBytes;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('rbsk_pkg_test_');
      // Stand-in for an encrypted database file: random bytes.
      dbBytes = secureRandomBytes(50000);
      snapshot = File('${dir.path}/snapshot.bin')..writeAsBytesSync(dbBytes);
      package = File('${dir.path}/test.rbskrp');
      code = SecretCode.generate(SecretCodeKind.backupRecovery);
      material = BackupKeyMaterial.derive(code);
      dbKey = generatePassphrase();
      await writeRecoveryPackage(
        databaseSnapshot: snapshot,
        databaseKey: dbKey,
        key: material,
        output: package,
        packageId: 'pkg-1',
        createdAt: DateTime.utc(2026, 9, 24, 10),
        schemaVersion: 1,
      );
    });

    tearDown(() => dir.deleteSync(recursive: true));

    File out() => File('${dir.path}/restored.bin');

    test('opens with the right key: same database bytes, key and id', () async {
      final opened = await openRecoveryPackage(
        package,
        code,
        databaseOutput: out(),
      );

      expect(out().readAsBytesSync(), dbBytes);
      expect(opened.databaseKey, dbKey);
      expect(opened.packageId, 'pkg-1');
      expect(opened.schemaVersion, 1);
      expect(opened.summary.createdAt, DateTime.utc(2026, 9, 24, 10));
      expect(opened.backupKeyMaterial.matches(code), isTrue);
    });

    test('the package never contains the database key, the wrapping key, or '
        'the backup key in plain form', () {
      final bytes = package.readAsBytesSync();
      final text = latin1.decode(bytes);

      expect(text, isNot(contains(dbKey)));
      expect(_containsBytes(bytes, hexToBytes(dbKey)), isFalse);
      expect(_containsBytes(bytes, material.wrappingKey), isFalse);
      expect(text, isNot(contains(code.canonical)));
      expect(_containsBytes(bytes, code.bytes), isFalse);
    });

    test('the summary is readable without the key', () async {
      final summary = await readRecoveryPackageSummary(package);
      expect(summary.keyId, material.keyId);
      expect(summary.databaseBytes, dbBytes.length);
    });

    Future<RecoveryPackageError?> attempt({SecretCode? withCode}) async {
      try {
        await openRecoveryPackage(
          package,
          withCode ?? code,
          databaseOutput: out(),
        );
        return null;
      } on RecoveryPackageException catch (e) {
        return e.reason;
      }
    }

    test('a different Backup Recovery Key is identified as such', () async {
      final other = SecretCode.generate(SecretCodeKind.backupRecovery);
      expect(await attempt(withCode: other), RecoveryPackageError.differentBackupKey);
      expect(out().existsSync(), isFalse);
    });

    void mutate(int offset) {
      final bytes = package.readAsBytesSync();
      bytes[offset] ^= 0x01;
      package.writeAsBytesSync(bytes);
    }

    int headerEnd() {
      final bytes = package.readAsBytesSync();
      final headerLen = ByteData.sublistView(bytes, 8, 12).getUint32(0);
      return 12 + headerLen;
    }

    test('a changed header byte is rejected', () async {
      // A byte inside the header JSON's createdAt value: still valid JSON
      // and still parseable, so only the authentication check can catch it.
      final bytes = package.readAsBytesSync();
      final header = utf8.decode(bytes.sublist(12, headerEnd()));
      final at = header.indexOf('2026-09-24T10');
      bytes[12 + at + 3] = '7'.codeUnitAt(0);
      package.writeAsBytesSync(bytes);

      expect(await attempt(), RecoveryPackageError.authenticationFailed);
      expect(out().existsSync(), isFalse);
    });

    test('a changed payload byte is rejected', () async {
      mutate(headerEnd() + 4 + 5);
      expect(await attempt(), RecoveryPackageError.authenticationFailed);
    });

    test('a changed database byte is rejected and nothing is left behind',
        () async {
      mutate(package.lengthSync() - 100);
      expect(await attempt(), RecoveryPackageError.databaseIntegrityFailed);
      expect(out().existsSync(), isFalse);
    });

    test('truncation and trailing data are rejected', () async {
      final original = package.readAsBytesSync();

      package.writeAsBytesSync(original.sublist(0, original.length - 1));
      expect(await attempt(), RecoveryPackageError.malformed);

      package.writeAsBytesSync([...original, 0]);
      expect(await attempt(), RecoveryPackageError.malformed);
    });

    test('a changed length field is rejected', () async {
      mutate(9); // header length
      expect(await attempt(), isNotNull);
    });

    test('a file that is not a package is rejected', () async {
      package.writeAsBytesSync(utf8.encode('SQLite format 3\u0000 not a package'));
      expect(await attempt(), RecoveryPackageError.notARecoveryPackage);

      package.writeAsBytesSync(const []);
      expect(await attempt(), RecoveryPackageError.notARecoveryPackage);
    });

    test('a future format version is refused, not guessed at', () async {
      mutate(7);
      expect(await attempt(), RecoveryPackageError.unsupportedVersion);
    });
  });
}
