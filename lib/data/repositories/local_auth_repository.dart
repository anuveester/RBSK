import 'package:referredline/core/auth/pin_policy.dart';
import 'package:referredline/core/errors/failure.dart';
import 'package:referredline/core/security/secret_code.dart';
import 'package:referredline/core/utils/id_generator.dart';
import 'package:referredline/data/local/auth/admin_recovery_code_store.dart';
import 'package:referredline/data/local/auth/auth_session_codec.dart';
import 'package:referredline/data/local/auth/credential_hasher.dart';
import 'package:referredline/data/local/auth/login_lockout_tracker.dart';
import 'package:referredline/data/local/database_connection.dart';
import 'package:referredline/data/local/enums.dart';
import 'package:referredline/data/local/recovery/backup_key_store.dart';
import 'package:referredline/data/local/security/security_audit.dart';
import 'package:referredline/domain/entities/app_user.dart';
import 'package:referredline/domain/entities/auth_recovery.dart';
import 'package:referredline/domain/entities/auth_session.dart';
import 'package:referredline/domain/entities/auth_status.dart';
import 'package:referredline/domain/repositories/auth_repository.dart';
import 'package:referredline/domain/repositories/user_repository.dart';

/// `SecureKeyStore` key holding a user's credential verifier
/// (docs/27_PHASE_1_4_PLAN.md §0.1). Holds the derived verifier only, never
/// the PIN.
String credentialVerifierStorageKey(String userId) =>
    'rbsk_credential_verifier_$userId';

/// `SecureKeyStore` key holding the persisted local session.
const String authSessionStorageKey = 'rbsk_active_session_v1';

/// Lockout identities for recovery attempts (not user ids).
const String recoveryCodeAttemptsId = 'admin-recovery-code';
const String backupKeyAttemptsId = 'backup-recovery-key';

class _DiscardingSink implements SecurityEventSink {
  const _DiscardingSink();

  @override
  Future<void> record(SecurityEvent event) async {}
}

/// Option A from docs/28_AUTHENTICATION_ARCHITECTURE_DECISION.md — the
/// approved, only implementation of [AuthRepository]. Verifies credentials
/// entirely on-device, never over a network, and stores nothing
/// credential-shaped in the SQLite database.
///
/// Recovery (docs/30 R1, R5) never touches the database encryption key or
/// the database: it only re-issues credential verifiers.
class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository({
    required UserRepository userRepository,
    required SecureKeyStore keyStore,
    SecurityEventSink? audit,
    BackupKeyStore? backupKeys,
    this._kdfPolicy = CredentialKdfPolicy.current,
    DateTime Function()? clock,
  }) : _users = userRepository,
       _store = keyStore,
       _audit = audit ?? const _DiscardingSink(),
       _backupKeys = backupKeys ?? BackupKeyStore(keyStore),
       _recovery = AdminRecoveryCodeStore(keyStore),
       _clock = clock ?? DateTime.now,
       _lockout = LoginLockoutTracker(keyStore, clock: clock);

  final UserRepository _users;
  final SecureKeyStore _store;
  final SecurityEventSink _audit;
  final BackupKeyStore _backupKeys;
  final AdminRecoveryCodeStore _recovery;
  final CredentialKdfPolicy _kdfPolicy;
  final DateTime Function() _clock;
  final LoginLockoutTracker _lockout;

  static const String _sessionKey = authSessionStorageKey;

  String _credentialKey(String userId) => credentialVerifierStorageKey(userId);

  DateTime _now() => _clock().toUtc();

  @override
  Future<AuthStatus> determineStatus() async {
    if (!await _users.hasAnyUsers()) {
      return const AuthUninitialized();
    }
    try {
      final session = await currentSession();
      return session == null
          ? const AuthLoggedOut()
          : AuthAuthenticated(session);
    } on SecureStorageUnavailableException {
      await _audit.record(
        SecurityEvent(
          SecurityEventType.secureStorageFailure,
          details: {'operation': 'restoreSession'},
        ),
      );
      rethrow;
    }
  }

  @override
  Future<RecoveryCodeIssued> setupBootstrapAdmin({
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

    final userId = generateUuidV4();
    final pinVerifier = await _derive(pin);
    final code = SecretCode.generate(SecretCodeKind.adminRecovery);
    final codeVerifier = await _derive(code.canonical);

    // Secrets first, user row last: if any secure-storage write fails, no
    // user exists yet and setup can simply be retried. The reverse order
    // could leave an Admin with no credential, which would lock setup out
    // permanently (any user existing = setup already done).
    await _guardStorage(() async {
      await _store.write(_credentialKey(userId), pinVerifier);
      await _recovery.write(
        AdminRecoveryRecord(
          userId: userId,
          verifier: codeVerifier,
          createdAt: _now(),
          acknowledged: false,
        ),
      );
    });
    await _users.createUser(id: userId, displayName: name, role: AppRole.ADMIN);

    final session = await _establishSession(userId: userId, role: AppRole.ADMIN);
    await _audit.record(
      SecurityEvent(
        SecurityEventType.adminRecoveryCodeCreated,
        subjectUserId: userId,
        actorUserId: userId,
        details: {'trigger': 'firstRunSetup'},
      ),
    );
    return RecoveryCodeIssued(session: session, recoveryCode: code.formatted);
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
    await _upgradeVerifierIfNeeded(userId, pin, verifier);
    final now = _now();
    await _users.recordLogin(userId, now);
    return _establishSession(userId: userId, role: user.role, at: now);
  }

  /// Re-derives an outdated verifier with the current KDF policy after a
  /// successful login. On any failure the old — still valid — verifier is
  /// kept, so an upgrade problem can never lock the user out.
  Future<void> _upgradeVerifierIfNeeded(
    String userId,
    String pin,
    String verifier,
  ) async {
    if (!verifierNeedsRehash(verifier, policy: _kdfPolicy)) {
      return;
    }
    try {
      final upgraded = await _derive(pin);
      await _store.write(_credentialKey(userId), upgraded);
      await _audit.record(
        SecurityEvent(
          SecurityEventType.pinVerifierUpgraded,
          subjectUserId: userId,
          actorUserId: userId,
          details: {'iterations': '${_kdfPolicy.iterations}'},
        ),
      );
    } catch (_) {
      // Keep the old verifier; the upgrade is retried at the next login.
    }
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

  // --- Authorization for privileged operations ------------------------------

  @override
  Future<AuthSession> requireAdminSession({String operation = 'admin'}) async {
    final AuthSession? session;
    try {
      session = await currentSession();
    } on SecureStorageUnavailableException {
      throw const SecureStorageFailure();
    }
    if (session == null) {
      await _denied(operation, 'noSession', null);
      throw const NoActiveSessionFailure();
    }
    if (session.role != AppRole.ADMIN) {
      await _denied(operation, 'notAdmin', session.userId);
      throw const NotAuthorizedFailure();
    }
    return session;
  }

  @override
  Future<AuthSession> reauthenticateAdmin({
    required String pin,
    String operation = 'admin',
  }) async {
    final session = await requireAdminSession(operation: operation);
    final lockedFor = await _lockout.checkLockout(session.userId);
    if (lockedFor != null) {
      await _denied(operation, 'lockedOut', session.userId);
      throw AccountLockedFailure(lockedFor);
    }
    final String? verifier;
    try {
      verifier = await _store.read(_credentialKey(session.userId));
    } on SecureStorageUnavailableException {
      throw const SecureStorageFailure();
    }
    final valid =
        verifier != null && await verifyCredentialInBackground(pin, verifier);
    if (!valid) {
      await _lockout.recordFailure(session.userId);
      await _denied(operation, 'wrongPin', session.userId);
      throw const InvalidCredentialsFailure();
    }
    await _lockout.recordSuccess(session.userId);
    return session;
  }

  Future<void> _denied(String operation, String reason, String? actor) =>
      _audit.record(
        SecurityEvent(
          SecurityEventType.privilegedActionDenied,
          actorUserId: actor,
          details: {'operation': operation, 'reason': reason},
        ),
      );

  // --- Admin Recovery Code ----------------------------------------------------

  @override
  Future<AdminRecoveryStatus> adminRecoveryStatus() async {
    final record = await _recovery.read();
    if (record == null) {
      return AdminRecoveryStatus.none;
    }
    return AdminRecoveryStatus(
      exists: true,
      adminUserId: record.userId,
      acknowledged: record.acknowledged,
      createdAt: record.createdAt,
    );
  }

  @override
  Future<void> confirmRecoveryCodeRecorded() async {
    final record = await _recovery.read();
    if (record == null || record.acknowledged) {
      return;
    }
    // Only the code's own Admin, logged in right now, can say it is written
    // down; otherwise "confirmed" could hide a code nobody recorded.
    final session = await requireAdminSession(operation: 'confirmRecoveryCode');
    if (session.userId != record.userId) {
      await _denied('confirmRecoveryCode', 'notCodeOwner', session.userId);
      throw const NotAuthorizedFailure();
    }
    await _guardStorage(() => _recovery.write(record.copyWith(acknowledged: true)));
    await _audit.record(
      SecurityEvent(
        SecurityEventType.adminRecoveryCodeConfirmed,
        subjectUserId: record.userId,
        actorUserId: session.userId,
      ),
    );
  }

  @override
  Future<RecoveryCodeIssued> resetPinWithRecoveryCode({
    required String recoveryCode,
    required String newPin,
  }) async {
    if (!PinPolicy.isValid(newPin)) {
      throw const InvalidPinFormatFailure();
    }
    // A mistyped code is not an attempt: it is rejected before the lockout
    // and without touching stored state.
    final code = _parseCode(recoveryCode, SecretCodeKind.adminRecovery);

    final lockedFor = await _lockout.checkLockout(recoveryCodeAttemptsId);
    if (lockedFor != null) {
      await _audit.record(
        SecurityEvent(
          SecurityEventType.pinResetWithRecoveryCodeRejected,
          details: {'reason': 'lockedOut'},
        ),
      );
      throw AccountLockedFailure(lockedFor);
    }

    final record = await _recovery.read();
    if (record == null) {
      throw const NoRecoveryCodeFailure();
    }
    if (!await verifyCredentialInBackground(code.canonical, record.verifier)) {
      await _lockout.recordFailure(recoveryCodeAttemptsId);
      await _audit.record(
        SecurityEvent(
          SecurityEventType.pinResetWithRecoveryCodeRejected,
          subjectUserId: record.userId,
          details: {'reason': 'invalidCode'},
        ),
      );
      throw const InvalidRecoveryCodeFailure();
    }

    final user = await _users.getById(record.userId);
    if (user == null || !user.isActive || user.role != AppRole.ADMIN) {
      await _audit.record(
        SecurityEvent(
          SecurityEventType.pinResetWithRecoveryCodeRejected,
          subjectUserId: record.userId,
          details: {'reason': 'adminNotActive'},
        ),
      );
      throw const RecoveryAccountUnavailableFailure();
    }

    // 1. New PIN. If this fails nothing has changed and the code still works.
    final pinVerifier = await _derive(newPin);
    await _guardStorage(() => _store.write(_credentialKey(user.id), pinVerifier));
    await _lockout.recordSuccess(recoveryCodeAttemptsId);
    await _lockout.recordSuccess(user.id);

    // 2. Use up the code by replacing it. If this fails the PIN is still
    //    reset and the old code remains valid — never a state where nobody
    //    can get in.
    final issued = await _issueRecoveryCode(user.id);

    final now = _now();
    await _users.recordLogin(user.id, now);
    final session = await _establishSession(userId: user.id, role: user.role, at: now);
    await _audit.record(
      SecurityEvent(
        SecurityEventType.pinResetWithRecoveryCodeSucceeded,
        subjectUserId: user.id,
        details: {'newRecoveryCodeSaved': '${issued != null}'},
      ),
    );
    return RecoveryCodeIssued(
      session: session,
      recoveryCode: issued,
      recoveryCodeSaved: issued != null,
    );
  }

  @override
  Future<String> createNewRecoveryCode({required String currentPin}) async {
    final session = await reauthenticateAdmin(
      pin: currentPin,
      operation: 'createRecoveryCode',
    );
    final code = SecretCode.generate(SecretCodeKind.adminRecovery);
    final verifier = await _derive(code.canonical);
    await _guardStorage(
      () => _recovery.write(
        AdminRecoveryRecord(
          userId: session.userId,
          verifier: verifier,
          createdAt: _now(),
          acknowledged: false,
        ),
      ),
    );
    await _audit.record(
      SecurityEvent(
        SecurityEventType.adminRecoveryCodeCreated,
        subjectUserId: session.userId,
        actorUserId: session.userId,
        details: {'trigger': 'replacedByAdmin'},
      ),
    );
    return code.formatted;
  }

  // --- After a restore ------------------------------------------------------

  @override
  Future<bool> hasAdminAbleToLogIn() async {
    final admins = (await _users.getAllActive()).where(
      (u) => u.role == AppRole.ADMIN,
    );
    for (final admin in admins) {
      final verifier = await _store.read(_credentialKey(admin.id));
      if (verifier != null && verifier.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<RecoveryCodeIssued> restoreAdminAccess({
    required String backupKey,
    required String adminUserId,
    required String newPin,
  }) async {
    if (await hasAdminAbleToLogIn()) {
      throw const AdminAccessRestoreNotAllowedFailure();
    }
    if (!PinPolicy.isValid(newPin)) {
      throw const InvalidPinFormatFailure();
    }
    final code = _parseCode(backupKey, SecretCodeKind.backupRecovery);

    final lockedFor = await _lockout.checkLockout(backupKeyAttemptsId);
    if (lockedFor != null) {
      throw AccountLockedFailure(lockedFor);
    }
    final material = await _backupKeys.read();
    if (material == null) {
      throw const NoBackupKeyFailure();
    }
    if (!material.matches(code)) {
      await _lockout.recordFailure(backupKeyAttemptsId);
      await _audit.record(
        SecurityEvent(
          SecurityEventType.adminAccessRestoreRejected,
          subjectUserId: adminUserId,
          details: {'reason': 'invalidBackupKey'},
        ),
      );
      throw const InvalidBackupKeyFailure();
    }
    final user = await _activeAdmin(adminUserId);

    final pinVerifier = await _derive(newPin);
    await _guardStorage(() => _store.write(_credentialKey(user.id), pinVerifier));
    await _lockout.recordSuccess(backupKeyAttemptsId);
    final issued = await _issueRecoveryCode(user.id);

    final now = _now();
    await _users.recordLogin(user.id, now);
    final session = await _establishSession(userId: user.id, role: user.role, at: now);
    await _audit.record(
      SecurityEvent(
        SecurityEventType.adminAccessRestoredWithBackupKey,
        subjectUserId: user.id,
        details: {'backupKeyId': material.keyId},
      ),
    );
    return RecoveryCodeIssued(
      session: session,
      recoveryCode: issued,
      recoveryCodeSaved: issued != null,
    );
  }

  // --- Helpers ----------------------------------------------------------------

  Future<String> _derive(String secret) =>
      deriveCredentialVerifierInBackground(secret, policy: _kdfPolicy);

  /// Creates, stores and audits a new Admin Recovery Code for [userId].
  /// Returns its formatted text, or null if it could not be stored (the
  /// previous code, if any, then stays valid).
  Future<String?> _issueRecoveryCode(String userId) async {
    final code = SecretCode.generate(SecretCodeKind.adminRecovery);
    try {
      final verifier = await _derive(code.canonical);
      await _recovery.write(
        AdminRecoveryRecord(
          userId: userId,
          verifier: verifier,
          createdAt: _now(),
          acknowledged: false,
        ),
      );
    } catch (_) {
      return null;
    }
    await _audit.record(
      SecurityEvent(
        SecurityEventType.adminRecoveryCodeCreated,
        subjectUserId: userId,
        details: {'trigger': 'afterRecovery'},
      ),
    );
    return code.formatted;
  }

  Future<AppUser> _activeAdmin(String userId) async {
    final user = await _users.getById(userId);
    if (user == null || !user.isActive || user.role != AppRole.ADMIN) {
      throw const NotAuthorizedFailure();
    }
    return user;
  }

  SecretCode _parseCode(String text, SecretCodeKind kind) {
    try {
      return SecretCode.parse(text, kind);
    } on SecretCodeFormatException catch (e) {
      throw RecoveryCodeTypingFailure(switch (e.problem) {
        SecretCodeProblem.wrongKind =>
          kind == SecretCodeKind.adminRecovery
              ? 'This looks like the Backup Recovery Key. '
                    'Please enter the Admin Recovery Code (it starts with AR).'
              : 'This looks like the Admin Recovery Code. '
                    'Please enter the Backup Recovery Key (it starts with BK).',
        SecretCodeProblem.checkFailed =>
          'There is a typing mistake in the code. Please check each character.',
        SecretCodeProblem.invalidFormat =>
          'The code should have 27 letters and numbers, '
              'like ${kind.prefix}-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXX.',
      });
    }
  }

  Future<void> _guardStorage(Future<void> Function() action) async {
    try {
      await action();
    } on SecureStorageUnavailableException {
      await _audit.record(
        SecurityEvent(
          SecurityEventType.secureStorageFailure,
          details: {'operation': 'write'},
        ),
      );
      throw const SecureStorageFailure();
    }
  }

  Future<AuthSession> _establishSession({
    required String userId,
    required AppRole role,
    DateTime? at,
  }) async {
    final session = AuthSession(
      userId: userId,
      role: role,
      loggedInAt: at ?? _now(),
    );
    await _store.write(_sessionKey, encodeAuthSession(session));
    return session;
  }
}
