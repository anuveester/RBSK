import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/pin_policy.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failure.dart';
import '../controllers/auth_controller.dart';
import '../controllers/auth_providers.dart';
import '../widgets/pin_field.dart';

/// Login: pick your name from the active users, then enter your PIN
/// (docs/27_PHASE_1_4_PLAN.md §0.2). No self-signup.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _pin = TextEditingController();
  String? _selectedUserId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && _selectedUserId != null && PinPolicy.isValid(_pin.text);

  Future<void> _submit() async {
    final userId = _selectedUserId;
    final pin = _pin.text;
    if (userId == null || !PinPolicy.isValid(pin)) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(userId: userId, pin: pin);
    } on AccountLockedFailure catch (f) {
      if (mounted) {
        final seconds = f.retryAfter.inSeconds + 1;
        setState(
          () => _error =
              'Too many incorrect attempts. Try again in $seconds seconds.',
        );
      }
    } on Failure catch (f) {
      if (mounted) {
        setState(() => _error = f.message);
      }
    } finally {
      _pin.clear();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final users = ref.watch(activeUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.appName)),
      body: SafeArea(
        child: users.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('Could not load accounts.')),
          data: (list) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Who is logging in?', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final user in list)
                ListTile(
                  key: ValueKey('login-user-${user.id}'),
                  title: Text(user.displayName),
                  leading: Icon(
                    _selectedUserId == user.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  selected: _selectedUserId == user.id,
                  enabled: !_busy,
                  onTap: () => setState(() {
                    _selectedUserId = user.id;
                    _error = null;
                  }),
                ),
              const SizedBox(height: 16),
              PinField(
                key: const ValueKey('login-pin'),
                controller: _pin,
                label: 'PIN',
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const ValueKey('login-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('login-submit'),
                onPressed: _canSubmit ? _submit : null,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Log in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
