import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/auth/pin_policy.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/core/security/secret_code.dart';

import '../controllers/auth_controller.dart';
import '../controllers/auth_providers.dart';
import '../widgets/pin_field.dart';
import '../widgets/recovery_code_display.dart';

/// Reset a forgotten Admin PIN with the Admin Recovery Code (docs/30 R1).
/// Works offline. Only the PIN is reset — the data and its encryption key
/// are not touched.
class PinRecoveryScreen extends ConsumerStatefulWidget {
  const PinRecoveryScreen({super.key});

  @override
  ConsumerState<PinRecoveryScreen> createState() => _PinRecoveryScreenState();
}

class _PinRecoveryScreenState extends ConsumerState<PinRecoveryScreen> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _confirmPin = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _newCode;
  bool _codeNotSaved = false;

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!PinPolicy.isValid(_pin.text)) {
      setState(() => _error = 'The new PIN must be exactly 6 digits.');
      return;
    }
    if (_pin.text != _confirmPin.text) {
      _pin.clear();
      _confirmPin.clear();
      setState(() => _error = 'The two new PINs do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final issued = await ref
          .read(authControllerProvider.notifier)
          .resetPinWithRecoveryCode(
            recoveryCode: _code.text,
            newPin: _pin.text,
          );
      _code.clear();
      if (mounted) {
        setState(() {
          _newCode = issued.recoveryCode;
          _codeNotSaved = !issued.recoveryCodeSaved;
        });
      }
    } on AccountLockedFailure catch (f) {
      if (mounted) {
        setState(
          () => _error =
              'Too many wrong codes. Try again in ${f.retryAfter.inSeconds + 1} seconds.',
        );
      }
    } on Failure catch (f) {
      if (mounted) {
        setState(() => _error = f.message);
      }
    } finally {
      _pin.clear();
      _confirmPin.clear();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(authControllerProvider.notifier);
    final newCode = _newCode;
    if (newCode != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PIN reset — new recovery code')),
        body: SafeArea(
          child: RecoveryCodeDisplay(
            code: newCode,
            kind: SecretCodeKind.adminRecovery,
            onConfirmed: () =>
                controller.completeAfterRecoveryCode(codeWasShown: true),
          ),
        ),
      );
    }
    if (_codeNotSaved) {
      return Scaffold(
        appBar: AppBar(title: const Text('PIN reset')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Your new PIN is set. A new recovery code could not be saved, '
              'so your previous Admin Recovery Code still works. Please create '
              'a new one from More → Admin Recovery Code.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () =>
                  controller.completeAfterRecoveryCode(codeWasShown: false),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final status = ref.watch(adminRecoveryStatusProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Admin PIN'),
        leading: BackButton(onPressed: () => context.go(Routes.login)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Enter the Admin Recovery Code (it starts with AR) and choose a '
              'new PIN. Your data will not be changed.',
              style: theme.textTheme.bodyLarge,
            ),
            if (status != null && !status.exists) ...[
              const SizedBox(height: 12),
              Text(
                'No Admin Recovery Code has been set up on this phone.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            TextField(
              key: const ValueKey('recover-code'),
              controller: _code,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              // Tells the keyboard not to learn or suggest what is typed.
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Admin Recovery Code',
                hintText: 'AR-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXX',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            PinField(
              key: const ValueKey('recover-pin'),
              controller: _pin,
              label: 'New 6-digit PIN',
              enabled: !_busy,
            ),
            const SizedBox(height: 16),
            PinField(
              key: const ValueKey('recover-confirm-pin'),
              controller: _confirmPin,
              label: 'Confirm new PIN',
              enabled: !_busy,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('recover-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('recover-submit'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Reset PIN'),
            ),
          ],
        ),
      ),
    );
  }
}
