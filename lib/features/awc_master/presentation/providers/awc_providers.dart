import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:referredline/data/local/database_provider.dart';
import 'package:referredline/data/repositories/drift_awc_repository.dart';
import 'package:referredline/domain/entities/awc.dart';
import 'package:referredline/domain/entities/master_list_query.dart';
import 'package:referredline/domain/repositories/awc_repository.dart';

/// AWC Master state (docs/35_PHASE_1_5_PLAN.md §16).
final awcRepositoryProvider = FutureProvider<AwcRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftAwcRepository(db);
}, retry: noAutomaticRetry);

class AwcListQueryNotifier extends Notifier<MasterListQuery> {
  @override
  MasterListQuery build() => const MasterListQuery();

  void setText(String text) => state = state.copyWith(text: text);

  void setDistrict(String? district) =>
      state = state.copyWith(district: () => district, block: () => null);

  void setBlock(String? block) => state = state.copyWith(block: () => block);

  void setStatus(ActiveFilter status) => state = state.copyWith(status: status);
}

final awcListQueryProvider =
    NotifierProvider<AwcListQueryNotifier, MasterListQuery>(
      AwcListQueryNotifier.new,
    );

final awcListProvider = FutureProvider<List<Awc>>((ref) async {
  final repository = await ref.watch(awcRepositoryProvider.future);
  return repository.search(ref.watch(awcListQueryProvider));
}, retry: noAutomaticRetry);

final awcDistrictsProvider = FutureProvider<List<String>>((ref) async {
  final repository = await ref.watch(awcRepositoryProvider.future);
  return repository.districts();
}, retry: noAutomaticRetry);

final awcBlocksProvider = FutureProvider<List<String>>((ref) async {
  final repository = await ref.watch(awcRepositoryProvider.future);
  final district = ref.watch(
    awcListQueryProvider.select((query) => query.district),
  );
  return repository.blocks(district: district);
}, retry: noAutomaticRetry);

final awcDetailProvider = FutureProvider.family<Awc?, String>((ref, id) async {
  final repository = await ref.watch(awcRepositoryProvider.future);
  return repository.getById(id);
}, retry: noAutomaticRetry);

final awcDuplicateGroupsProvider = FutureProvider<List<List<Awc>>>((ref) async {
  final repository = await ref.watch(awcRepositoryProvider.future);
  return repository.possibleDuplicateGroups();
}, retry: noAutomaticRetry);

void refreshAwcs(WidgetRef ref) {
  ref.invalidate(awcListProvider);
  ref.invalidate(awcDistrictsProvider);
  ref.invalidate(awcBlocksProvider);
  ref.invalidate(awcDetailProvider);
  ref.invalidate(awcDuplicateGroupsProvider);
}

void retryAwcs(WidgetRef ref) {
  ref.invalidate(appDatabaseProvider);
  ref.invalidate(awcRepositoryProvider);
  refreshAwcs(ref);
}
