import 'package:referredline/core/auth/pin_policy.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/utils/id_generator.dart';
import 'package:referredline/data/local/auth/auth_session_codec.dart';
import 'package:referredline/data/local/auth/credential_hasher.dart';
import 'package:referredline/data/local/auth/login_lockout_tracker.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/domain/entities/auth_session.dart';
import 'package:referredline/domain/entities/auth_status.dart';
import 'package:referredline/domain/repositories/auth_repository.dart';
import 'package:referredline/domain/repositories/user_repository.dart';

/// Option A from docs/28_AUTHENTICATION_ARCHITECTURE_DECISION.md — the
/// approved, only implementation of [AuthRepository] in Phase 1.4. Verifies
/// credentials entirely on-device, never over a network, and stores nothing
/// credential-shaped in the SQLite database (see `credential_hasher.dart`
/// for the derivation and `login_lockout_tracker.dart` for the brute-force
/// mitigation this class delegates to).
/// `SecureKeyStore` key holding a user's credential verifier
/// (docs/27_PHASE_1_4_PLAN.md §0.1). Holds the derived verifier only, never
/// the PIN.
String credentialVerifierStorageKey(String userId) =>
    'rbsk_credential_verifier_$userId';

/// `SecureKeyStore` key holding the persisted local session.
const String authSessionStorageKey = 'rbsk_active_session_v1';

class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository({
    required UserRepository userRepository,
    required SecureKeyStore keyStore,
    DateTime Function()? clock,
  }) : _users = userRepository,
       _store = keyStore,
       _clock = clock ?? DateTime.now,
       _lockout = LoginLockoutTracker(keyStore, clock: clock);

  final UserRepository _users;
  final SecureKeyStore _store;
  final DateTime Function() _clock;
  final LoginLockoutTracker _lockout;

  static const String _sessionKey = authSessionStorageKey;

  String _credentialKey(String userId) => credentialVerifierStorageKey(userId);

  @override
  Future<AuthStatus> determineStatus() async {
    if (!await _users.hasAnyUsers()) {
      return const AuthUninitialized();
    }

    final session = await currentSession();
    return session == null ? const AuthLoggedOut() : AuthAuthenticated(session);
  }

  @override
  Future<AuthSession> setupBootstrapAdmin({
    required String displayName,
    required String pin,
  }) async {
    if (await _users.hasAnyUsers()) {
      throw const BootstrapAlreadyCompletedFailure();
    }
    final name = displayName.trim();
    if (name.isEmpty) {
      throw const InvalidDisplayNameFailure();
    }
    if (!PinPolicy.isValid(pin)) {
      throw const InvalidPinFormatFailure();
    }

    // Verifier first, user row second: if the secure-storage write fails, no
    // user exists yet and setup can simply be retried. The reverse order
    // could leave an Admin row with no credential, which would lock setup
    // out permanently (any user existing = setup already done).
    final userId = generateLocalId('user');
    await _store.write(
      _credentialKey(userId),
      await deriveCredentialVerifierInBackground(pin),
    );
    await _users.createUser(id: userId, displayName: name, role: AppRole.ADMIN);

    return _establishSession(userId: userId, role: AppRole.ADMIN);
  }

  @override
  Future<AuthSession> login({
    required String userId,
    required String pin,
  }) async {
    final lockedFor = await _lockout.checkLockout(userId);
    if (lockedFor != null) {
      throw AccountLockedFailure(lockedFor);
    }

    final user = await _users.getById(userId);
    if (user == null) {
      // Same rejection as a wrong PIN — do not reveal whether the id existed.
      await _lockout.recordFailure(userId);
      throw const InvalidCredentialsFailure();
    }

    if (!user.isActive) {
      throw const AccountDeactivatedFailure();
    }

    final verifier = await _store.read(_credentialKey(userId));
    final valid =
        verifier != null && await verifyCredentialInBackground(pin, verifier);
    if (!valid) {
      await _lockout.recordFailure(userId);
      throw const InvalidCredentialsFailure();
    }

    await _lockout.recordSuccess(userId);
    final now = _clock().toUtc();
    await _users.recordLogin(userId, now);
    return _establishSession(userId: userId, role: user.role, at: now);
  }

  @override
  Future<void> logout() async {
    await _store.write(_sessionKey, '');
  }

  @override
  Future<AuthSession?> currentSession() async {
    final raw = await _store.read(_sessionKey);
    final session = decodeAuthSession(raw);
    if (session == null) {
      return null;
    }

    // Fail closed if the referenced user no longer exists or was
    // deactivated since the session was established — docs/28 §6: this is
    // a best-effort, device-local check, not real-time cross-device
    // revocation, which needs a sync mechanism that doesn't exist yet.
    final user = await _users.getById(session.userId);
    if (user == null || !user.isActive) {
      await logout();
      return null;
    }

    // Identity is the persisted user id; the role is read from the current
    // `users` row, so a role change takes effect on the next restore rather
    // than trusting the role cached at login.
    return AuthSession(
      userId: user.id,
      role: user.role,
      loggedInAt: session.loggedInAt,
    );
  }

  Future<AuthSession> _establishSession({
    required String userId,
    required AppRole role,
    DateTime? at,
  }) async {
    final session = AuthSession(
      userId: userId,
      role: role,
      loggedInAt: at ?? _clock().toUtc(),
    );
    await _store.write(_sessionKey, encodeAuthSession(session));
    return session;
  }
}
