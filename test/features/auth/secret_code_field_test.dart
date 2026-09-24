import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/features/auth/presentation/widgets/pin_field.dart';
import 'package:referredline/features/auth/presentation/widgets/secret_code_field.dart';

void main() {
  Future<void> showMenuFor(WidgetTester tester, Widget field) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: field))));
    await tester.enterText(find.byType(TextField), 'SYNTHETICCODE');
    await tester.pump();
    // Select the text and open the menu, as a long-press would.
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.userUpdateTextEditingValue(
      editable.textEditingValue.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
      ),
      SelectionChangedCause.longPress,
    );
    await tester.pump();
    editable.showToolbar();
    await tester.pumpAndSettle();
  }

  testWidgets('a plain text field offers Copy (control)', (tester) async {
    await showMenuFor(tester, TextField(controller: TextEditingController()));
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('a recovery-secret field never offers Copy or Cut', (tester) async {
    await showMenuFor(
      tester,
      SecretCodeField(controller: TextEditingController(), label: 'Code'),
    );
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Cut'), findsNothing);
    expect(find.text('Select all'), findsOneWidget, reason: 'menu is shown');
  });

  testWidgets('secret and PIN fields ask the keyboard not to learn or '
      'suggest what is typed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SecretCodeField(controller: TextEditingController(), label: 'Code'),
              PinField(controller: TextEditingController(), label: 'PIN'),
            ],
          ),
        ),
      ),
    );
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.enableIMEPersonalizedLearning, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.autocorrect, isFalse);
    }
  });
}
