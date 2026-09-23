import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/auth/pin_policy.dart';

/// Masked, digits-only, exactly-6-digit PIN entry. The value lives only in
/// the [controller]; screens clear it after every attempt and never log it.
class PinField extends StatelessWidget {
  const PinField({
    required this.controller,
    required this.label,
    this.onChanged,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.number,
      maxLength: PinPolicy.length,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(PinPolicy.length),
      ],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
    );
  }
}
