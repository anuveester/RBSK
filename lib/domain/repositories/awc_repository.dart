import 'package:referredline/domain/entities/awc.dart';
import 'package:referredline/domain/entities/master_list_query.dart';

/// AWC Master data access (docs/35_PHASE_1_5_PLAN.md §13). The only way the
/// app reads or writes `awcs`. Soft-deleted rows are never returned. Every
/// write records one `audit_log` row in the same transaction. There is
/// deliberately no delete, and `source_plan_awc_code` is never written here.
abstract interface class AwcRepository {
  /// Matches the name, official code or village, case-insensitively.
  Future<List<Awc>> search(MasterListQuery query);

  Future<Awc?> getById(String id);

  Future<List<String>> districts();

  Future<List<String>> blocks({String? district});

  /// Another AWC already holding the non-blank official [code], if any.
  Future<Awc?> findByOfficialCode(String code, {String? excludeId});

  /// Other AWCs with the same normalized name, village and subcentre number
  /// (blank matches blank). Includes inactive AWCs. Never merges anything.
  Future<List<Awc>> possibleDuplicatesFor(AwcInput input, {String? excludeId});

  Future<List<List<Awc>>> possibleDuplicateGroups();

  Future<Awc> create(AwcInput input);

  Future<Awc> update(String id, AwcInput input);

  Future<Awc> setActive(String id, {required bool active});
}
