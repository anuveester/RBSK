import 'dart:convert';

import 'package:referredline/data/local/database_connection.dart';

/// Local brute-force mitigation for repeated incorrect PIN attempts
/// (docs/28_AUTHENTICATION_ARCHITECTURE_DECISION.md §Security). This is the
/// only protection against on-device PIN guessing — there is no server to
/// rate-limit against, so it must be enforced here.
///
/// **Exact behavior, documented per the approval instruction — do not
/// overclaim beyond this:**
/// - After [maxAttempts] (5) consecutive failed attempts for one user, that
///   user is locked out for [cooldown] (60 seconds).
/// - A failed attempt made *during* an active lockout does not extend the
///   cooldown or increment the counter further — the cooldown is fixed and
///   always expires.
/// - A successful login resets the counter to zero.
/// - **There is no permanent lockout and no separate "forgot PIN" recovery
///   flow in this phase** — the fixed cooldown expiring is the only, and
///   deliberate, recovery path, which is what guarantees the sole Admin can
///   never be permanently locked out (per the approval instruction). A full
///   credential-reset flow (e.g. one Admin resetting another user's PIN)
///   needs another authenticated Admin to exist and is deferred to a later
///   Admin-tools phase (docs/13 Phase 7) — for a single freshly-bootstrapped
///   Admin, no such second account exists yet, so this is an honest,
///   documented limitation, not an oversight.
///
/// State is stored per user in [SecureKeyStore] (Android Keystore-backed),
/// never in the SQLite database — consistent with keeping all Phase 1.4
/// credential-adjacent state out of the encrypted business schema
/// (docs/28 §7 Option A).
class LoginLockoutTracker {
  LoginLockoutTracker(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final SecureKeyStore _store;
  final DateTime Function() _clock;

  static const int maxAttempts = 5;
  static const Duration cooldown = Duration(seconds: 60);

  String _key(String userId) => 'rbsk_auth_lockout_$userId';

  /// Returns the remaining lockout duration, or `null` if not currently
  /// locked out.
  Future<Duration?> checkLockout(String userId) async {
    final lockedUntil = (await _read(userId))?.lockedUntil;
    if (lockedUntil == null) {
      return null;
    }
    final remaining = lockedUntil.difference(_clock().toUtc());
    return remaining > Duration.zero ? remaining : null;
  }

  Future<void> recordFailure(String userId) async {
    final existing = await _read(userId);
    final now = _clock().toUtc();
    final lockedUntil = existing?.lockedUntil;

    // A failure during an active lockout does not extend it or increment
    // the counter further — documented behavior above.
    if (lockedUntil != null && lockedUntil.isAfter(now)) {
      return;
    }

    // An expired lockout starts a fresh count.
    final previous = lockedUntil == null ? (existing?.failureCount ?? 0) : 0;
    final failureCount = previous + 1;
    await _write(
      userId,
      failureCount >= maxAttempts
          ? _LockoutState(failureCount: 0, lockedUntil: now.add(cooldown))
          : _LockoutState(failureCount: failureCount),
    );
  }

  Future<void> recordSuccess(String userId) async {
    await _store.write(_key(userId), '');
  }

  Future<_LockoutState?> _read(String userId) async {
    final raw = await _store.read(_key(userId));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final lockedUntil = map['lockedUntil'] as String?;
      return _LockoutState(
        failureCount: map['failureCount'] as int,
        lockedUntil: lockedUntil == null ? null : DateTime.parse(lockedUntil),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> _write(String userId, _LockoutState state) async {
    await _store.write(
      _key(userId),
      jsonEncode({
        'failureCount': state.failureCount,
        'lockedUntil': state.lockedUntil?.toIso8601String(),
      }),
    );
  }
}

class _LockoutState {
  const _LockoutState({required this.failureCount, this.lockedUntil});

  final int failureCount;

  /// Null while not locked.
  final DateTime? lockedUntil;
}
