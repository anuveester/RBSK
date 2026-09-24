import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:referredline/core/auth/pin_policy.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/platform/recovery_file_gateway.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/core/utils/id_generator.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/database_provider.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/local/recovery/database_recovery_service.dart';
import 'package:referredline/data/local/recovery/recovery_package.dart';
import 'package:referredline/domain/entities/auth_status.dart';
import 'package:referredline/features/auth/presentation/controllers/auth_controller.dart';
import 'package:referredline/features/auth/presentation/controllers/auth_providers.dart';
import 'package:referredline/features/auth/presentation/widgets/pin_field.dart';
import 'package:referredline/features/auth/presentation/widgets/recovery_code_display.dart';
import 'package:referredline/features/auth/presentation/widgets/secret_code_field.dart';

import '../recovery_messages.dart';

enum _Step { choose, enterKey, confirm, adminAccess, showCode, notAvailable }

/// Restore data from an encrypted recovery package (docs/30 R5), then set
/// Admin access on this phone with the Backup Recovery Key.
///
/// Offered only where it is safe: on a phone with no accounts yet (first
/// run), or when the database key is unavailable. Existing data is never
/// deleted — it is kept aside under another name. Setting Admin access is
/// offered only while no Admin can log in on this phone.
class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  _Step? _step;
  bool _resolvingStep = false;
  RestoreContext _context = RestoreContext.newDevice;
  File? _packageFile;
  RecoveryPackageSummary? _summary;
  VerifiedRestore? _verified;
  bool _understood = false;
  bool _busy = false;
  String? _error;
  String? _errorRef;
  String? _adminId;
  String? _issuedCode;
  bool _issuedNotSaved = false;

  final _backupKey = TextEditingController();
  final _pin = TextEditingController();
  final _confirmPin = TextEditingController();

  // Captured up front: `ref` must not be used in dispose().
  late final DatabaseRecoveryService _service;

  @override
  void initState() {
    super.initState();
    _service = ref.read(databaseRecoveryServiceProvider);
    // The Backup Recovery Key is typed on this screen at several steps.
    SecureScreen.acquire();
  }

  @override
  void dispose() {
    final verified = _verified;
    if (verified != null) {
      // ignore: unawaited_futures
      _service.discard(verified);
    }
    final file = _packageFile;
    if (file != null) {
      // ignore: unawaited_futures
      _deleteIfPresent(file);
    }
    SecureScreen.release();
    _backupKey.dispose();
    _pin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<_Step> _initialStep() async {
    final auth = ref.read(authControllerProvider);
    if (auth.hasError && auth.error is DatabaseKeyUnavailableException) {
      _context = RestoreContext.keyUnavailable;
      return _Step.choose;
    }
    final status = auth.value;
    if (status is AuthUninitialized) {
      _context = RestoreContext.newDevice;
      return _Step.choose;
    }
    if (status is AuthLoggedOut) {
      final canLogIn = await ref.read(adminCanLogInProvider.future);
      return canLogIn ? _Step.notAvailable : _Step.adminAccess;
    }
    return _Step.notAvailable;
  }

  void _fail(Object e) {
    setState(() {
      _error = e is Failure ? e.message : recoveryErrorMessage(e);
      _errorRef = recoveryErrorReference(e);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _errorRef = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        _fail(e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _choose() => _run(() async {
    final work = await ref.read(recoveryWorkDirectoryProvider)();
    await work.create(recursive: true);
    final destination = File(p.join(work.path, 'import-${generateUuidV4()}.rbskrp'));
    final picked = await ref
        .read(recoveryFileGatewayProvider)
        .pickPackage(destination);
    if (picked == null) {
      return;
    }
    _packageFile = picked;
    final summary = await ref.read(databaseRecoveryServiceProvider).inspect(picked);
    setState(() {
      _summary = summary;
      _step = _Step.enterKey;
    });
  });

  Future<void> _verify() => _run(() async {
    final verified = await ref
        .read(databaseRecoveryServiceProvider)
        .verify(_packageFile!, _backupKey.text, context: _context);
    setState(() {
      _verified = verified;
      _step = _Step.confirm;
    });
  });

  Future<void> _install() => _run(() async {
    final verified = _verified!;
    // The database file is about to be moved; close the open connection
    // first (there is none if the key was unavailable).
    final db = ref.read(appDatabaseProvider).value;
    if (db != null) {
      await closeAppDatabase(db);
    }
    try {
      await ref
          .read(databaseRecoveryServiceProvider)
          .install(verified, confirmedByUser: true);
    } catch (_) {
      // Rolled back; a verified restore is single-use, so the key must be
      // checked again before another attempt.
      if (mounted) {
        setState(() {
          _step = _Step.enterKey;
          _understood = false;
        });
      }
      rethrow;
    } finally {
      // Success or failure, the connection closed above must be replaced:
      // after a failed (rolled-back) restore the previous data opens again.
      _verified = null;
      ref.invalidate(appDatabaseProvider);
    }
    final file = _packageFile;
    if (file != null && await file.exists()) {
      await file.delete();
    }
    _packageFile = null;
    await ref.read(authControllerProvider.future);
    setState(() => _step = _Step.adminAccess);
  });

  Future<void> _setAdminAccess() async {
    final adminId = _adminId;
    if (adminId == null) {
      setState(() => _error = 'Choose which Admin account to use.');
      return;
    }
    if (!PinPolicy.isValid(_pin.text) || _pin.text != _confirmPin.text) {
      _pin.clear();
      _confirmPin.clear();
      setState(
        () => _error = 'Enter the same 6-digit PIN in both PIN boxes.',
      );
      return;
    }
    await _run(() async {
      try {
        final issued = await ref
            .read(authControllerProvider.notifier)
            .restoreAdminAccess(
              backupKey: _backupKey.text,
              adminUserId: adminId,
              newPin: _pin.text,
            );
        _backupKey.clear();
        setState(() {
          _issuedCode = issued.recoveryCode;
          _issuedNotSaved = !issued.recoveryCodeSaved;
          _step = _Step.showCode;
        });
      } finally {
        _pin.clear();
        _confirmPin.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    if (step == null) {
      if (!_resolvingStep) {
        _resolvingStep = true;
        _initialStep().then((s) {
          if (mounted) {
            setState(() => _step = s);
          }
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final controller = ref.read(authControllerProvider.notifier);
    if (step == _Step.showCode) {
      final code = _issuedCode;
      if (code != null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Keep this code safe')),
          body: SafeArea(
            child: RecoveryCodeDisplay(
              code: code,
              kind: SecretCodeKind.adminRecovery,
              onConfirmed: () =>
                  controller.completeAfterRecoveryCode(codeWasShown: true),
            ),
          ),
        );
      }
      if (_issuedNotSaved) {
        return _scaffold([
          const Text(
            'Admin access is set. A new Admin Recovery Code could not be '
            'saved. Please create one from More → Admin Recovery Code.',
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () =>
                controller.completeAfterRecoveryCode(codeWasShown: false),
            child: const Text('Continue'),
          ),
        ]);
      }
    }

    return _scaffold(switch (step) {
      _Step.choose => _chooseStep(),
      _Step.enterKey => _enterKeyStep(),
      _Step.confirm => _confirmStep(),
      _Step.adminAccess => _adminAccessStep(),
      _ => [
        const Text(
          'Restoring is not available right now. Restoring is offered on a '
          'new phone, or when this phone\'s data is locked.',
        ),
      ],
    });
  }

  Widget _scaffold(List<Widget> children) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restore from backup'),
        leading: BackButton(onPressed: _busy ? null : () => context.go(Routes.splash)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ...children,
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey('restore-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              if (_errorRef != null)
                Text(
                  'Reference: $_errorRef',
                  style: theme.textTheme.bodySmall,
                ),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _chooseStep() => [
    Text(
      _context == RestoreContext.keyUnavailable
          ? 'The data on this phone is locked. You can restore it from a '
                'recovery package (backup file). The locked data will be kept '
                'aside, not deleted.'
          : 'Restore the data from a recovery package (backup file) made on '
                'the old phone. You will need the Backup Recovery Key.',
    ),
    const SizedBox(height: 24),
    FilledButton(
      key: const ValueKey('restore-choose'),
      onPressed: _busy ? null : _choose,
      child: const Text('Choose backup file'),
    ),
  ];

  List<Widget> _enterKeyStep() {
    final summary = _summary!;
    return [
      Text('Backup made on: ${_formatDate(summary.createdAt)}'),
      Text('Backup key ID: ${summary.keyDisplayId}'),
      const SizedBox(height: 16),
      const Text('Enter the Backup Recovery Key (it starts with BK).'),
      const SizedBox(height: 8),
      SecretCodeField(
        key: const ValueKey('restore-backup-key'),
        controller: _backupKey,
        enabled: !_busy,
        label: 'Backup Recovery Key',
        hint: 'BK-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXX',
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const ValueKey('restore-verify'),
        onPressed: _busy ? null : _verify,
        child: const Text('Check backup'),
      ),
    ];
  }

  List<Widget> _confirmStep() => [
    Text(
      'The backup is genuine and complete. '
      'Restore the data from ${_formatDate(_verified!.summary.createdAt)}?',
    ),
    const SizedBox(height: 12),
    Text(
      _context == RestoreContext.keyUnavailable
          ? 'The locked data on this phone will be kept aside under another '
                'name. It will not be deleted.'
          : 'Anything already set up on this phone will be kept aside under '
                'another name. It will not be deleted.',
    ),
    const SizedBox(height: 12),
    CheckboxListTile(
      key: const ValueKey('restore-understood'),
      value: _understood,
      onChanged: _busy ? null : (v) => setState(() => _understood = v ?? false),
      contentPadding: EdgeInsets.zero,
      title: const Text('I understand. Restore this backup.'),
    ),
    const SizedBox(height: 16),
    FilledButton(
      key: const ValueKey('restore-install'),
      onPressed: _busy || !_understood ? null : _install,
      child: const Text('Restore now'),
    ),
  ];

  List<Widget> _adminAccessStep() {
    final admins = (ref.watch(activeUsersProvider).value ?? const [])
        .where((u) => u.role == AppRole.ADMIN)
        .toList();
    return [
      const Text(
        'Set a new PIN for an Admin on this phone. This needs the Backup '
        'Recovery Key.',
      ),
      const SizedBox(height: 16),
      for (final admin in admins)
        ListTile(
          key: ValueKey('restore-admin-${admin.id}'),
          title: Text(admin.displayName),
          leading: Icon(
            _adminId == admin.id
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
          ),
          onTap: _busy ? null : () => setState(() => _adminId = admin.id),
        ),
      const SizedBox(height: 16),
      SecretCodeField(
        key: const ValueKey('restore-admin-backup-key'),
        controller: _backupKey,
        enabled: !_busy,
        label: 'Backup Recovery Key',
      ),
      const SizedBox(height: 16),
      PinField(
        key: const ValueKey('restore-admin-pin'),
        controller: _pin,
        label: 'New 6-digit PIN',
        enabled: !_busy,
      ),
      const SizedBox(height: 16),
      PinField(
        key: const ValueKey('restore-admin-confirm-pin'),
        controller: _confirmPin,
        label: 'Confirm new PIN',
        enabled: !_busy,
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const ValueKey('restore-admin-submit'),
        onPressed: _busy ? null : _setAdminAccess,
        child: const Text('Set Admin PIN'),
      ),
    ];
  }

  static Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  static String _formatDate(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }
}
