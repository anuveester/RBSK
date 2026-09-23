import 'package:referredline/data/local/enums.dart';

/// School and AWC referral destinations + routing, transcribed from
/// docs/20_REFERRAL_CONFIGURATION.md §2-3. The two vocabularies are never
/// merged — a School query must never return DEIC/NRC and an AWC query must
/// never be assumed to equal School routing (Phase 1.3 instruction §2.G).
class ReferralDestinationSeedRow {
  const ReferralDestinationSeedRow({
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

/// Row-level routing: which destination is offered for which context,
/// optionally narrowed by finding category. `category == null` means "all
/// categories in this context".
class ReferralDestinationContextSeedRow {
  const ReferralDestinationContextSeedRow({
    required this.id,
    required this.destinationId,
    required this.context,
    this.category,
  });

  final String id;
  final String destinationId;
  final LocationType context;
  final DiseaseCategory? category;
}

// --- Destinations (8 total: 3 School + 5 AWC) ---

const List<ReferralDestinationSeedRow> referralDestinationSeedData = [
  // School — [USER-DECIDED], working vocabulary, no official source document
  // (docs/20 §2).
  ReferralDestinationSeedRow(
    id: 'ref-dest-phc-chc',
    code: 'PHC_CHC',
    label: 'PHC/CHC',
  ),
  ReferralDestinationSeedRow(
    id: 'ref-dest-district-hospital',
    code: 'DISTRICT_HOSPITAL',
    label: 'District Hospital',
  ),
  ReferralDestinationSeedRow(
    id: 'ref-dest-higher-center',
    code: 'HIGHER_CENTER',
    label: 'Higher Center',
  ),

  // AWC — [SOURCE-DERIVED], RBSK Job Aid 0-6 years, page 4 (docs/20 §3).
  ReferralDestinationSeedRow(
    id: 'ref-dest-phc',
    code: 'PHC',
    label: 'PHC',
  ),
  ReferralDestinationSeedRow(
    id: 'ref-dest-chc',
    code: 'CHC',
    label: 'CHC',
  ),
  ReferralDestinationSeedRow(
    id: 'ref-dest-dh',
    code: 'DH',
    label: 'District Hospital (DH)',
  ),
  ReferralDestinationSeedRow(
    id: 'ref-dest-deic',
    code: 'DEIC',
    label: 'District Early Intervention Centre (DEIC)',
  ),
  ReferralDestinationSeedRow(
    id: 'ref-dest-nrc',
    code: 'NRC',
    label: 'Nutrition Rehabilitation Centre (NRC)',
  ),
];

// --- Context routing ---

const List<ReferralDestinationContextSeedRow>
referralDestinationContextSeedData = [
  // School: all 3 destinations apply to every finding category.
  ReferralDestinationContextSeedRow(
    id: 'ctx-school-phc-chc',
    destinationId: 'ref-dest-phc-chc',
    context: LocationType.SCHOOL,
  ),
  ReferralDestinationContextSeedRow(
    id: 'ctx-school-district-hospital',
    destinationId: 'ref-dest-district-hospital',
    context: LocationType.SCHOOL,
  ),
  ReferralDestinationContextSeedRow(
    id: 'ctx-school-higher-center',
    destinationId: 'ref-dest-higher-center',
    context: LocationType.SCHOOL,
  ),

  // AWC: category-dependent, exactly as printed on the Job Aid (docs/20 §3).
  // Defects at Birth -> DH, DEIC
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-defects-dh',
    destinationId: 'ref-dest-dh',
    context: LocationType.AWC,
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-defects-deic',
    destinationId: 'ref-dest-deic',
    context: LocationType.AWC,
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),
  // Deficiencies -> PHC, CHC, NRC (SAM routes specifically to NRC)
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-deficiencies-phc',
    destinationId: 'ref-dest-phc',
    context: LocationType.AWC,
    category: DiseaseCategory.DEFICIENCIES,
  ),
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-deficiencies-chc',
    destinationId: 'ref-dest-chc',
    context: LocationType.AWC,
    category: DiseaseCategory.DEFICIENCIES,
  ),
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-deficiencies-nrc',
    destinationId: 'ref-dest-nrc',
    context: LocationType.AWC,
    category: DiseaseCategory.DEFICIENCIES,
  ),
  // Diseases -> PHC, CHC, DH, DEIC (Dental condition routes to DEIC/DH)
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-diseases-phc',
    destinationId: 'ref-dest-phc',
    context: LocationType.AWC,
    category: DiseaseCategory.DISEASES,
  ),
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-diseases-chc',
    destinationId: 'ref-dest-chc',
    context: LocationType.AWC,
    category: DiseaseCategory.DISEASES,
  ),
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-diseases-dh',
    destinationId: 'ref-dest-dh',
    context: LocationType.AWC,
    category: DiseaseCategory.DISEASES,
  ),
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-diseases-deic',
    destinationId: 'ref-dest-deic',
    context: LocationType.AWC,
    category: DiseaseCategory.DISEASES,
  ),
  // Developmental Delay & Disability -> DEIC
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-developmental-deic',
    destinationId: 'ref-dest-deic',
    context: LocationType.AWC,
    category: DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY,
  ),
  // Others -> PHC, CHC, DH
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-others-phc',
    destinationId: 'ref-dest-phc',
    context: LocationType.AWC,
    category: DiseaseCategory.OTHERS,
  ),
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-others-chc',
    destinationId: 'ref-dest-chc',
    context: LocationType.AWC,
    category: DiseaseCategory.OTHERS,
  ),
  ReferralDestinationContextSeedRow(
    id: 'ctx-awc-others-dh',
    destinationId: 'ref-dest-dh',
    context: LocationType.AWC,
    category: DiseaseCategory.OTHERS,
  ),
];
