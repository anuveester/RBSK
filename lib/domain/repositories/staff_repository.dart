import 'package:referredline/domain/entities/staff_member.dart';

abstract interface class StaffRepository {
  /// Staff whose `staff_assignments` covers [asOf] (start_date <= asOf AND
  /// (end_date IS NULL OR end_date >= asOf)) — the historical-lookup pattern
  /// documented in docs/04_DATABASE_ARCHITECTURE.md §2.1.
  Future<List<StaffMember>> getActiveAsOf(DateTime asOf);

  Future<List<StaffMember>> getAll();
}
