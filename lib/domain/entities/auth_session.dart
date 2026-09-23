import 'package:referredline/data/local/enums.dart';

/// What's remembered locally between app launches — deliberately not called
/// a "token": there is no cloud identity provider yet (docs/28
/// §Cloud/future-sync implications), so naming this a token would overclaim
/// what it is. Identifies the authenticated user by UUID/local id, never by
/// display name, so it stays correct even if a display name is later edited.
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.role,
    required this.loggedInAt,
  });

  final String userId;
  final AppRole role;
  final DateTime loggedInAt;
}
