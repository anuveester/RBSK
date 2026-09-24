import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/core/utils/text_normalize.dart';
import 'package:referredline/core/widgets/database_state_view.dart';
import 'package:referredline/core/widgets/master_widgets.dart';
import 'package:referredline/domain/entities/school.dart';

import '../providers/school_providers.dart';
import 'school_list_screen.dart' show schoolCandidate;

/// Add School (screen 20) and Edit School (screen 19's edit mode).
class SchoolFormScreen extends ConsumerWidget {
  const SchoolFormScreen({this.id, super.key});

  /// Null when adding a new school.
  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = this.id;
    if (id == null) {
      return const _SchoolForm(initial: null);
    }
    final school = ref.watch(schoolDetailProvider(id));
    return DatabaseStateView<School?>(
      value: school,
      onRetry: () => retrySchools(ref),
      builder: (school) => school == null
          ? Scaffold(
              appBar: AppBar(title: const Text('Edit school')),
              body: const Center(
                child: Text('This school could not be found.'),
              ),
            )
          : _SchoolForm(initial: school),
    );
  }
}

class _SchoolForm extends ConsumerStatefulWidget {
  const _SchoolForm({required this.initial});

  final School? initial;

  @override
  ConsumerState<_SchoolForm> createState() => _SchoolFormState();
}

class _SchoolFormState extends ConsumerState<_SchoolForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _code = TextEditingController(
    text: widget.initial?.officialSchoolCode,
  );
  late final _district = TextEditingController(text: widget.initial?.district);
  late final _block = TextEditingController(text: widget.initial?.block);
  late final _village = TextEditingController(
    text: widget.initial?.panchayatVillage,
  );
  late final _address = TextEditingController(text: widget.initial?.address);
  late String? _type = widget.initial?.institutionType;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void dispose() {
    for (final c in [_name, _code, _district, _block, _village, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  SchoolInput get _input => SchoolInput(
    name: _name.text,
    officialSchoolCode: _code.text,
    institutionType: _type,
    district: _district.text,
    block: _block.text,
    panchayatVillage: _village.text,
    address: _address.text,
  );

  void _leave() {
    final initial = widget.initial;
    context.go(
      initial == null ? Routes.schools : Routes.schoolDetail(initial.id),
    );
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _busy = true);
    try {
      final repository = await ref.read(schoolRepositoryProvider.future);
      final input = _input;
      final excludeId = widget.initial?.id;

      // 1. The same non-blank code: never saved (D4).
      final code = blankToNull(input.officialSchoolCode);
      if (code != null) {
        final holder = await repository.findByOfficialCode(
          code,
          excludeId: excludeId,
        );
        if (holder != null) {
          throw DuplicateOfficialCodeFailure(
            codeLabel: 'School Code',
            recordLabel: 'school',
            existingName: holder.name,
          );
        }
      }

      // 2. The same name: a possible duplicate the user must look at (D4).
      final nameChanged =
          !_editing ||
          normalizeForMatch(input.name) !=
              normalizeForMatch(widget.initial!.name);
      if (nameChanged) {
        final matches = await repository.possibleDuplicatesFor(
          input,
          excludeId: excludeId,
        );
        if (matches.isNotEmpty && mounted) {
          final saveAnyway = await confirmPossibleDuplicates(
            context,
            candidates: [for (final s in matches) schoolCandidate(s)],
          );
          if (!saveAnyway) {
            return;
          }
        }
      }

      final saved = _editing
          ? await repository.update(widget.initial!.id, input)
          : await repository.create(input);
      refreshSchools(ref);
      if (mounted) {
        context.go(Routes.schoolDetail(saved.id));
      }
    } on Failure catch (f) {
      if (mounted) {
        setState(() => _error = f.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = saveErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storedOtherType =
        _type != null && !schoolInstitutionTypes.contains(_type) ? _type : null;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit school' : 'Add school')),
      // Every field stays built (not a lazy list) so the whole form is
      // validated, including fields scrolled out of view.
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('school-form-name'),
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'School name *'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Please enter the name.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('school-form-code'),
                controller: _code,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'School Code',
                  helperText: 'Leave blank if the school has no code.',
                ),
              ),
              const SizedBox(height: 16),
              Text('Institution type', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                key: const ValueKey('school-form-type'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in [...schoolInstitutionTypes, null])
                    ChoiceChip(
                      key: ValueKey('school-type-${type ?? 'blank'}'),
                      label: Text(type ?? 'Blank'),
                      selected: _type == type,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _type = type),
                    ),
                  if (storedOtherType != null)
                    ChoiceChip(
                      label: Text(storedOtherType),
                      selected: true,
                      onSelected: null,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('school-form-district'),
                controller: _district,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'District'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('school-form-block'),
                controller: _block,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Block'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('school-form-village'),
                controller: _village,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Panchayat / Village',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('school-form-address'),
                controller: _address,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  key: const ValueKey('school-form-error'),
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 16,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('school-form-save'),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('school-form-cancel'),
                onPressed: _busy ? null : _leave,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
