import 'package:referredline/core/utils/text_normalize.dart';

/// The School institution types seen in the source Micro Plan
/// (docs/04_DATABASE_ARCHITECTURE.md §2.2). The manual form offers exactly
/// these, plus blank (docs/35_PHASE_1_5_PLAN.md §12). No others are invented.
const List<String> schoolInstitutionTypes = ['PS', 'UPS', 'COM'];

/// Plain read-model for `schools` (docs/04 §2.2). No Drift type leaks past
/// the data layer (docs/06_PROJECT_STRUCTURE.md).
class School {
  const School({
    required this.id,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.rowVersion,
    this.officialSchoolCode,
    this.institutionType,
    this.district,
    this.block,
    this.panchayatVillage,
    this.address,
    this.dataQualityNotes,
  });

  final String id;

  /// Blank stays blank: null when the school has no official code.
  final String? officialSchoolCode;
  final String name;
  final String? institutionType;
  final String? district;
  final String? block;
  final String? panchayatVillage;
  final String? address;

  /// Flags from the Micro Plan import for human review. Read-only.
  final String? dataQualityNotes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int rowVersion;
}

/// The School fields a person can enter or edit (docs/35 §5). Everything
/// else (id, timestamps, row version, notes) is managed by the repository.
class SchoolInput {
  const SchoolInput({
    required this.name,
    this.officialSchoolCode,
    this.institutionType,
    this.district,
    this.block,
    this.panchayatVillage,
    this.address,
  });

  final String name;
  final String? officialSchoolCode;
  final String? institutionType;
  final String? district;
  final String? block;
  final String? panchayatVillage;
  final String? address;

  /// As stored: the name and every optional field trimmed; blank optional
  /// fields become null. Nothing else is changed.
  SchoolInput normalized() => SchoolInput(
    name: name.trim(),
    officialSchoolCode: blankToNull(officialSchoolCode),
    institutionType: blankToNull(institutionType),
    district: blankToNull(district),
    block: blankToNull(block),
    panchayatVillage: blankToNull(panchayatVillage),
    address: blankToNull(address),
  );
}
