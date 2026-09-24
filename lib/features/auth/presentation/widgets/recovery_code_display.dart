import 'package:flutter/material.dart';
import 'package:referredline/core/platform/recovery_file_gateway.dart';
import 'package:referredline/core/security/secret_code.dart';

/// Shows a recovery secret exactly once, then asks the person to confirm
/// they wrote it down (tick + type its last group) before continuing.
/// Screenshots and screen recording are blocked while it is visible.
class RecoveryCodeDisplay extends StatefulWidget {
  const RecoveryCodeDisplay({
    required this.code,
    required this.kind,
    required this.onConfirmed,
    super.key,
  });

  /// The formatted code, e.g. `AR-XXXX-…-XXX`.
  final String code;
  final SecretCodeKind kind;
  final Future<void> Function() onConfirmed;

  @override
  State<RecoveryCodeDisplay> createState() => _RecoveryCodeDisplayState();
}

class _RecoveryCodeDisplayState extends State<RecoveryCodeDisplay> {
  final _check = TextEditingController();
  bool _written = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    setSecureScreen(true);
  }

  @override
  void dispose() {
    setSecureScreen(false);
    _check.dispose();
    super.dispose();
  }

  String get _lastGroup => widget.code.split('-').last.toUpperCase();

  bool get _canContinue =>
      !_busy && _written && _check.text.trim().toUpperCase() == _lastGroup;

  Future<void> _continue() async {
    setState(() => _busy = true);
    try {
      await widget.onConfirmed();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = widget.kind == SecretCodeKind.adminRecovery;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          isAdmin ? 'Your Admin Recovery Code' : 'Your Backup Recovery Key',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          isAdmin
              ? 'If the Admin PIN is ever forgotten, this code lets an '
                    'authorised person set a new PIN on this phone. '
                    'Your data stays safe. It is shown only once.'
              : 'This key opens the encrypted backups made on this phone. '
                    'Without it, a backup cannot be restored. '
                    'It is shown only once.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.code,
            key: const ValueKey('recovery-code-text'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '• Write it on paper now.\n'
          '• Keep the paper in a safe place, away from this phone.\n'
          '• Do not photograph it or send it in a message.\n'
          '${isAdmin ? '• Anyone with this code and this phone can reset the Admin PIN.' : '• Anyone with this key and a backup file can read that backup.'}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          key: const ValueKey('recovery-code-written'),
          value: _written,
          onChanged: _busy ? null : (v) => setState(() => _written = v ?? false),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I have written it down and will keep it safe, '
            'separate from this phone.',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('recovery-code-confirm'),
          controller: _check,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'To check, type the last 3 characters of the code',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('recovery-code-continue'),
          onPressed: _canContinue ? _continue : null,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }
}
