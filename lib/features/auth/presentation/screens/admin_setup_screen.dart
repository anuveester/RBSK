import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/pin_policy.dart';
import '../../../../core/errors/failure.dart';
import '../controllers/auth_controller.dart';
import '../widgets/pin_field.dart';

/// First-run Admin setup (docs/27_PHASE_1_4_PLAN.md §0, decision 7). Only
/// reachable while no user exists; the router and `LocalAuthRepository`
/// both refuse it afterwards.
class AdminSetupScreen extends ConsumerStatefulWidget {
  const AdminSetupScreen({super.key});

  @override
  ConsumerState<AdminSetupScreen> createState() => _AdminSetupScreenState();
}

class _AdminSetupScreenState extends ConsumerState<AdminSetupScreen> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _confirmPin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final pin = _pin.text;
    final confirm = _confirmPin.text;

    String? error;
    if (name.isEmpty) {
      error = 'Enter the Administrator\'s name.';
    } else if (!PinPolicy.isValid(pin)) {
      error = 'PIN must be exactly ${PinPolicy.length} digits.';
    } else if (pin != confirm) {
      error = 'The two PINs do not match.';
    }
    if (error != null) {
      _clearPins();
      setState(() => _error = error);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .setupBootstrapAdmin(displayName: name, pin: pin);
    } on Failure catch (f) {
      if (mounted) {
        setState(() => _error = f.message);
      }
    } finally {
      _clearPins();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _clearPins() {
    _pin.clear();
    _confirmPin.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Set up Administrator')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'This device has no accounts yet. Create the Administrator '
              'account. This is done once.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'There is no PIN recovery in this version. Keep the PIN safe.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              key: const ValueKey('setup-name'),
              controller: _name,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Administrator name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            PinField(
              key: const ValueKey('setup-pin'),
              controller: _pin,
              label: '${PinPolicy.length}-digit PIN',
              enabled: !_busy,
            ),
            const SizedBox(height: 16),
            PinField(
              key: const ValueKey('setup-confirm-pin'),
              controller: _confirmPin,
              label: 'Confirm PIN',
              enabled: !_busy,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('setup-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('setup-submit'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Administrator'),
            ),
          ],
        ),
      ),
    );
  }
}
