import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/data/local/database_provider.dart';
import 'package:referredline/data/local/recovery/recovery_package.dart';
import 'package:referredline/domain/entities/auth_status.dart';
import 'package:referredline/features/auth/presentation/controllers/auth_controller.dart';
import 'package:referredline/features/auth/presentation/controllers/auth_providers.dart';
import 'package:referredline/features/auth/presentation/widgets/pin_confirm_dialog.dart';
import 'package:referredline/features/auth/presentation/widgets/recovery_code_display.dart';

import '../recovery_messages.dart';

/// Admin-only controlled encrypted backup (docs/30 R5): set up the Backup
/// Recovery Key, and create encrypted recovery packages that the user saves
/// wherever they choose through Android's file picker.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  Future<BackupKeyMaterial?>? _material;
  String? _newKey;
  String? _message;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _material = ref.read(databaseRecoveryServiceProvider).currentBackupKey();
  }

  String? get _adminId => switch (ref.read(authControllerProvider).value) {
    AuthAuthenticated(:final session) => session.userId,
    _ => null,
  };

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } on Failure catch (f) {
      if (mounted) {
        setState(() => _error = f.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = recoveryErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _setUpKey({required bool replacing}) async {
    final adminId = _adminId;
    if (adminId == null) {
      return;
    }
    final pin = await askForCurrentPin(
      context,
      title: 'Confirm it is you',
      message: replacing
          ? 'Enter your PIN to create a new Backup Recovery Key. Backups made '
                'before this will still need the OLD key.'
          : 'Enter your PIN to set up the Backup Recovery Key.',
    );
    if (pin == null) {
      return;
    }
    await _run(() async {
      // The service checks the session and the PIN itself.
      final auth = await ref.read(authRepositoryProvider.future);
      final audit = await ref.read(securityAuditProvider.future);
      final key = await ref
          .read(databaseRecoveryServiceProvider)
          .createBackupKey(auth: auth, currentPin: pin, audit: audit);
      setState(() => _newKey = key.formatted);
    });
  }

  Future<void> _export() async {
    final adminId = _adminId;
    if (adminId == null) {
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create encrypted backup?'),
        content: const Text(
          'An encrypted backup file will be made. Next, choose where to save '
          'it — for example Downloads, a USB drive, or a cloud drive app. '
          'The file can only be opened with the Backup Recovery Key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('backup-export-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create backup'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) {
      return;
    }
    final pin = await askForCurrentPin(
      context,
      title: 'Confirm it is you',
      message: 'Enter your PIN to create the encrypted backup.',
    );
    if (pin == null) {
      return;
    }
    await _run(() async {
      final service = ref.read(databaseRecoveryServiceProvider);
      final db = await ref.read(appDatabaseProvider.future);
      final auth = await ref.read(authRepositoryProvider.future);
      final audit = await ref.read(securityAuditProvider.future);
      // The service checks the session and the PIN itself.
      final package = await service.createPackage(
        db,
        auth: auth,
        currentPin: pin,
        audit: audit,
      );
      try {
        final saved = await ref
            .read(recoveryFileGatewayProvider)
            .saveToDevice(package, p.basename(package.path));
        setState(
          () => _message = saved
              ? 'Backup saved. Keep it with the Backup Recovery Key stored '
                    'separately.'
              : 'Backup not saved (cancelled).',
        );
      } finally {
        await service.discardExport(package);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final newKey = _newKey;
    if (newKey != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Backup Recovery Key')),
        body: SafeArea(
          child: RecoveryCodeDisplay(
            code: newKey,
            kind: SecretCodeKind.backupRecovery,
            onConfirmed: () async {
              setState(() {
                _newKey = null;
                _reload();
              });
            },
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup Export')),
      body: FutureBuilder<BackupKeyMaterial?>(
        future: _material,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final material = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (material == null) ...[
                const Text(
                  'Before making backups, set up the Backup Recovery Key. '
                  'It is needed to open any backup, for example on a new '
                  'phone.',
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey('backup-setup-key'),
                  onPressed: _busy ? null : () => _setUpKey(replacing: false),
                  child: const Text('Set up the Backup Recovery Key'),
                ),
              ] else ...[
                Text(
                  'Backup Recovery Key ID: ${material.displayId}',
                  key: const ValueKey('backup-key-id'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Backups are encrypted. The patient data inside stays '
                  'encrypted, and the file can only be opened with the Backup '
                  'Recovery Key.',
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey('backup-export'),
                  onPressed: _busy ? null : _export,
                  child: const Text('Create encrypted backup'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  key: const ValueKey('backup-replace-key'),
                  onPressed: _busy ? null : () => _setUpKey(replacing: true),
                  child: const Text('Replace the Backup Recovery Key'),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, key: const ValueKey('backup-message')),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const ValueKey('backup-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
