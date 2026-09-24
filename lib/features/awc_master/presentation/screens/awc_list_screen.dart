import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/core/widgets/database_state_view.dart';
import 'package:referredline/core/widgets/master_widgets.dart';
import 'package:referredline/domain/entities/awc.dart';
import 'package:referredline/domain/entities/master_list_query.dart';

import '../providers/awc_providers.dart';

/// AWC Master List (docs/02_SCREEN_MAP.md screen 21): search by name, code
/// or village; filter by district, block and Active/Inactive/All.
class AwcListScreen extends ConsumerWidget {
  const AwcListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(awcListQueryProvider);
    final notifier = ref.read(awcListQueryProvider.notifier);
    final awcs = ref.watch(awcListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AWCs'),
        actions: [
          TextButton.icon(
            key: const ValueKey('awc-duplicates'),
            onPressed: () => context.go(Routes.awcDuplicates),
            icon: const Icon(Icons.difference_outlined),
            label: const Text('Possible duplicates'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('awc-add'),
        onPressed: () => context.go(Routes.awcAdd),
        icon: const Icon(Icons.add),
        label: const Text('Add AWC'),
      ),
      body: awcs.hasError && !awcs.hasValue
          ? DataUnavailableMessage(
              error: awcs.error!,
              onRetry: () => retryAwcs(ref),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: MasterSearchAndFilters(
                    query: query,
                    searchHint: 'AWC name, code or village',
                    districts: ref.watch(awcDistrictsProvider).value ?? const [],
                    blocks: ref.watch(awcBlocksProvider).value ?? const [],
                    onText: notifier.setText,
                    onDistrict: notifier.setDistrict,
                    onBlock: notifier.setBlock,
                    onStatus: notifier.setStatus,
                  ),
                ),
                Expanded(
                  child: DatabaseStateView<List<Awc>>(
                    value: awcs,
                    onRetry: () => retryAwcs(ref),
                    builder: (items) => items.isEmpty
                        ? _EmptyList(query: query)
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 96),
                            itemCount: items.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) => _AwcTile(items[i]),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AwcTile extends StatelessWidget {
  const _AwcTile(this.awc);

  final Awc awc;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('awc-tile-${awc.id}'),
      title: Text(awc.name),
      subtitle: Text(awcSummary(awc)),
      trailing: awc.isActive ? null : const InactiveLabel(),
      onTap: () => context.go(Routes.awcDetail(awc.id)),
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
              ? 'No AWCs match. Try another search or filter.'
              : 'No AWCs yet. Tap "Add AWC" to add one.',
          key: const ValueKey('awc-list-empty'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

/// Village, subcentre and official code in one short line.
String awcSummary(Awc awc) => [
  if (awc.panchayatVillage != null) awc.panchayatVillage!,
  if (awc.subcentreNo != null) 'No. ${awc.subcentreNo}',
  if (awc.officialAwcCode != null) 'Code: ${awc.officialAwcCode}' else 'No code',
].join(' · ');

DuplicateCandidate awcCandidate(Awc awc, {VoidCallback? onTap}) =>
    DuplicateCandidate(
      title: awc.name,
      details: [
        awcSummary(awc),
        [awc.block, awc.district].whereType<String>().join(', '),
      ],
      isActive: awc.isActive,
      onTap: onTap,
    );
