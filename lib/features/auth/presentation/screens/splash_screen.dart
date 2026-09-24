import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/database_provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../controllers/auth_controller.dart';

/// Shown while the stored auth state is read at startup (a local, offline
/// read — normally a brief moment), and when it cannot be read. Failures are
/// explained in plain words; the only technical detail is a short reference
/// for support, never secret material.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final error = auth.hasError ? auth.error : null;
    final theme = Theme.of(context);

    if (error == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppConstants.appName),
              SizedBox(height: 16),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }

    final (title, body, reference, canRestore) = switch (error) {
      DatabaseKeyUnavailableException(:final reason) => (
        'Your data is locked',
        'The app could not unlock the data saved on this phone. '
            'Your existing data has NOT been deleted.\n\n'
            'To continue, restore from your backup file using the Backup '
            'Recovery Key. If you do not have them, contact your RBSK '
            'administrator. Do not uninstall the app or clear its data.',
        reason.name,
        true,
      ),
      SecureStorageUnavailableException() => (
        'Secure storage could not be read',
        'This phone\'s secure storage could not be read just now. Nothing '
            'has been deleted. Please try again, or restart the phone.',
        'secureStorageUnavailable',
        false,
      ),
      _ => (
        'Could not open the local data',
        'Could not open the local data on this phone. Nothing has been '
            'deleted. Please try again.',
        null,
        false,
      ),
    };

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              key: const ValueKey('splash-error'),
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(body, style: theme.textTheme.bodyLarge),
            if (reference != null) ...[
              const SizedBox(height: 12),
              Text('Reference: $reference', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 24),
            if (canRestore)
              FilledButton(
                key: const ValueKey('splash-restore'),
                onPressed: () => context.go(Routes.restore),
                child: const Text('Restore from backup'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('splash-retry'),
              onPressed: () => ref.invalidate(appDatabaseProvider),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
