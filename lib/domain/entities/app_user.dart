import 'package:referredline/data/local/enums.dart';

/// Plain read-model for `users` (docs/04_DATABASE_ARCHITECTURE.md §2.1).
///
/// `AppRole` is reused directly from `data/local/enums.dart`, matching the
/// pattern already established by `DiseaseFinding` (see that file's own
/// comment). No credential material of any kind is represented here — the
/// frozen `users` table has no credential column, and this type must never
/// grow one (docs/28_AUTHENTICATION_ARCHITECTURE_DECISION.md).
class AppUser {
  const AppUser({
    required this.id,
    required this.displayName,
    required this.role,
    required this.isActive,
    this.email,
  });

  final String id;
  final String displayName;
  final AppRole role;
  final bool isActive;
  final String? email;
}
