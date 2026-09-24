import 'dart:io';

import 'package:flutter/services.dart';

/// Moves recovery packages between the app and places the user chooses
/// (Downloads, a USB drive, a cloud drive app…) using Android's own document
/// picker (Storage Access Framework). The user always picks the location;
/// the app never writes outside its own storage by itself, and needs no
/// storage permission.
abstract interface class RecoveryFileGateway {
  /// Asks the user where to save [file]. False if they cancelled.
  Future<bool> saveToDevice(File file, String suggestedName);

  /// Asks the user to choose a package and copies it into [destination].
  /// Null if they cancelled.
  Future<File?> pickPackage(File destination);
}

/// Thrown when Android could not copy the file (not when the user cancels).
class RecoveryFileTransferException implements Exception {
  const RecoveryFileTransferException();
}

const MethodChannel _channel = MethodChannel(
  'com.rbsk.referredline/recovery_files',
);

class AndroidRecoveryFileGateway implements RecoveryFileGateway {
  const AndroidRecoveryFileGateway();

  @override
  Future<bool> saveToDevice(File file, String suggestedName) async {
    try {
      final uri = await _channel.invokeMethod<String>('saveFile', {
        'sourcePath': file.path,
        'suggestedName': suggestedName,
      });
      return uri != null;
    } on PlatformException {
      throw const RecoveryFileTransferException();
    }
  }

  @override
  Future<File?> pickPackage(File destination) async {
    try {
      final copied = await _channel.invokeMethod<bool>('openFile', {
        'destinationPath': destination.path,
      });
      return copied == true ? destination : null;
    } on PlatformException {
      throw const RecoveryFileTransferException();
    }
  }
}

/// Stops screenshots and screen recording (Android `FLAG_SECURE`) while a
/// recovery secret is visible or being typed.
///
/// Reference-counted: every screen that needs protection takes a lease in
/// `initState` and releases it in `dispose`, and the flag stays on until the
/// last lease is released. A plain on/off switch would let an inner widget
/// (e.g. the one-time code display inside the restore screen) turn the
/// protection off while the outer screen still shows a secret.
class SecureScreen {
  SecureScreen._();

  static int _leases = 0;

  static void acquire() {
    if (_leases++ == 0) {
      _apply(true);
    }
  }

  static void release() {
    if (_leases == 0) {
      return;
    }
    if (--_leases == 0) {
      _apply(false);
    }
  }

  /// Number of screens currently holding protection (for tests).
  static int get activeLeases => _leases;

  static Future<void> _apply(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSecureScreen', {'enabled': enabled});
    } on MissingPluginException {
      // Not running on Android.
    } on PlatformException {
      // Best effort.
    }
  }
}
