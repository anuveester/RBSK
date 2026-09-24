import 'package:flutter/material.dart';
import 'package:referredline/domain/entities/master_list_query.dart';

/// Small building blocks shared by the School and AWC master screens
/// (docs/35_PHASE_1_5_PLAN.md §14).

/// Marks an inactive record in lists and detail views.
class InactiveLabel extends StatelessWidget {
  const InactiveLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Inactive',
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// One labelled value on a detail screen. A blank value shows [blankText].
class DetailField extends StatelessWidget {
  const DetailField({
    required this.label,
    required this.value,
    this.blankText = 'Not given',
    super.key,
  });

  final String label;
  final String? value;
  final String blankText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blank = value == null || value!.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(
            blank ? blankText : value!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: blank ? theme.colorScheme.onSurfaceVariant : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Search box plus District, Block and Status filters for a master list.
/// District and Block offer only values already stored.
class MasterSearchAndFilters extends StatelessWidget {
  const MasterSearchAndFilters({
    required this.query,
    required this.searchHint,
    required this.districts,
    required this.blocks,
    required this.onText,
    required this.onDistrict,
    required this.onBlock,
    required this.onStatus,
    super.key,
  });

  final MasterListQuery query;
  final String searchHint;
  final List<String> districts;
  final List<String> blocks;
  final ValueChanged<String> onText;
  final ValueChanged<String?> onDistrict;
  final ValueChanged<String?> onBlock;
  final ValueChanged<ActiveFilter> onStatus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('master-search'),
          initialValue: query.text,
          decoration: InputDecoration(
            labelText: 'Search',
            hintText: searchHint,
            prefixIcon: const Icon(Icons.search),
          ),
          textInputAction: TextInputAction.search,
          onChanged: onText,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Picker(
                key: const ValueKey('master-filter-district'),
                label: 'District',
                allLabel: 'All districts',
                value: query.district,
                options: districts,
                onChanged: onDistrict,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Picker(
                key: const ValueKey('master-filter-block'),
                label: 'Block',
                allLabel: 'All blocks',
                value: query.block,
                options: blocks,
                onChanged: onBlock,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<ActiveFilter>(
          key: const ValueKey('master-filter-status'),
          segments: const [
            ButtonSegment(value: ActiveFilter.active, label: Text('Active')),
            ButtonSegment(value: ActiveFilter.inactive, label: Text('Inactive')),
            ButtonSegment(value: ActiveFilter.all, label: Text('All')),
          ],
          selected: {query.status},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onStatus(selection.single),
        ),
      ],
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.allLabel,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String allLabel;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = options.contains(value) ? value : null;
    return DropdownButtonFormField<String?>(
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<String?>(child: Text(allLabel)),
        for (final option in options)
          DropdownMenuItem<String?>(
            value: option,
            child: Text(option, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// A record shown in the possible-duplicate dialog and review screen.
class DuplicateCandidate {
  const DuplicateCandidate({
    required this.title,
    required this.details,
    required this.isActive,
    this.onTap,
  });

  final String title;
  final List<String> details;
  final bool isActive;
  final VoidCallback? onTap;
}

class DuplicateCandidateTile extends StatelessWidget {
  const DuplicateCandidateTile({required this.candidate, super.key});

  final DuplicateCandidate candidate;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(candidate.title),
      subtitle: Text(candidate.details.where((d) => d.isNotEmpty).join('\n')),
      trailing: candidate.isActive ? null : const InactiveLabel(),
      onTap: candidate.onTap,
    );
  }
}

/// Before saving: lists possible duplicates and asks whether to save anyway.
/// True only if the user chooses **Save anyway**. Nothing is ever merged.
Future<bool> confirmPossibleDuplicates(
  BuildContext context, {
  required List<DuplicateCandidate> candidates,
}) async {
  final choice = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('possible-duplicate-dialog'),
      title: const Text('Possible duplicate found'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text('Please check these records before saving.'),
            const SizedBox(height: 8),
            for (final candidate in candidates)
              DuplicateCandidateTile(candidate: candidate),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('duplicate-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('duplicate-save-anyway'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save anyway'),
        ),
      ],
    ),
  );
  return choice ?? false;
}

/// Asks before switching a record between Active and Inactive.
Future<bool> confirmActiveChange(
  BuildContext context, {
  required String recordLabel,
  required bool makeActive,
}) async {
  final choice = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(makeActive ? 'Mark as active?' : 'Mark as inactive?'),
      content: Text(
        makeActive
            ? 'This $recordLabel will show in the active list again.'
            : 'This $recordLabel stays in the records and can be made active '
                  'again later.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('active-change-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(makeActive ? 'Mark active' : 'Mark inactive'),
        ),
      ],
    ),
  );
  return choice ?? false;
}
