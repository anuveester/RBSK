import 'auth_session.dart';

/// The three conceptual authentication states the app can be in
/// (docs/28_AUTHENTICATION_ARCHITECTURE_DECISION.md §First-run Admin setup):
///
/// - [AuthUninitialized]: no `users` row exists anywhere yet — the app has
///   never had its bootstrap Admin set up. Only reachable before the very
///   first Admin setup completes; once any user exists, this state can never
///   recur, which is what prevents bootstrap setup from accidentally running
///   twice.
/// - [AuthLoggedOut]: at least one user exists, but no session is currently
///   active on this device.
/// - [AuthAuthenticated]: a session is active and restorable, entirely
///   offline (read from secure storage, never from a network call).
sealed class AuthStatus {
  const AuthStatus();
}

final class AuthUninitialized extends AuthStatus {
  const AuthUninitialized();
}

final class AuthLoggedOut extends AuthStatus {
  const AuthLoggedOut();
}

final class AuthAuthenticated extends AuthStatus {
  const AuthAuthenticated(this.session);

  final AuthSession session;
}
