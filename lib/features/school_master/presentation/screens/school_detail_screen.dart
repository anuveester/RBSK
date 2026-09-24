import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/core/widgets/database_state_view.dart';
import 'package:referredline/core/widgets/master_widgets.dart';
import 'package:referredline/domain/entities/school.dart';

import '../providers/school_providers.dart';

/// School Detail (docs/02_SCREEN_MAP.md screen 19). Records are never
/// deleted: the only state change offered is Active/Inactive (D3).
class SchoolDetailScreen extends ConsumerWidget {
  const SchoolDetailScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final school = ref.watch(schoolDetailProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('School')),
      body: DatabaseStateView<School?>(
        value: school,
        onRetry: () => retrySchools(ref),
        builder: (school) => school == null
            ? const Center(child: Text('This school could not be found.'))
            : _SchoolDetail(school: school),
      ),
    );
  }
}

class _SchoolDetail extends ConsumerStatefulWidget {
  const _SchoolDetail({required this.school});

  final School school;

  @override
  ConsumerState<_SchoolDetail> createState() => _SchoolDetailState();
}

class _SchoolDetailState extends ConsumerState<_SchoolDetail> {
  bool _busy = false;

  Future<void> _setActive(bool active) async {
    final confirmed = await confirmActiveChange(
      context,
      recordLabel: 'school',
      makeActive: active,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final repository = await ref.read(schoolRepositoryProvider.future);
      await repository.setActive(widget.school.id, active: active);
      refreshSchools(ref);
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
    final school = widget.school;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  school.name,
                  key: const ValueKey('school-detail-name'),
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              if (!school.isActive) const InactiveLabel(),
            ],
          ),
          const SizedBox(height: 8),
          DetailField(
            label: 'School Code',
            value: school.officialSchoolCode,
            blankText: 'No code',
          ),
          DetailField(label: 'Institution type', value: school.institutionType),
          DetailField(label: 'District', value: school.district),
          DetailField(label: 'Block', value: school.block),
          DetailField(
            label: 'Panchayat / Village',
            value: school.panchayatVillage,
          ),
          DetailField(label: 'Address', value: school.address),
          if (school.dataQualityNotes != null)
            DetailField(
              label: 'Notes from the Micro Plan (cannot be edited)',
              value: school.dataQualityNotes,
            ),
          const Divider(height: 32),
          SwitchListTile(
            key: const ValueKey('school-active-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            subtitle: Text(
              school.isActive
                  ? 'This school is in use.'
                  : 'Inactive. It stays in the records.',
            ),
            value: school.isActive,
            onChanged: _busy ? null : _setActive,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('school-edit'),
            onPressed: _busy
                ? null
                : () => context.go(Routes.schoolEdit(school.id)),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}
