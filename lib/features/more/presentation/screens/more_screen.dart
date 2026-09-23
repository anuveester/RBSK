import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/rbac/more_menu_items.dart';
import '../../../../domain/entities/auth_status.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

/// More destination. The only real behavior here is Logout (Phase 1.4
/// scope). The other entries come from the RBAC read model and are inert
/// labels — their screens belong to later phases.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(authControllerProvider).value;
    final items = switch (status) {
      AuthAuthenticated(:final session) => moreMenuItemsFor(session.role),
      _ => const <MoreMenuItem>[],
    };

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          for (final item in items)
            ListTile(
              key: ValueKey('more-item-${item.label}'),
              title: Text(item.label),
              subtitle: const Text('Not available yet.'),
              enabled: false,
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
