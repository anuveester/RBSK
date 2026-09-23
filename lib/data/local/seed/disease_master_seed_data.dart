import 'package:referredline/data/local/enums.dart';

/// The 37-row official Disease/Finding Master, transcribed verbatim from
/// docs/14_JOB_AID_FIELD_MAPPING.md §7 (RBSK Job Aid 0-6 years, page 4).
///
/// **37 is the confirmed, final count** — 11 Defects at Birth + 8
/// Deficiencies + 9 Diseases + 9 Developmental Delay & Disability. An earlier
/// figure of 29, carried in three prior documents, was a documentation
/// miscount and must not be reconstructed
/// (docs/00_PROJECT_MASTER_PLAN.md §10, resolution — this phase's own
/// authorization).
///
/// Codes and names are exactly as printed on the source form — never
/// reworded, never normalized. Codes 31-38 do not appear on the source page
/// and are not represented here; nothing is invented to fill the gap
/// (docs/14 §9).
///
/// `sourceReference` is the same literal string for every row, naming the
/// one source page all 37 rows come from.
class DiseaseMasterSeedRow {
  const DiseaseMasterSeedRow({
    required this.id,
    required this.officialCode,
    required this.name,
    required this.category,
  });

  final String id;
  final String officialCode;
  final String name;
  final DiseaseCategory category;
}

/// Every row above comes from this one source page — set as
/// `disease_master.source_reference` uniformly by the seed runner rather than
/// repeated 37 times here.
const String diseaseMasterSourceReference = 'RBSK Job Aid 0-6 years, p.4';

const List<DiseaseMasterSeedRow> diseaseMasterSeedData = [
  // --- Defects at Birth (11) ---
  DiseaseMasterSeedRow(
    id: 'disease-1',
    officialCode: '1',
    name: 'Neural Tube Defect',
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-2',
    officialCode: '2',
    name: "Down's Syndrome",
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-3',
    officialCode: '3',
    name: 'Cleft Lip & Palate',
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-4',
    officialCode: '4',
    name: 'Talipes (club foot)',
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-5',
    officialCode: '5',
    name: 'Developmental Dysplasia of Hip',
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-6',
    officialCode: '6',
    name: 'Congenital Cataract',
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-7',
    officialCode: '7',
    name: 'Congenital Deafness',
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-8',
    officialCode: '8',
    name: 'Congenital Heart Disease',
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-9',
    officialCode: '9',
    name: 'ROP (only at DH)',
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-42',
    officialCode: '42',
    name: 'Microcephaly',
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-43',
    officialCode: '43',
    name: 'Macrocephaly',
    category: DiseaseCategory.DEFECTS_AT_BIRTH,
  ),

  // --- Deficiencies (8) ---
  DiseaseMasterSeedRow(
    id: 'disease-10',
    officialCode: '10',
    name: 'Severe Anemia',
    category: DiseaseCategory.DEFICIENCIES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-11',
    officialCode: '11',
    name: 'Vitamin A Def.',
    category: DiseaseCategory.DEFICIENCIES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-12',
    officialCode: '12',
    name: 'Vitamin D Deficiency',
    category: DiseaseCategory.DEFICIENCIES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-13',
    officialCode: '13',
    name: 'SAM up to 60 mon.',
    category: DiseaseCategory.DEFICIENCIES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-14',
    officialCode: '14',
    name: 'Goiter (usually after 6 years)',
    category: DiseaseCategory.DEFICIENCIES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-41',
    officialCode: '41',
    name: 'Severe Stunting',
    category: DiseaseCategory.DEFICIENCIES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-44',
    officialCode: '44',
    name: 'Vitamin B complex def.',
    category: DiseaseCategory.DEFICIENCIES,
  ),
  // Code 30 — the official catch-all. NOT a predefined diagnosis: selecting
  // it requires the user to supply a specification (Phase 1.3 instruction
  // §2.B). No additional clinical meaning is invented for it here.
  DiseaseMasterSeedRow(
    id: 'disease-30',
    officialCode: '30',
    name: 'Others (Specify)',
    category: DiseaseCategory.DEFICIENCIES,
  ),

  // --- Diseases (9) ---
  DiseaseMasterSeedRow(
    id: 'disease-15',
    officialCode: '15',
    name: 'Skin Conditions',
    category: DiseaseCategory.DISEASES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-16',
    officialCode: '16',
    name: 'Otitis Media',
    category: DiseaseCategory.DISEASES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-17',
    officialCode: '17',
    name: 'Rheumatic Heart Dis.',
    category: DiseaseCategory.DISEASES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-18',
    officialCode: '18',
    name: 'Bronchial Asthma (Reactive Airway Dis.)',
    category: DiseaseCategory.DISEASES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-19',
    officialCode: '19',
    name: 'Dental Conditions',
    category: DiseaseCategory.DISEASES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-20',
    officialCode: '20',
    name: 'Convulsive Disorders',
    category: DiseaseCategory.DISEASES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-39',
    officialCode: '39',
    name: 'Childhood Leprosy Disease',
    category: DiseaseCategory.DISEASES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-40',
    officialCode: '40',
    name: 'Childhood T.B.',
    category: DiseaseCategory.DISEASES,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-40-1',
    officialCode: '40.1',
    name: 'Childhood Extra Pulmonary T.B.',
    category: DiseaseCategory.DISEASES,
  ),

  // --- Developmental Delay & Disability (9) ---
  DiseaseMasterSeedRow(
    id: 'disease-21',
    officialCode: '21',
    name: 'Vision Impairment',
    category: DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-22',
    officialCode: '22',
    name: 'Hearing Impairment',
    category: DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-23',
    officialCode: '23',
    name: 'Neuro-motor Impairment',
    category: DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-24',
    officialCode: '24',
    name: 'Motor Delay',
    category: DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-25',
    officialCode: '25',
    name: 'Cognitive Delay',
    category: DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-26',
    officialCode: '26',
    name: 'Speech and Language Delay',
    category: DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-27',
    officialCode: '27',
    name: 'Behavioral Disorder (Autism)',
    category: DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-28',
    officialCode: '28',
    name: 'Learning Disorder',
    category: DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY,
  ),
  DiseaseMasterSeedRow(
    id: 'disease-29',
    officialCode: '29',
    name: 'Attention Deficit Hyperactivity Disorder',
    category: DiseaseCategory.DEVELOPMENTAL_DELAY_DISABILITY,
  ),
];

/// The catch-all's official code, exposed as a constant so later phases
/// (the actual screening form) can detect "this selection requires a
/// free-text specification" without hardcoding the string elsewhere.
const String othersSpecifyOfficialCode = '30';
