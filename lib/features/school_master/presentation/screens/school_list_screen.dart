import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/core/widgets/database_state_view.dart';
import 'package:referredline/core/widgets/master_widgets.dart';
import 'package:referredline/domain/entities/master_list_query.dart';
import 'package:referredline/domain/entities/school.dart';

import '../providers/school_providers.dart';

/// School Master List (docs/02_SCREEN_MAP.md screen 18): search by name or
/// code, filter by district, block and Active/Inactive/All.
class SchoolListScreen extends ConsumerWidget {
  const SchoolListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(schoolListQueryProvider);
    final notifier = ref.read(schoolListQueryProvider.notifier);
    final schools = ref.watch(schoolListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schools'),
        actions: [
          TextButton.icon(
            key: const ValueKey('school-duplicates'),
            onPressed: () => context.go(Routes.schoolDuplicates),
            icon: const Icon(Icons.difference_outlined),
            label: const Text('Possible duplicates'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('school-add'),
        onPressed: () => context.go(Routes.schoolAdd),
        icon: const Icon(Icons.add),
        label: const Text('Add school'),
      ),
      body: schools.hasError && !schools.hasValue
          ? DataUnavailableMessage(
              error: schools.error!,
              onRetry: () => retrySchools(ref),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: MasterSearchAndFilters(
                    query: query,
                    searchHint: 'School name or code',
                    districts: ref.watch(schoolDistrictsProvider).value ?? const [],
                    blocks: ref.watch(schoolBlocksProvider).value ?? const [],
                    onText: notifier.setText,
                    onDistrict: notifier.setDistrict,
                    onBlock: notifier.setBlock,
                    onStatus: notifier.setStatus,
                  ),
                ),
                Expanded(
                  child: DatabaseStateView<List<School>>(
                    value: schools,
                    onRetry: () => retrySchools(ref),
                    builder: (items) => items.isEmpty
                        ? _EmptyList(query: query)
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 96),
                            itemCount: items.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) => _SchoolTile(items[i]),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SchoolTile extends StatelessWidget {
  const _SchoolTile(this.school);

  final School school;

  @override
  Widget build(BuildContext context) {
    final place = [school.panchayatVillage, school.block]
        .whereType<String>()
        .join(', ');
    return ListTile(
      key: ValueKey('school-tile-${school.id}'),
      title: Text(school.name),
      subtitle: Text(
        [schoolCodeText(school), if (place.isNotEmpty) place].join('\n'),
      ),
      isThreeLine: place.isNotEmpty,
      trailing: school.isActive ? null : const InactiveLabel(),
      onTap: () => context.go(Routes.schoolDetail(school.id)),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.query});

  final MasterListQuery query;

  @override
  Widget build(BuildContext context) {
    final filtered =
        query.text.trim().isNotEmpty ||
        query.district != null ||
        query.block != null ||
        query.status != ActiveFilter.active;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          filtered
              ? 'No schools match. Try another search or filter.'
              : 'No schools yet. Tap "Add school" to add one.',
          key: const ValueKey('school-list-empty'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

/// How a school's official code reads on screen: blank stays blank.
String schoolCodeText(School school) => school.officialSchoolCode == null
    ? 'No code'
    : 'Code: ${school.officialSchoolCode}';

/// A school as shown in duplicate lists.
DuplicateCandidate schoolCandidate(School school, {VoidCallback? onTap}) =>
    DuplicateCandidate(
      title: school.name,
      details: [
        schoolCodeText(school),
        [school.panchayatVillage, school.block, school.district]
            .whereType<String>()
            .join(', '),
      ],
      isActive: school.isActive,
      onTap: onTap,
    );
