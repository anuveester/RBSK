import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:referredline/core/security/crypto_utils.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/data/local/database_connection.dart';

/// Encrypted recovery package (docs/30 R5) — the app's controlled backup.
///
/// What is in a package, and how each part is protected:
///
/// | Part | Protection |
/// |---|---|
/// | Database data | The SQLite file exactly as stored: still encrypted with the database key (SQLite3MultipleCiphers). Never exported as plaintext. |
/// | Database key | Inside the payload, AES-256-GCM encrypted. |
/// | Recovery secret (Backup Recovery Key) | Never in the package and never stored on the phone. The payload key is HKDF-SHA256(secret, per-key salt). |
/// | Integrity / authenticity | GCM authenticates the header (as associated data) and the payload. The payload carries the database's SHA-256 and length, so any change anywhere is rejected. Only a holder of the Backup Recovery Key can produce a package that verifies. |
///
/// Layout (big-endian lengths):
/// `magic(8) | u32 headerLen | header JSON | u32 payloadLen | GCM(payload JSON) | u64 dbLen | database bytes`
///
/// The package contains no file names or paths — importing always writes to
/// the app's own fixed database location, so a package cannot direct a write
/// anywhere else.
const List<int> _magic = [0x52, 0x42, 0x53, 0x4B, 0x52, 0x50, 0x00, 0x01];
const int recoveryPackageFormatVersion = 1;
const String _formatName = 'rbsk-recovery-package';
const int _maxHeaderBytes = 16 * 1024;
const int _maxPayloadBytes = 16 * 1024;

/// Upper bound on the database section, to refuse absurd files early.
const int maxRecoveryDatabaseBytes = 1024 * 1024 * 1024;

const String _kekInfo = 'RBSK recovery package KEK v1';
const String _keyIdInfo = 'RBSK recovery package key id v1';

enum RecoveryPackageError {
  notARecoveryPackage,
  unsupportedVersion,
  malformed,
  tooLarge,
  differentBackupKey,
  authenticationFailed,
  databaseIntegrityFailed,
  databaseDoesNotOpen,
}

class RecoveryPackageException implements Exception {
  const RecoveryPackageException(this.reason);

  final RecoveryPackageError reason;

  @override
  String toString() => 'RecoveryPackageException(${reason.name})';
}

/// HKDF-SHA256 (RFC 5869) via pointycastle. Pinned by known-answer tests.
Uint8List hkdfSha256(Uint8List ikm, Uint8List salt, Uint8List info, int length) {
  final derivator = HKDFKeyDerivator(SHA256Digest())
    ..init(HkdfParameters(ikm, length, salt, info));
  return derivator.process(Uint8List(0));
}

Uint8List _hkdf(Uint8List ikm, Uint8List salt, String info, int length) =>
    hkdfSha256(ikm, salt, Uint8List.fromList(utf8.encode(info)), length);

/// AES-256-GCM with a 128-bit tag via pointycastle. Encrypt returns
/// ciphertext‖tag; decrypt throws [InvalidCipherTextException] on any
/// authentication failure. Pinned by known-answer tests.
Uint8List aes256Gcm({
  required bool encrypt,
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List aad,
  required Uint8List input,
}) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(encrypt, AEADParameters(KeyParameter(key), 128, nonce, aad));
  return cipher.process(input);
}

Uint8List _gcm({
  required bool encrypt,
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List aad,
  required Uint8List input,
}) => aes256Gcm(encrypt: encrypt, key: key, nonce: nonce, aad: aad, input: input);

/// Key material derived from a Backup Recovery Key. The phone keeps this
/// (never the key itself) so it can make packages without asking for the key
/// each time.
class BackupKeyMaterial {
  const BackupKeyMaterial({
    required this.kekSalt,
    required this.wrappingKey,
    required this.keyId,
    required this.createdAt,
  });

  factory BackupKeyMaterial.derive(
    SecretCode code, {
    Uint8List? kekSalt,
    DateTime? createdAt,
  }) {
    if (code.kind != SecretCodeKind.backupRecovery) {
      throw ArgumentError('Not a Backup Recovery Key.');
    }
    final salt = kekSalt ?? secureRandomBytes(16);
    return BackupKeyMaterial(
      kekSalt: salt,
      wrappingKey: _hkdf(code.bytes, salt, _kekInfo, 32),
      keyId: bytesToHex(_hkdf(code.bytes, salt, _keyIdInfo, 8)),
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
    );
  }

  /// Not secret: stored with the key material and in each package header.
  final Uint8List kekSalt;

  /// Secret: encrypts package payloads.
  final Uint8List wrappingKey;

  /// Not secret: one-way identifier people can use to match a package to its
  /// Backup Recovery Key.
  final String keyId;
  final DateTime createdAt;

  /// Whether [code] is the Backup Recovery Key this material came from.
  bool matches(SecretCode code) =>
      code.kind == SecretCodeKind.backupRecovery &&
      constantTimeEquals(
        BackupKeyMaterial.derive(code, kekSalt: kekSalt).wrappingKey,
        wrappingKey,
      );

  /// Short form of [keyId] for people, e.g. `3F9A-12C4`.
  String get displayId =>
      '${keyId.substring(0, 4)}-${keyId.substring(4, 8)}'.toUpperCase();

  @override
  String toString() => 'BackupKeyMaterial($displayId, redacted)';
}

/// What can be read from a package without its key.
class RecoveryPackageSummary {
  const RecoveryPackageSummary({
    required this.createdAt,
    required this.keyId,
    required this.databaseBytes,
  });

  final DateTime createdAt;
  final String keyId;
  final int databaseBytes;

  String get keyDisplayId =>
      '${keyId.substring(0, 4)}-${keyId.substring(4, 8)}'.toUpperCase();
}

/// A package whose authenticity and database integrity have been verified,
/// with its database already written to [databaseFile].
class OpenedRecoveryPackage {
  const OpenedRecoveryPackage({
    required this.summary,
    required this.packageId,
    required this.databaseKey,
    required this.schemaVersion,
    required this.backupKeyMaterial,
  });

  final RecoveryPackageSummary summary;
  final String packageId;
  final String databaseKey;
  final int schemaVersion;
  final BackupKeyMaterial backupKeyMaterial;

  @override
  String toString() => 'OpenedRecoveryPackage($packageId, redacted)';
}

Uint8List _u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();
Uint8List _u64(int v) => (ByteData(8)..setUint64(0, v)).buffer.asUint8List();

Future<Uint8List> _sha256OfFile(File file) async {
  final digest = SHA256Digest();
  await for (final chunk in file.openRead()) {
    final bytes = Uint8List.fromList(chunk);
    digest.update(bytes, 0, bytes.length);
  }
  final out = Uint8List(digest.digestSize);
  digest.doFinal(out, 0);
  return out;
}

/// Writes a package for [databaseSnapshot] (an already-encrypted copy of the
/// database file) to [output].
Future<void> writeRecoveryPackage({
  required File databaseSnapshot,
  required String databaseKey,
  required BackupKeyMaterial key,
  required File output,
  required String packageId,
  required DateTime createdAt,
  required int schemaVersion,
}) async {
  if (!isWellFormedDatabaseKey(databaseKey)) {
    throw ArgumentError('Unexpected database key format.');
  }
  final dbLength = await databaseSnapshot.length();
  if (dbLength <= 0 || dbLength > maxRecoveryDatabaseBytes) {
    throw const RecoveryPackageException(RecoveryPackageError.tooLarge);
  }
  final dbHash = await _sha256OfFile(databaseSnapshot);
  final nonce = secureRandomBytes(12);
  final created = createdAt.toUtc().toIso8601String();

  final header = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': _formatName,
        'version': recoveryPackageFormatVersion,
        'kdf': 'hkdf-sha256',
        'cipher': 'aes-256-gcm',
        'kekSalt': base64Encode(key.kekSalt),
        'keyId': key.keyId,
        'nonce': base64Encode(nonce),
        'createdAt': created,
      }),
    ),
  );
  final aad = Uint8List.fromList([..._magic, ..._u32(header.length), ...header]);
  final payload = _gcm(
    encrypt: true,
    key: key.wrappingKey,
    nonce: nonce,
    aad: aad,
    input: Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'packageId': packageId,
          'createdAt': created,
          'databaseKey': databaseKey,
          'databaseSha256': bytesToHex(dbHash),
          'databaseBytes': dbLength,
          'schemaVersion': schemaVersion,
        }),
      ),
    ),
  );

  final sink = output.openWrite();
  try {
    sink
      ..add(aad)
      ..add(_u32(payload.length))
      ..add(payload)
      ..add(_u64(dbLength));
    await sink.addStream(databaseSnapshot.openRead());
    await sink.flush();
  } finally {
    await sink.close();
  }
}

class _Layout {
  const _Layout(this.headerJson, this.aad, this.payload, this.dbOffset, this.dbLength);

  final Map<String, dynamic> headerJson;
  final Uint8List aad;
  final Uint8List payload;
  final int dbOffset;
  final int dbLength;
}

Future<Uint8List> _readExact(RandomAccessFile raf, int length) async {
  final bytes = await raf.read(length);
  if (bytes.length != length) {
    throw const RecoveryPackageException(RecoveryPackageError.malformed);
  }
  return bytes;
}

Future<_Layout> _readLayout(File package) async {
  final total = await package.length();
  final raf = await package.open();
  try {
    if (total < _magic.length + 4) {
      throw const RecoveryPackageException(
        RecoveryPackageError.notARecoveryPackage,
      );
    }
    final magic = await _readExact(raf, _magic.length);
    if (!constantTimeEquals(magic.sublist(0, 6), _magic.sublist(0, 6))) {
      throw const RecoveryPackageException(
        RecoveryPackageError.notARecoveryPackage,
      );
    }
    if (magic[6] != _magic[6] || magic[7] != _magic[7]) {
      throw const RecoveryPackageException(
        RecoveryPackageError.unsupportedVersion,
      );
    }
    final headerLenBytes = await _readExact(raf, 4);
    final headerLen = ByteData.sublistView(headerLenBytes).getUint32(0);
    if (headerLen == 0 || headerLen > _maxHeaderBytes) {
      throw const RecoveryPackageException(RecoveryPackageError.malformed);
    }
    final header = await _readExact(raf, headerLen);
    final Map<String, dynamic> headerJson;
    try {
      headerJson = jsonDecode(utf8.decode(header)) as Map<String, dynamic>;
    } on FormatException {
      throw const RecoveryPackageException(RecoveryPackageError.malformed);
    } on TypeError {
      throw const RecoveryPackageException(RecoveryPackageError.malformed);
    }
    final payloadLen = ByteData.sublistView(
      await _readExact(raf, 4),
    ).getUint32(0);
    if (payloadLen < 17 || payloadLen > _maxPayloadBytes) {
      throw const RecoveryPackageException(RecoveryPackageError.malformed);
    }
    final payload = await _readExact(raf, payloadLen);
    final dbLength = ByteData.sublistView(await _readExact(raf, 8)).getUint64(0);
    final dbOffset = _magic.length + 4 + headerLen + 4 + payloadLen + 8;
    if (dbLength <= 0 || dbLength > maxRecoveryDatabaseBytes) {
      throw const RecoveryPackageException(RecoveryPackageError.tooLarge);
    }
    // Exactly the declared database bytes follow: no truncation, no trailing
    // data.
    if (dbOffset + dbLength != total) {
      throw const RecoveryPackageException(RecoveryPackageError.malformed);
    }
    final aad = Uint8List.fromList([..._magic, ...headerLenBytes, ...header]);
    return _Layout(headerJson, aad, payload, dbOffset, dbLength);
  } on FileSystemException {
    throw const RecoveryPackageException(RecoveryPackageError.malformed);
  } finally {
    await raf.close();
  }
}

class _Header {
  const _Header(this.kekSalt, this.keyId, this.nonce, this.createdAt);

  final Uint8List kekSalt;
  final String keyId;
  final Uint8List nonce;
  final DateTime createdAt;
}

_Header _parseHeader(Map<String, dynamic> json) {
  if (json['format'] != _formatName) {
    throw const RecoveryPackageException(RecoveryPackageError.notARecoveryPackage);
  }
  if (json['version'] != recoveryPackageFormatVersion ||
      json['kdf'] != 'hkdf-sha256' ||
      json['cipher'] != 'aes-256-gcm') {
    throw const RecoveryPackageException(RecoveryPackageError.unsupportedVersion);
  }
  try {
    final kekSalt = base64Decode(json['kekSalt'] as String);
    final nonce = base64Decode(json['nonce'] as String);
    final keyId = json['keyId'] as String;
    final createdAt = DateTime.parse(json['createdAt'] as String);
    if (kekSalt.length != 16 ||
        nonce.length != 12 ||
        !RegExp(r'^[0-9a-f]{16}$').hasMatch(keyId)) {
      throw const RecoveryPackageException(RecoveryPackageError.malformed);
    }
    return _Header(kekSalt, keyId, nonce, createdAt.toUtc());
  } on FormatException {
    throw const RecoveryPackageException(RecoveryPackageError.malformed);
  } on TypeError {
    throw const RecoveryPackageException(RecoveryPackageError.malformed);
  }
}

/// Reads what can be shown before the key is entered. Validates structure,
/// not authenticity.
Future<RecoveryPackageSummary> readRecoveryPackageSummary(File package) async {
  final layout = await _readLayout(package);
  final header = _parseHeader(layout.headerJson);
  return RecoveryPackageSummary(
    createdAt: header.createdAt,
    keyId: header.keyId,
    databaseBytes: layout.dbLength,
  );
}

/// Fully verifies [package] with [backupKey] and writes its database to
/// [databaseOutput]. On any failure [databaseOutput] is removed and a
/// [RecoveryPackageException] is thrown; nothing else is touched.
Future<OpenedRecoveryPackage> openRecoveryPackage(
  File package,
  SecretCode backupKey, {
  required File databaseOutput,
}) async {
  final layout = await _readLayout(package);
  final header = _parseHeader(layout.headerJson);

  final material = BackupKeyMaterial.derive(backupKey, kekSalt: header.kekSalt);
  if (material.keyId != header.keyId) {
    throw const RecoveryPackageException(RecoveryPackageError.differentBackupKey);
  }

  final Map<String, dynamic> payload;
  try {
    final plain = _gcm(
      encrypt: false,
      key: material.wrappingKey,
      nonce: header.nonce,
      aad: layout.aad,
      input: layout.payload,
    );
    payload = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  } on InvalidCipherTextException {
    throw const RecoveryPackageException(RecoveryPackageError.authenticationFailed);
  } on FormatException {
    throw const RecoveryPackageException(RecoveryPackageError.malformed);
  } on TypeError {
    throw const RecoveryPackageException(RecoveryPackageError.malformed);
  }

  final String databaseKey;
  final Uint8List expectedHash;
  final String packageId;
  final int schemaVersion;
  try {
    databaseKey = payload['databaseKey'] as String;
    expectedHash = hexToBytes(payload['databaseSha256'] as String);
    packageId = payload['packageId'] as String;
    schemaVersion = payload['schemaVersion'] as int;
    if (!isWellFormedDatabaseKey(databaseKey) ||
        expectedHash.length != 32 ||
        payload['databaseBytes'] != layout.dbLength) {
      throw const RecoveryPackageException(RecoveryPackageError.malformed);
    }
  } on FormatException {
    throw const RecoveryPackageException(RecoveryPackageError.malformed);
  } on TypeError {
    throw const RecoveryPackageException(RecoveryPackageError.malformed);
  }

  final digest = SHA256Digest();
  try {
    final sink = databaseOutput.openWrite();
    try {
      await for (final chunk in package.openRead(
        layout.dbOffset,
        layout.dbOffset + layout.dbLength,
      )) {
        final bytes = Uint8List.fromList(chunk);
        digest.update(bytes, 0, bytes.length);
        sink.add(bytes);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  } on FileSystemException {
    if (await databaseOutput.exists()) {
      await databaseOutput.delete();
    }
    throw const RecoveryPackageException(RecoveryPackageError.malformed);
  }
  final actualHash = Uint8List(digest.digestSize);
  digest.doFinal(actualHash, 0);
  if (!constantTimeEquals(actualHash, expectedHash)) {
    await databaseOutput.delete();
    throw const RecoveryPackageException(
      RecoveryPackageError.databaseIntegrityFailed,
    );
  }

  return OpenedRecoveryPackage(
    summary: RecoveryPackageSummary(
      createdAt: header.createdAt,
      keyId: header.keyId,
      databaseBytes: layout.dbLength,
    ),
    packageId: packageId,
    databaseKey: databaseKey,
    schemaVersion: schemaVersion,
    backupKeyMaterial: BackupKeyMaterial(
      kekSalt: material.kekSalt,
      wrappingKey: material.wrappingKey,
      keyId: material.keyId,
      createdAt: DateTime.now().toUtc(),
    ),
  );
}
