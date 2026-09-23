import 'package:referredline/data/local/enums.dart';

/// Plain read-model for `disease_master` (docs/04_DATABASE_ARCHITECTURE.md §2.4).
///
/// `DiseaseCategory`/`ApplicableTo` are reused directly from
/// `data/local/enums.dart` rather than duplicated as separate domain-layer
/// enums — they are plain Dart enums with no Drift dependency, and this
/// project deliberately favors pragmatic layering over an extra mapping layer
/// for no real benefit (docs/06_PROJECT_STRUCTURE.md: "avoid adding a fourth
/// layer of indirection for the future").
class DiseaseFinding {
  const DiseaseFinding({
    required this.id,
    required this.name,
    required this.category,
    required this.applicableTo,
    this.officialCode,
    this.description,
    this.isActive = true,
  });

  final String id;

  /// Job Aid code, verbatim (e.g. `'1'`, `'40.1'`). Null only if genuinely
  /// absent from the source — never invented.
  final String? officialCode;

  /// Official Job Aid wording, verbatim — never reworded.
  final String name;

  final DiseaseCategory category;
  final ApplicableTo applicableTo;
  final String? description;
  final bool isActive;
}
