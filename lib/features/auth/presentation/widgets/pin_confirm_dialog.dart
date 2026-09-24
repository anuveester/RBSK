import 'package:flutter/material.dart';
import 'package:referredline/core/auth/pin_policy.dart';

import 'pin_field.dart';

/// Asks for the current PIN before a sensitive action. Returns the entered
/// PIN, or null if cancelled. The PIN is not kept after the dialog closes.
Future<String?> askForCurrentPin(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PinConfirmDialog(title: title, message: message),
  );
}

class _PinConfirmDialog extends StatefulWidget {
  const _PinConfirmDialog({required this.title, required this.message});

  final String title;
  final String message;

  @override
  State<_PinConfirmDialog> createState() => _PinConfirmDialogState();
}

class _PinConfirmDialogState extends State<_PinConfirmDialog> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          PinField(
            key: const ValueKey('pin-confirm-field'),
            controller: _pin,
            label: 'Your PIN',
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pin-confirm-submit'),
          onPressed: PinPolicy.isValid(_pin.text)
              ? () => Navigator.of(context).pop(_pin.text)
              : null,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
