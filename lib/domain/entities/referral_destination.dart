/// Plain read-model for `referral_destinations`
/// (docs/04_DATABASE_ARCHITECTURE.md §2.8). Which destinations are valid for
/// which context (School vs AWC) and finding category is a query concern —
/// see `ReferralDestinationRepository.getDestinations` — not a field here,
/// matching the schema's own separation of `referral_destinations` from
/// `referral_destination_contexts`.
class ReferralDestination {
  const ReferralDestination({
    required this.id,
    required this.code,
    required this.label,
    this.description,
  });

  final String id;
  final String code;
  final String label;
  final String? description;
}
