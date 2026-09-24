import 'package:referredline/core/utils/text_normalize.dart';

/// Plain read-model for `awcs` (docs/04_DATABASE_ARCHITECTURE.md §2.2).
class Awc {
  const Awc({
    required this.id,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.rowVersion,
    this.officialAwcCode,
    this.sourcePlanAwcCode,
    this.subcentreNo,
    this.panchayatVillage,
    this.block,
    this.district,
    this.dataQualityNotes,
  });

  final String id;

  /// A genuine government AWC code only; null until one is supplied.
  final String? officialAwcCode;

  /// The number from the Micro Plan. **Not** an identity and **not** unique:
  /// the same value belongs to different AWCs across months. Read-only here;
  /// filled by the Micro Plan import (a later phase).
  final String? sourcePlanAwcCode;
  final String name;

  /// The village ordinal, e.g. 2 in "JAKHAURA-2". Informational.
  final int? subcentreNo;
  final String? panchayatVillage;
  final String? block;
  final String? district;

  /// Flags from the Micro Plan import for human review. Read-only.
  final String? dataQualityNotes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int rowVersion;
}

/// The AWC fields a person can enter or edit (docs/35 §6).
/// `source_plan_awc_code` and data-quality notes are deliberately absent.
class AwcInput {
  const AwcInput({
    required this.name,
    this.officialAwcCode,
    this.subcentreNo,
    this.panchayatVillage,
    this.block,
    this.district,
  });

  final String name;
  final String? officialAwcCode;
  final int? subcentreNo;
  final String? panchayatVillage;
  final String? block;
  final String? district;

  /// As stored: text trimmed; blank optional fields become null.
  AwcInput normalized() => AwcInput(
    name: name.trim(),
    officialAwcCode: blankToNull(officialAwcCode),
    subcentreNo: subcentreNo,
    panchayatVillage: blankToNull(panchayatVillage),
    block: blankToNull(block),
    district: blankToNull(district),
  );
}
