/// Team-B, FY 2025-26 — source: the Micro Plan header block ("Details of
/// Dedicated team staff"), transcribed in docs/04_DATABASE_ARCHITECTURE.md
/// §2.1 and docs/16_PHASE0_DATABASE_REVIEW.md §8.
///
/// PRIVACY: no phone/contact field exists on this type or anywhere in this
/// file, on purpose. Phase 1.3 instruction §2.D / §9 is explicit — staff
/// contact numbers are never seeded, never placed in source code, tests,
/// fixtures, documentation, or Git. The source Micro Plan does carry them;
/// this file simply has no field capable of holding one.
class StaffSeedRow {
  const StaffSeedRow({
    required this.id,
    required this.fullName,
    required this.designation,
    this.qualification,
  });

  final String id;
  final String fullName;

  /// Role, not a formal job title from the source — matches
  /// `staff.designation` (docs/04 §2.1: "e.g. 'Medical Officer', 'Staff
  /// Nurse', 'Optometrist'").
  final String designation;

  /// Separate from `designation` per the frozen schema's own column split
  /// (docs/04 §2.1: "qualification — separate from role, per source plan").
  final String? qualification;
}

const List<StaffSeedRow> staffSeedData = [
  StaffSeedRow(
    id: 'staff-rajni-pratap',
    fullName: 'Rajni Pratap',
    designation: 'Medical Officer',
    qualification: 'BAMS',
  ),
  StaffSeedRow(
    id: 'staff-deepak-yadav',
    fullName: 'Deepak Yadav',
    designation: 'Medical Officer',
    qualification: 'BHMS',
  ),
  StaffSeedRow(
    id: 'staff-shabnam-khan',
    fullName: 'Shabnam Khan',
    designation: 'Staff Nurse',
  ),
  StaffSeedRow(
    id: 'staff-mangal-kumar',
    fullName: 'Mangal Kumar',
    // OPT = Optometrist — resolved, docs/21 approval condition E.
    designation: 'Optometrist',
  ),
];

/// One open-ended `staff_assignments` row per member, `team_label = 'Team - B'`,
/// starting at the FY 2025-26 start date. No `end_date` — the source Micro
/// Plan shows an identical roster across all 12 months of FY 2025-26, i.e. no
/// transfer evidence within that year (docs/16 §9).
class StaffAssignmentSeedRow {
  StaffAssignmentSeedRow({
    required this.id,
    required this.staffId,
    required this.roleInTeam,
    required this.startDate,
    required this.financialYearId,
  });

  final String id;
  final String staffId;
  final String roleInTeam;
  final DateTime startDate;
  final String financialYearId;
}

final List<StaffAssignmentSeedRow> staffAssignmentSeedData = [
  StaffAssignmentSeedRow(
    id: 'assign-rajni-pratap-fy2025-26',
    staffId: 'staff-rajni-pratap',
    roleInTeam: 'Medical Officer',
    startDate: DateTime.utc(2025, 4, 1),
    financialYearId: 'fy-2025-26',
  ),
  StaffAssignmentSeedRow(
    id: 'assign-deepak-yadav-fy2025-26',
    staffId: 'staff-deepak-yadav',
    roleInTeam: 'Medical Officer',
    startDate: DateTime.utc(2025, 4, 1),
    financialYearId: 'fy-2025-26',
  ),
  StaffAssignmentSeedRow(
    id: 'assign-shabnam-khan-fy2025-26',
    staffId: 'staff-shabnam-khan',
    roleInTeam: 'Staff Nurse',
    startDate: DateTime.utc(2025, 4, 1),
    financialYearId: 'fy-2025-26',
  ),
  StaffAssignmentSeedRow(
    id: 'assign-mangal-kumar-fy2025-26',
    staffId: 'staff-mangal-kumar',
    roleInTeam: 'Optometrist',
    startDate: DateTime.utc(2025, 4, 1),
    financialYearId: 'fy-2025-26',
  ),
];
