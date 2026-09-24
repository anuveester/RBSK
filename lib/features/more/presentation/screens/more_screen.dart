import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/rbac/more_menu_items.dart';
import '../../../../data/local/enums.dart';
import '../../../../domain/entities/auth_status.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/auth_providers.dart';

/// More destination. Entries come from the RBAC read model; those with a
/// route open their screen, the rest are inert labels for later phases.
/// Logout is available to everyone.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(authControllerProvider).value;
    final role = switch (status) {
      AuthAuthenticated(:final session) => session.role,
      _ => null,
    };
    final items = role == null ? const <MoreMenuItem>[] : moreMenuItemsFor(role);
    final recovery = role == AppRole.ADMIN
        ? ref.watch(adminRecoveryStatusProvider).value
        : null;
    final needsRecoveryCode =
        recovery != null && (!recovery.exists || !recovery.acknowledged);

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          if (needsRecoveryCode)
            ListTile(
              key: const ValueKey('more-recovery-warning'),
              leading: Icon(
                Icons.warning_amber,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Admin Recovery Code needs attention'),
              subtitle: const Text('Create one now so a forgotten PIN can be reset.'),
              onTap: () => context.go(
                items.firstWhere((i) => i.label == 'Admin Recovery Code').route!,
              ),
            ),
          for (final item in items)
            ListTile(
              key: ValueKey('more-item-${item.label}'),
              title: Text(item.label),
              subtitle: item.route == null ? const Text('Not available yet.') : null,
              enabled: item.route != null,
              trailing: item.route == null ? null : const Icon(Icons.chevron_right),
              onTap: item.route == null ? null : () => context.go(item.route!),
            ),
          if (items.isNotEmpty) const Divider(),
          ListTile(
            key: const ValueKey('more-logout'),
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            onTap: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
    );
  }
}
