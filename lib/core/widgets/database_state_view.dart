import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:referredline/data/local/database_connection.dart';

/// Shows [value]'s data, a spinner while it loads, or — if the local data
/// cannot be opened — a plain message with **Try again**
/// (docs/35_PHASE_1_5_PLAN.md §11, decision D5).
///
/// No technical detail is shown, and there is deliberately no Restore
/// button (Backup/Restore UI is out of scope).
class DatabaseStateView<T> extends StatelessWidget {
  const DatabaseStateView({
    required this.value,
    required this.onRetry,
    required this.builder,
    super.key,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) => value.when(
    skipLoadingOnReload: true,
    skipLoadingOnRefresh: true,
    data: builder,
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => DataUnavailableMessage(error: error, onRetry: onRetry),
  );
}

/// The error behind [error], without the provider wrappers Riverpod adds.
Object rootError(Object error) {
  var current = error;
  while (current is ProviderException) {
    current = current.exception;
  }
  return current;
}

/// True if [error] means the database key is unavailable (data locked).
bool isDataLocked(Object error) =>
    rootError(error) is DatabaseKeyUnavailableException;

class DataUnavailableMessage extends StatelessWidget {
  const DataUnavailableMessage({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = isDataLocked(error);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const ValueKey('data-unavailable'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              locked ? Icons.lock_outline : Icons.error_outline,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              locked
                  ? 'Your data is locked right now.'
                  : 'Your data could not be opened right now.',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your data is NOT deleted.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('data-try-again'),
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// For a save that failed for a reason other than a message-carrying
/// `Failure`: the plain locked message, or a plain "could not save".
String saveErrorMessage(Object error) => isDataLocked(error)
    ? 'Your data is locked right now. Your data is NOT deleted. Try again.'
    : 'This could not be saved right now. Nothing was changed. Try again.';
