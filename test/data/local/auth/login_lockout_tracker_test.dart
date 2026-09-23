import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/data/local/auth/login_lockout_tracker.dart';

import '../../../support/in_memory_secure_key_store.dart';

void main() {
  late InMemorySecureKeyStore store;
  late DateTime now;
  late LoginLockoutTracker tracker;

  setUp(() {
    store = InMemorySecureKeyStore();
    now = DateTime.utc(2026, 9, 23, 10);
    tracker = LoginLockoutTracker(store, clock: () => now);
  });

  Future<void> fail(int times, [String user = 'u1']) async {
    for (var i = 0; i < times; i++) {
      await tracker.recordFailure(user);
    }
  }

  test('policy constants are the documented 5 attempts / 60 seconds', () {
    expect(LoginLockoutTracker.maxAttempts, 5);
    expect(LoginLockoutTracker.cooldown, const Duration(seconds: 60));
  });

  test('not locked before any failure, or after 4 failures', () async {
    expect(await tracker.checkLockout('u1'), isNull);
    await fail(4);
    expect(await tracker.checkLockout('u1'), isNull);
  });

  test('the 5th consecutive failure locks for 60 seconds', () async {
    await fail(5);
    expect(await tracker.checkLockout('u1'), const Duration(seconds: 60));
  });

  test('lockout expires on its own — there is no permanent lockout', () async {
    await fail(5);
    now = now.add(const Duration(seconds: 59));
    expect(await tracker.checkLockout('u1'), isNotNull);
    now = now.add(const Duration(seconds: 1));
    expect(await tracker.checkLockout('u1'), isNull);
  });

  test('failures during a lockout do not extend it', () async {
    await fail(5);
    now = now.add(const Duration(seconds: 30));
    await fail(10);
    expect(await tracker.checkLockout('u1'), const Duration(seconds: 30));
  });

  test('after a lockout expires, the count starts again from zero', () async {
    await fail(5);
    now = now.add(const Duration(seconds: 61));
    await fail(4);
    expect(await tracker.checkLockout('u1'), isNull);
    await fail(1);
    expect(await tracker.checkLockout('u1'), isNotNull);
  });

  test('a success resets the consecutive-failure count', () async {
    await fail(4);
    await tracker.recordSuccess('u1');
    await fail(4);
    expect(await tracker.checkLockout('u1'), isNull);
  });

  test('lockout is per user', () async {
    await fail(5, 'u1');
    expect(await tracker.checkLockout('u1'), isNotNull);
    expect(await tracker.checkLockout('u2'), isNull);
  });

  test(
    'a corrupted stored value fails open to "not locked", not a crash',
    () async {
      store.values['rbsk_auth_lockout_u1'] = '{not json';
      expect(await tracker.checkLockout('u1'), isNull);
      store.values['rbsk_auth_lockout_u1'] = '{"failureCount":"x"}';
      expect(await tracker.checkLockout('u1'), isNull);
      await tracker.recordFailure('u1');
    },
  );
}
