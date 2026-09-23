/// Plain read-model for `staff` (docs/04_DATABASE_ARCHITECTURE.md §2.1).
///
/// Deliberately has NO phone/contact field, even as an optional one — this is
/// a structural guard, not just a seeding choice: nothing in the domain layer
/// can accidentally surface a staff phone number through this entity, per the
/// privacy rule established in Phase 1.2 and restated for Phase 1.3 (contact
/// numbers are never seeded, never committed).
class StaffMember {
  const StaffMember({
    required this.id,
    required this.fullName,
    this.designation,
    this.qualification,
  });

  final String id;
  final String fullName;
  final String? designation;
  final String? qualification;
}
