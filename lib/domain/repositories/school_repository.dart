import 'package:referredline/domain/entities/master_list_query.dart';
import 'package:referredline/domain/entities/school.dart';

/// School Master data access (docs/35_PHASE_1_5_PLAN.md §13). The only way
/// the app reads or writes `schools`. Soft-deleted rows are never returned.
/// Every write records one `audit_log` row in the same transaction. There
/// is deliberately no delete.
abstract interface class SchoolRepository {
  /// Matches the name or official code, case-insensitively, sorted by name.
  Future<List<School>> search(MasterListQuery query);

  Future<School?> getById(String id);

  /// Distinct stored districts, for the filter.
  Future<List<String>> districts();

  /// Distinct stored blocks, narrowed to [district] when given.
  Future<List<String>> blocks({String? district});

  /// Another school already holding the non-blank [code], if any. Saving
  /// such a code is blocked.
  Future<School?> findByOfficialCode(String code, {String? excludeId});

  /// Other schools with the same normalized name — possible duplicates to
  /// show before saving. Includes inactive schools. Never merges anything.
  Future<List<School>> possibleDuplicatesFor(
    SchoolInput input, {
    String? excludeId,
  });

  /// Every group of two or more schools sharing a normalized name.
  Future<List<List<School>>> possibleDuplicateGroups();

  /// Throws `NameRequiredFailure` or `DuplicateOfficialCodeFailure`.
  Future<School> create(SchoolInput input);

  /// Writes only what changed; if nothing changed nothing is written.
  /// Throws `NameRequiredFailure`, `DuplicateOfficialCodeFailure` or
  /// `MasterRecordNotFoundFailure`.
  Future<School> update(String id, SchoolInput input);

  Future<School> setActive(String id, {required bool active});
}
