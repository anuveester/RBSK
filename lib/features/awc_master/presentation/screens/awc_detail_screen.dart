import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/core/widgets/database_state_view.dart';
import 'package:referredline/core/widgets/master_widgets.dart';
import 'package:referredline/domain/entities/awc.dart';

import '../providers/awc_providers.dart';

/// AWC Detail (docs/02_SCREEN_MAP.md screen 22). The Micro Plan code and
/// notes are shown read-only and marked as reference data, never as the
/// AWC's official identity. No delete: only Active/Inactive (D3).
class AwcDetailScreen extends ConsumerWidget {
  const AwcDetailScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final awc = ref.watch(awcDetailProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('AWC')),
      body: DatabaseStateView<Awc?>(
        value: awc,
        onRetry: () => retryAwcs(ref),
        builder: (awc) => awc == null
            ? const Center(child: Text('This AWC could not be found.'))
            : _AwcDetail(awc: awc),
      ),
    );
  }
}

class _AwcDetail extends ConsumerStatefulWidget {
  const _AwcDetail({required this.awc});

  final Awc awc;

  @override
  ConsumerState<_AwcDetail> createState() => _AwcDetailState();
}

class _AwcDetailState extends ConsumerState<_AwcDetail> {
  bool _busy = false;

  Future<void> _setActive(bool active) async {
    final confirmed = await confirmActiveChange(
      context,
      recordLabel: 'AWC',
      makeActive: active,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final repository = await ref.read(awcRepositoryProvider.future);
      await repository.setActive(widget.awc.id, active: active);
      refreshAwcs(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is Failure ? e.message : saveErrorMessage(e)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final awc = widget.awc;
    final theme = Theme.of(context);
    final hasReference =
        awc.sourcePlanAwcCode != null || awc.dataQualityNotes != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  awc.name,
                  key: const ValueKey('awc-detail-name'),
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              if (!awc.isActive) const InactiveLabel(),
            ],
          ),
          const SizedBox(height: 8),
          DetailField(
            label: 'AWC Code (official)',
            value: awc.officialAwcCode,
            blankText: 'No code',
          ),
          DetailField(
            label: 'Subcentre no.',
            value: awc.subcentreNo?.toString(),
          ),
          DetailField(
            label: 'Panchayat / Village',
            value: awc.panchayatVillage,
          ),
          DetailField(label: 'Block', value: awc.block),
          DetailField(label: 'District', value: awc.district),
          if (hasReference) ...[
            const Divider(height: 32),
            Text(
              'From the Micro Plan (reference only, not an ID; cannot be edited)',
              key: const ValueKey('awc-reference-section'),
              style: theme.textTheme.titleSmall,
            ),
            if (awc.sourcePlanAwcCode != null)
              DetailField(
                label: 'Micro Plan AWC code',
                value: awc.sourcePlanAwcCode,
              ),
            if (awc.dataQualityNotes != null)
              DetailField(label: 'Notes', value: awc.dataQualityNotes),
          ],
          const Divider(height: 32),
          SwitchListTile(
            key: const ValueKey('awc-active-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            subtitle: Text(
              awc.isActive
                  ? 'This AWC is in use.'
                  : 'Inactive. It stays in the records.',
            ),
            value: awc.isActive,
            onChanged: _busy ? null : _setActive,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('awc-edit'),
            onPressed: _busy ? null : () => context.go(Routes.awcEdit(awc.id)),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}
