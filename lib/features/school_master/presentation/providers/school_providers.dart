import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:referredline/data/local/database_provider.dart';
import 'package:referredline/data/repositories/drift_school_repository.dart';
import 'package:referredline/domain/entities/master_list_query.dart';
import 'package:referredline/domain/entities/school.dart';
import 'package:referredline/domain/repositories/school_repository.dart';

/// School Master state (docs/35_PHASE_1_5_PLAN.md §16). Screens reach the
/// data only through [schoolRepositoryProvider].
final schoolRepositoryProvider = FutureProvider<SchoolRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftSchoolRepository(db);
}, retry: noAutomaticRetry);

/// The list's search text and filters. Starts on Active schools.
class SchoolListQueryNotifier extends Notifier<MasterListQuery> {
  @override
  MasterListQuery build() => const MasterListQuery();

  void setText(String text) => state = state.copyWith(text: text);

  /// A new district clears the block (it may not belong to that district).
  void setDistrict(String? district) =>
      state = state.copyWith(district: () => district, block: () => null);

  void setBlock(String? block) => state = state.copyWith(block: () => block);

  void setStatus(ActiveFilter status) => state = state.copyWith(status: status);
}

final schoolListQueryProvider =
    NotifierProvider<SchoolListQueryNotifier, MasterListQuery>(
      SchoolListQueryNotifier.new,
    );

final schoolListProvider = FutureProvider<List<School>>((ref) async {
  final repository = await ref.watch(schoolRepositoryProvider.future);
  return repository.search(ref.watch(schoolListQueryProvider));
}, retry: noAutomaticRetry);

final schoolDistrictsProvider = FutureProvider<List<String>>((ref) async {
  final repository = await ref.watch(schoolRepositoryProvider.future);
  return repository.districts();
}, retry: noAutomaticRetry);

final schoolBlocksProvider = FutureProvider<List<String>>((ref) async {
  final repository = await ref.watch(schoolRepositoryProvider.future);
  final district = ref.watch(
    schoolListQueryProvider.select((query) => query.district),
  );
  return repository.blocks(district: district);
}, retry: noAutomaticRetry);

final schoolDetailProvider = FutureProvider.family<School?, String>((
  ref,
  id,
) async {
  final repository = await ref.watch(schoolRepositoryProvider.future);
  return repository.getById(id);
}, retry: noAutomaticRetry);

final schoolDuplicateGroupsProvider = FutureProvider<List<List<School>>>((
  ref,
) async {
  final repository = await ref.watch(schoolRepositoryProvider.future);
  return repository.possibleDuplicateGroups();
}, retry: noAutomaticRetry);

/// After any School change, so every School screen shows current data.
void refreshSchools(WidgetRef ref) {
  ref.invalidate(schoolListProvider);
  ref.invalidate(schoolDistrictsProvider);
  ref.invalidate(schoolBlocksProvider);
  ref.invalidate(schoolDetailProvider);
  ref.invalidate(schoolDuplicateGroupsProvider);
}

/// "Try again" on a School screen: re-open the data, then re-read.
void retrySchools(WidgetRef ref) {
  ref.invalidate(appDatabaseProvider);
  ref.invalidate(schoolRepositoryProvider);
  refreshSchools(ref);
}
