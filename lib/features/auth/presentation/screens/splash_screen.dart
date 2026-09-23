import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../controllers/auth_controller.dart';

/// Shown only while the stored auth state is read at startup (a local,
/// offline read — normally a brief moment). If that read fails, says so
/// instead of spinning forever.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = ref.watch(authControllerProvider).hasError;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(AppConstants.appName),
              const SizedBox(height: 16),
              if (failed)
                const Text(
                  'Could not open the local data on this device.',
                  key: ValueKey('splash-error'),
                  textAlign: TextAlign.center,
                )
              else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
