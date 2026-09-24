import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/router/routes.dart';
import 'package:referredline/core/utils/text_normalize.dart';
import 'package:referredline/core/widgets/database_state_view.dart';
import 'package:referredline/core/widgets/master_widgets.dart';
import 'package:referredline/domain/entities/awc.dart';

import '../providers/awc_providers.dart';
import 'awc_list_screen.dart' show awcCandidate;

/// Add AWC (screen 23) and Edit AWC. The Micro Plan AWC code and notes are
/// not editable here (read-only reference data, docs/35 §6).
class AwcFormScreen extends ConsumerWidget {
  const AwcFormScreen({this.id, super.key});

  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = this.id;
    if (id == null) {
      return const _AwcForm(initial: null);
    }
    final awc = ref.watch(awcDetailProvider(id));
    return DatabaseStateView<Awc?>(
      value: awc,
      onRetry: () => retryAwcs(ref),
      builder: (awc) => awc == null
          ? Scaffold(
              appBar: AppBar(title: const Text('Edit AWC')),
              body: const Center(child: Text('This AWC could not be found.')),
            )
          : _AwcForm(initial: awc),
    );
  }
}

class _AwcForm extends ConsumerStatefulWidget {
  const _AwcForm({required this.initial});

  final Awc? initial;

  @override
  ConsumerState<_AwcForm> createState() => _AwcFormState();
}

class _AwcFormState extends ConsumerState<_AwcForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _code = TextEditingController(
    text: widget.initial?.officialAwcCode,
  );
  late final _subcentre = TextEditingController(
    text: widget.initial?.subcentreNo?.toString(),
  );
  late final _village = TextEditingController(
    text: widget.initial?.panchayatVillage,
  );
  late final _block = TextEditingController(text: widget.initial?.block);
  late final _district = TextEditingController(text: widget.initial?.district);
  bool _busy = false;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void dispose() {
    for (final c in [_name, _code, _subcentre, _village, _block, _district]) {
      c.dispose();
    }
    super.dispose();
  }

  AwcInput get _input => AwcInput(
    name: _name.text,
    officialAwcCode: _code.text,
    subcentreNo: int.tryParse(_subcentre.text.trim()),
    panchayatVillage: _village.text,
    block: _block.text,
    district: _district.text,
  );

  static String _matchKey(String name, String? village, int? subcentre) =>
      '${normalizeForMatch(name)}|${normalizeForMatch(village)}|${subcentre ?? ''}';

  void _leave() {
    final initial = widget.initial;
    context.go(initial == null ? Routes.awcs : Routes.awcDetail(initial.id));
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _busy = true);
    try {
      final repository = await ref.read(awcRepositoryProvider.future);
      final input = _input;
      final excludeId = widget.initial?.id;

      final code = blankToNull(input.officialAwcCode);
      if (code != null) {
        final holder = await repository.findByOfficialCode(
          code,
          excludeId: excludeId,
        );
        if (holder != null) {
          throw DuplicateOfficialCodeFailure(
            codeLabel: 'AWC Code',
            recordLabel: 'AWC',
            existingName: holder.name,
          );
        }
      }

      final initial = widget.initial;
      final keyChanged =
          initial == null ||
          _matchKey(input.name, input.panchayatVillage, input.subcentreNo) !=
              _matchKey(
                initial.name,
                initial.panchayatVillage,
                initial.subcentreNo,
              );
      if (keyChanged) {
        final matches = await repository.possibleDuplicatesFor(
          input,
          excludeId: excludeId,
        );
        if (matches.isNotEmpty && mounted) {
          final saveAnyway = await confirmPossibleDuplicates(
            context,
            candidates: [for (final a in matches) awcCandidate(a)],
          );
          if (!saveAnyway) {
            return;
          }
        }
      }

      final saved = _editing
          ? await repository.update(initial!.id, input)
          : await repository.create(input);
      refreshAwcs(ref);
      if (mounted) {
        context.go(Routes.awcDetail(saved.id));
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
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit AWC' : 'Add AWC')),
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
                key: const ValueKey('awc-form-name'),
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'AWC name *'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Please enter the name.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('awc-form-village'),
                controller: _village,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Panchayat / Village',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('awc-form-subcentre'),
                controller: _subcentre,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Subcentre no.',
                  helperText:
                      'For example 2 in "JAKHAURA-2". Leave blank if none.',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('awc-form-code'),
                controller: _code,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'AWC Code (official)',
                  helperText: 'Leave blank unless you have the official government AWC code.',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('awc-form-block'),
                controller: _block,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Block'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('awc-form-district'),
                controller: _district,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'District'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  key: const ValueKey('awc-form-error'),
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 16,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('awc-form-save'),
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
                key: const ValueKey('awc-form-cancel'),
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
