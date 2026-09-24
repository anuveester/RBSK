import 'package:flutter/material.dart';

/// Entry for a recovery secret (Admin Recovery Code or Backup Recovery
/// Key). Keeps what is typed away from the keyboard and the clipboard:
///
/// - no suggestions, no autocorrect, and a password-type keyboard, so the
///   keyboard does not learn or suggest it;
/// - `enableIMEPersonalizedLearning: false` asks the keyboard for its
///   incognito mode (Android `IME_FLAG_NO_PERSONALIZED_LEARNING`);
/// - the long-press menu offers Paste but not Copy or Cut, so the secret is
///   not put on the clipboard, where other apps may be able to read it.
///
/// Whether a particular keyboard honours these requests can only be checked
/// on a real phone (docs/32).
class SecretCodeField extends StatelessWidget {
  const SecretCodeField({
    required this.controller,
    required this.label,
    this.hint,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: TextInputType.visiblePassword,
      textCapitalization: TextCapitalization.characters,
      contextMenuBuilder: secretFieldContextMenu,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// The standard text-field menu without Copy and Cut.
Widget secretFieldContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: [
      for (final item in editableTextState.contextMenuButtonItems)
        if (item.type != ContextMenuButtonType.copy &&
            item.type != ContextMenuButtonType.cut)
          item,
    ],
  );
}
