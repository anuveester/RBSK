import 'package:referredline/data/local/enums.dart';
import 'package:referredline/domain/entities/app_user.dart';

abstract interface class UserRepository {
  /// True iff at least one `users` row exists — the signal that
  /// distinguishes first-run (uninitialized) from every later state.
  Future<bool> hasAnyUsers();

  Future<AppUser?> getById(String id);

  Future<List<AppUser>> getAllActive();

  /// Creates the one bootstrap Admin row. Callers (see
  /// `LocalAuthRepository.setupBootstrapAdmin`) must guarantee this is only
  /// ever called when [hasAnyUsers] was false — this method itself performs
  /// no such guard, since "is this the first user" is an authentication
  /// policy decision, not a data-layer concern.
  Future<AppUser> createUser({
    required String id,
    required String displayName,
    required AppRole role,
  });

  Future<void> recordLogin(String id, DateTime at);
}
