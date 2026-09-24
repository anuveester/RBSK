import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/platform/recovery_file_gateway.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/features/auth/presentation/widgets/recovery_code_display.dart';

/// A screen that protects itself for its whole lifetime, as the restore and
/// PIN-recovery screens do.
class _ProtectedScreen extends StatefulWidget {
  const _ProtectedScreen({required this.showCode});

  final bool showCode;

  @override
  State<_ProtectedScreen> createState() => _ProtectedScreenState();
}

class _ProtectedScreenState extends State<_ProtectedScreen> {
  @override
  void initState() {
    super.initState();
    SecureScreen.acquire();
  }

  @override
  void dispose() {
    SecureScreen.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: widget.showCode
        ? RecoveryCodeDisplay(
            code: SecretCode.generate(SecretCodeKind.backupRecovery).formatted,
            kind: SecretCodeKind.backupRecovery,
            onConfirmed: () async {},
          )
        : const Text('entering a key'),
  );
}

void main() {
  final calls = <bool>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.rbsk.referredline/recovery_files'),
          (call) async {
            if (call.method == 'setSecureScreen') {
              calls.add((call.arguments as Map)['enabled'] as bool);
            }
            return null;
          },
        );
  });

  test('protection stays on until the last holder releases it', () async {
    SecureScreen.acquire();
    SecureScreen.acquire();
    SecureScreen.release();
    await Future<void>.delayed(Duration.zero);
    expect(calls, [true]);
    SecureScreen.release();
    await Future<void>.delayed(Duration.zero);
    expect(calls, [true, false]);
    // An extra release is ignored rather than going negative.
    SecureScreen.release();
    SecureScreen.acquire();
    await Future<void>.delayed(Duration.zero);
    expect(calls, [true, false, true]);
    SecureScreen.release();
    expect(SecureScreen.activeLeases, 0);
  });

  testWidgets('closing a one-time code shown inside a protected screen does '
      'not switch protection off for that screen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _ProtectedScreen(showCode: true)),
    );
    expect(SecureScreen.activeLeases, 2);

    await tester.pumpWidget(
      const MaterialApp(home: _ProtectedScreen(showCode: false)),
    );
    expect(SecureScreen.activeLeases, 1);
    expect(calls, [true], reason: 'never switched off while still needed');

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(SecureScreen.activeLeases, 0);
    expect(calls, [true, false]);
  });
}
