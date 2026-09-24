import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/domain/entities/auth_status.dart';
import 'package:referredline/features/auth/presentation/controllers/auth_controller.dart';
import 'package:referredline/features/auth/presentation/controllers/auth_providers.dart';
import 'package:referredline/features/auth/presentation/widgets/pin_confirm_dialog.dart';
import 'package:referredline/features/auth/presentation/widgets/recovery_code_display.dart';

/// Admin-only (route guard + RBAC read model): see whether an Admin
/// Recovery Code exists, and replace it (needs the current PIN).
class RecoveryCodeScreen extends ConsumerStatefulWidget {
  const RecoveryCodeScreen({super.key});

  @override
  ConsumerState<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends ConsumerState<RecoveryCodeScreen> {
  String? _newCode;
  String? _error;
  bool _busy = false;

  String? get _adminId => switch (ref.read(authControllerProvider).value) {
    AuthAuthenticated(:final session) => session.userId,
    _ => null,
  };

  Future<void> _createNew() async {
    final adminId = _adminId;
    if (adminId == null) {
      return;
    }
    final pin = await askForCurrentPin(
      context,
      title: 'Confirm it is you',
      message:
          'Enter your PIN to create a new Admin Recovery Code. '
          'The old code will stop working.',
    );
    if (pin == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = await ref.read(authRepositoryProvider.future);
      final code = await repository.createNewRecoveryCode(
        adminUserId: adminId,
        currentPin: pin,
      );
      if (mounted) {
        setState(() => _newCode = code);
      }
    } on Failure catch (f) {
      if (mounted) {
        setState(() => _error = f.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final newCode = _newCode;
    if (newCode != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New Admin Recovery Code')),
        body: SafeArea(
          child: RecoveryCodeDisplay(
            code: newCode,
            kind: SecretCodeKind.adminRecovery,
            onConfirmed: () async {
              final repository = await ref.read(authRepositoryProvider.future);
              await repository.confirmRecoveryCodeRecorded();
              ref.invalidate(adminRecoveryStatusProvider);
              if (mounted) {
                setState(() => _newCode = null);
              }
            },
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final status = ref.watch(adminRecoveryStatusProvider).value;
    final String statusText;
    if (status == null) {
      statusText = 'Checking…';
    } else if (!status.exists) {
      statusText =
          'No Admin Recovery Code is set up. Create one now — without it, a '
          'forgotten Admin PIN cannot be reset.';
    } else if (!status.acknowledged) {
      statusText =
          'A code exists but was never confirmed as written down. If you do '
          'not have it on paper, create a new one now.';
    } else {
      statusText = 'An Admin Recovery Code is set up and was confirmed.';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Recovery Code')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(statusText, key: const ValueKey('recovery-status')),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('recovery-create-new'),
            onPressed: _busy ? null : _createNew,
            child: const Text('Create a new recovery code'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
