import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/core/widgets/database_state_view.dart';
import 'package:referredline/core/widgets/master_widgets.dart';
import 'package:referredline/domain/entities/awc.dart';

import '../providers/awc_providers.dart';
import 'awc_list_screen.dart' show awcCandidate;

/// Possible duplicates review: groups of AWCs with the same name, village
/// and subcentre number. Read-only — nothing is merged, changed or deleted.
class AwcDuplicatesScreen extends ConsumerWidget {
  const AwcDuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(awcDuplicateGroupsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Possible duplicate AWCs')),
      body: DatabaseStateView<List<List<Awc>>>(
        value: groups,
        onRetry: () => retryAwcs(ref),
        builder: (groups) => groups.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No possible duplicates found.',
                    key: ValueKey('awc-duplicates-empty'),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'These AWCs have the same name, village and subcentre '
                    'number. Please check whether they are the same AWC. '
                    'Nothing is changed automatically.',
                  ),
                  const SizedBox(height: 12),
                  for (final group in groups)
                    Card(
                      key: const ValueKey('awc-duplicate-group'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            for (final awc in group)
                              DuplicateCandidateTile(
                                candidate: awcCandidate(
                                  awc,
                                  onTap: () => context.go(Routes.awcDetail(awc.id)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
