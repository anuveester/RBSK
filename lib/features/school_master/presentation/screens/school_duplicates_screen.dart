import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/core/widgets/database_state_view.dart';
import 'package:referredline/core/widgets/master_widgets.dart';
import 'package:referredline/domain/entities/school.dart';

import '../providers/school_providers.dart';
import 'school_list_screen.dart' show schoolCandidate;

/// Possible duplicates review (docs/35_PHASE_1_5_PLAN.md §7): groups of
/// schools with the same name. Read-only — nothing here merges, changes or
/// deletes a record.
class SchoolDuplicatesScreen extends ConsumerWidget {
  const SchoolDuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(schoolDuplicateGroupsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Possible duplicate schools')),
      body: DatabaseStateView<List<List<School>>>(
        value: groups,
        onRetry: () => retrySchools(ref),
        builder: (groups) => groups.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No possible duplicates found.',
                    key: ValueKey('school-duplicates-empty'),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'These schools have the same name. Please check whether '
                    'they are the same school. Nothing is changed '
                    'automatically.',
                  ),
                  const SizedBox(height: 12),
                  for (final group in groups)
                    Card(
                      key: const ValueKey('school-duplicate-group'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            for (final school in group)
                              DuplicateCandidateTile(
                                candidate: schoolCandidate(
                                  school,
                                  onTap: () =>
                                      context.go(Routes.schoolDetail(school.id)),
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
