import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';

/// More destination (docs/02_SCREEN_MAP.md §Navigation shell): the
/// lower-frequency screens. Phase 1.5 adds the School and AWC masters; the
/// other entries (staff, settings, backup, audit log) belong to later phases.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Masters', style: theme.textTheme.titleMedium),
          ),
          ListTile(
            key: const ValueKey('more-schools'),
            leading: const Icon(Icons.school_outlined),
            title: const Text('School Master'),
            subtitle: const Text('Schools: add, search, edit'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.schools),
          ),
          ListTile(
            key: const ValueKey('more-awcs'),
            leading: const Icon(Icons.child_care_outlined),
            title: const Text('AWC Master'),
            subtitle: const Text('Anganwadi centres: add, search, edit'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.awcs),
          ),
        ],
      ),
    );
  }
}
