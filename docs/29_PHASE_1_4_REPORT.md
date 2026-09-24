# Phase 1.4 — Implementation Report

> **HISTORICAL — REMOVED IMPLEMENTATION (2026-09-24).** The Phase 1.4 authentication implementation was intentionally removed. Authentication will be redesigned and implemented from scratch after the complete functional application is finished.
> This document describes the removed implementation (and, where relevant,
> the backup/recovery features removed with it). None of the code it
> describes is part of the current application, and this document is not a
> plan for restoring it. Current status:
> [00_PROJECT_MASTER_PLAN.md](00_PROJECT_MASTER_PLAN.md) §0.

**Status: IMPLEMENTED — independent verification completed (PASS WITH
FIXES, §20). NOT CLOSED.** Closure requires your explicit approval, the same
as Phases 1.1–1.3. §1–§19 describe the implementation as reported at
`4fe2e06`; where the verification pass changed something, §20 says so.

| | |
|---|---|
| Date | 2026-09-23 |
| Plan and final decisions | [27_PHASE_1_4_PLAN.md](27_PHASE_1_4_PLAN.md) §0 |
| Architecture analysis | [28_AUTHENTICATION_ARCHITECTURE_DECISION.md](28_AUTHENTICATION_ARCHITECTURE_DECISION.md) |
| Baseline | `cbb225b` (Phase 1.3 closed at `a12227d`) |
| Implementation commits | `b797ac3` (implementation), `09f4b0b` (UUIDv4 fix, see §18) |
| Flutter / Dart | 3.47.2 / 3.13.2 |

## 1. Architecture implemented

Option A, behind an `AuthRepository` abstraction, keeping the five layers
from docs/28 §10 separate:

| Layer | Implementation |
|---|---|
| Identity | Existing `users` table, read and written through `UserRepository` / `DriftUserRepository`. No schema change. |
| Credential | `LocalAuthRepository` (the only `AuthRepository` implementation) with a PBKDF2 verifier in `SecureKeyStore`. |
| Session | `AuthSession` (user id, role, login time) persisted in `SecureKeyStore`; `AuthStatus` = `AuthUninitialized` / `AuthLoggedOut` / `AuthAuthenticated`. |
| RBAC | `moreMenuItemsFor(AppRole)` read model plus the route guard `resolveAuthRedirect`. |
| Audit identity | `users.id` (a UUIDv4), which future `created_by`/`updated_by` values will reference. `last_login_at` is recorded on each login. |

Only `authRepositoryProvider` names `LocalAuthRepository`. Replacing it with
a future cloud implementation changes that one provider and nothing in the
session, RBAC, or router code.

## 2. Credential mechanism and exact parameters

| | |
|---|---|
| Algorithm | PBKDF2-HMAC-SHA256 (`pointycastle` 4.0.0: `PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))`) |
| Iterations | 210,000 |
| Salt | 16 bytes from `Random.secure()`, new for every credential, **not secret**: stored inside the verifier |
| Derived key | 32 bytes |
| Verifier format | `pbkdf2-hmac-sha256$210000$<base64 salt>$<base64 key>` |
| Comparison | Constant-time |
| Execution | On a background isolate (`Isolate.run`) so the UI doesn't freeze |
| Storage | `SecureKeyStore` key `rbsk_credential_verifier_<users.id>`. Never the database, never a log. |
| PIN format | Exactly 6 digits. Enforced in the repository (`PinPolicy`), not only in the UI. |

Why this package and these parameters, including the deliberate gap from
OWASP's current 600,000-iteration figure, is recorded in docs/27 §0.1 and
in `credential_hasher.dart`'s own documentation.

**Measured cost:** about 1.3–1.7 s per derivation in the Flutter test VM
(debug/JIT on this development machine). This is **not** a measurement of a
release build on an Android phone. On-device benchmarking is still
outstanding (§18).

## 3. First-run Admin flow

1. At startup `determineStatus()` counts `users` rows. Zero rows means
   `AuthUninitialized`, and the router sends every location to `/setup`.
2. The setup screen asks for the Administrator's name, a 6-digit PIN, and a
   confirmation. Mismatched or invalid input is rejected, the PIN fields are
   cleared, and nothing is written.
3. `setupBootstrapAdmin`:
   - refuses with `BootstrapAlreadyCompletedFailure` if any user exists;
   - validates the name and PIN;
   - writes the verifier to secure storage first, then inserts the `users`
     row (role `ADMIN`, `staff_id` NULL, UUIDv4 id). If the storage write
     fails, no user exists and setup can simply be retried;
   - establishes a session.
4. The app goes straight to Home. From then on the status can never be
   `AuthUninitialized` again, so `/setup` redirects to `/login`. Re-running
   setup is blocked twice over: by the router and by the repository.

No Admin is created automatically, and no default PIN exists anywhere.

## 4. Session architecture

- Persisted under `rbsk_active_session_v1` in `SecureKeyStore` as
  `{userId, role, loggedInAt}`. No PIN, no health data.
- **Restoration (offline):** the session is read, then the `users` row is
  re-checked. If the user is missing or deactivated, the session is cleared
  and the user is logged out. The role is taken from the current `users`
  row, not the cached copy, so identity is the id and the role is always
  current.
- A corrupted session value is treated as logged out and never crashes the
  app.
- **Logout** clears the stored session. The credential is kept, so the user
  can log in again.
- **No expiry and no inactivity timeout** in Phase 1.4. A session lasts until
  logout or deactivation. See §18.
- No server tokens were invented; there is no server.

## 5. RBAC implementation

Uses the existing `AppRole` enum (`ADMIN`, `MEDICAL_OFFICER`,
`TEAM_MEMBER`); no new roles were added. The mapping is sourced from the
docs/04 §3 matrix:

- All three roles may open all five destinations. The matrix grants every
  role access to visit plans, screenings, referrals/treatment entry, and
  reports.
- `backup export / audit log` are ADMIN-only, so the `More` menu shows
  **Backup Export** and **Audit Log** entries to ADMIN only. They are inert
  labels; those screens belong to later phases.

## 6. Route guards

`resolveAuthRedirect(status, location)` is a pure function that go_router
runs on every navigation, including a direct `go('/reports')` or deep link:

| State | Behavior |
|---|---|
| Loading | Everything goes to `/splash` (which shows an error if local data can't be opened) |
| Uninitialized | Everything goes to `/setup` |
| Logged out | Everything goes to `/login`, including `/setup` and unknown paths |
| Authenticated | `/login`, `/setup`, `/splash` go to Home; all five destinations are allowed |

The router is created once. Auth changes reach it through a
`ValueListenable` (`refreshListenable`), and logout returns to `/login`
immediately.

There is **no role-restricted route** in Phase 1.4, because no Admin-only
screen exists yet. Role gating currently happens at the `More` menu level.
When an Admin-only screen is added, its route will need a role check in
this function.

## 7. Navigation per role

| | Home | Visits | Referrals | Reports | More | More: Backup Export, Audit Log | More: Log out |
|---|---|---|---|---|---|---|---|
| ADMIN | yes | yes | yes | yes | yes | shown | yes |
| MEDICAL_OFFICER | yes | yes | yes | yes | yes | absent | yes |
| TEAM_MEMBER | yes | yes | yes | yes | yes | absent | yes |

Each row is verified by a widget test that walks every destination for that
role. All five destinations are placeholder stubs with no business logic.

## 8. Brute-force mitigation

Exact behavior (also in docs/27 §0.3):
- 5 consecutive wrong PINs for one user lock that user for 60 seconds.
- An attempt during the lockout is refused without checking the PIN, even if
  the PIN is correct, and does not extend the lockout.
- A success resets the count. Lockouts are per user.
- The lockout always expires, so it is never permanent.
- State is stored per user in `SecureKeyStore`. Corrupted state is treated as
  "not locked".
- **What this does not protect against:** anyone who can modify app storage
  on a rooted device can reset the counter. Against an extracted verifier,
  the protection is the KDF cost, not the lockout.
- An unknown user id counts as a wrong PIN. A deactivated user gets
  "account deactivated" and never reaches PIN verification.

## 9. Files created and modified

**Created, `lib/` (27):**
```
core/auth/pin_policy.dart
core/rbac/more_menu_items.dart
core/router/app_shell.dart
core/router/auth_redirect.dart
core/utils/id_generator.dart
core/widgets/placeholder_destination.dart
data/local/auth/auth_session_codec.dart
data/local/auth/credential_hasher.dart
data/local/auth/login_lockout_tracker.dart
data/repositories/drift_user_repository.dart
data/repositories/local_auth_repository.dart
domain/entities/app_user.dart
domain/entities/auth_session.dart
domain/entities/auth_status.dart
domain/repositories/auth_repository.dart
domain/repositories/user_repository.dart
features/auth/presentation/controllers/auth_controller.dart
features/auth/presentation/controllers/auth_providers.dart
features/auth/presentation/screens/admin_setup_screen.dart
features/auth/presentation/screens/login_screen.dart
features/auth/presentation/screens/splash_screen.dart
features/auth/presentation/widgets/pin_field.dart
features/home/presentation/screens/home_screen.dart
features/more/presentation/screens/more_screen.dart
features/referrals/presentation/screens/referrals_placeholder_screen.dart
features/reports/presentation/screens/reports_placeholder_screen.dart
features/visits/presentation/screens/visits_placeholder_screen.dart
```

**Modified, `lib/`:** `core/errors/failure.dart` (auth failure subtypes),
`core/router/app_router.dart` (shell, guard, auth routes),
`core/router/routes.dart` (route constants).

**Removed:** `features/home/presentation/screens/home_placeholder_screen.dart`,
folded into the shell as planned in docs/27 §20.

**Tests created (11):** `support/in_memory_secure_key_store.dart`,
`support/app_harness.dart`, `core/rbac/more_menu_items_test.dart`,
`core/router/auth_redirect_test.dart`, `core/utils/id_generator_test.dart`,
`data/local/auth/credential_hasher_test.dart`,
`data/local/auth/login_lockout_tracker_test.dart`,
`data/repositories/user_repository_test.dart`,
`data/repositories/local_auth_repository_test.dart`,
`features/auth/auth_flow_test.dart`,
`features/navigation/role_navigation_test.dart`.

**Tests modified:**
- `app_smoke_test.dart` and `core/router/app_router_test.dart`: rewritten,
  because both asserted the removed Phase 1.1 placeholder screen.
- `data/local/database_connection_test.dart` (Phase 1.2): **timeout-only
  change**; see §12.

**Other:** `pubspec.yaml` and `pubspec.lock` (`pointycastle`), and docs
(this file, docs/27, docs/28 header, docs/00).

**Not touched:** every file under `lib/data/local/tables/`,
`app_database.dart`, `enums.dart`, all of `lib/data/local/seed/`,
`build.yaml`, and Android sources.

## 10. Dependencies added

| Package | Version | Why | Checks |
|---|---|---|---|
| `pointycastle` | 4.0.0 | PBKDF2 for the PIN verifier | Pure Dart, no native build. SDK constraint `^3.2.0`, compatible with `^3.13.2`. Its dependencies (`collection`, `convert`) were already in the graph, so the lockfile delta is this one package. Source repository per its pubspec: `github.com/bcgit/pc-dart`. (An earlier draft said "published by the Bouncy Castle project"; the pub.dev publisher was not verified, so that wording was corrected at verification.) |

Nothing else was added: no `uuid` (§1 uses `Random.secure()`), no `crypto`,
no Supabase, and no biometrics.

## 11. Schema verification

| Check | Result |
|---|---|
| `schemaVersion` | **1** (`app_database.dart:79`) |
| Migration | None. No `onUpgrade` step. |
| Tables, enums, seed files, `build.yaml` | `git diff --stat a12227d -- lib/data/local/tables/ lib/data/local/app_database.dart lib/data/local/enums.dart lib/data/local/seed/ build.yaml` is **empty** |
| Table count | **28**, asserted by `app_database_test.dart` and by `seed_runner_test.dart` after seeding; both pass |
| Credential column or table | None. The verifier lives only in `SecureKeyStore`. |
| Phase 1.3 seeds | Unchanged. The seed-runner test's check that the `users` table stays empty after seeding still passes, since the bootstrap Admin is created by setup, never by seeding. |

## 12. Test results

**163 tests, all passing**, counted by the test runner (JSON reporter), not
by hand. Before the UUID fix the suite was 161/161, twice in a row.

| Group | Tests |
|---|---|
| Carried over from Phases 1.1–1.3, assertions unchanged (Phase 1.3's 85, minus the 4 old router/smoke tests that asserted the removed placeholder) | 81 |
| New or rewritten in Phase 1.4 (including 6 router and 1 smoke) | 82 |
| **Total** | **163** |

New coverage, mapped to the required list:

| Requirement | Where |
|---|---|
| 1 First-run uninitialized | `local_auth_repository_test` (first run), `app_smoke_test`, `app_router_test` |
| 2 Admin setup | `local_auth_repository_test`, `auth_flow_test` (end to end in the UI) |
| 3 Setup cannot be repeated | Repository (twice, and when any user exists); router (`/setup` goes to login) |
| 4 / 5 Correct and incorrect PIN | Repository and `auth_flow_test` |
| 6 Verifier never exposes the raw PIN | `credential_hasher_test` (plain and base64); repository test scans every stored value and every `users` column |
| 7 / 8 Session creation and restoration | Repository (new instance = restart); `auth_flow_test` (app relaunch opens Home with no login) |
| 9 Logout | Repository and UI (logout, then relaunch, stays logged out) |
| 10 Invalid session | Corrupted value, deactivated user, nonexistent user |
| 11 Role resolution | One test per role; role refreshed from the `users` row |
| 12–14 Navigation per role | `role_navigation_test` (walks all 5 destinations and checks the More entries) |
| 15 Unauthorized route access | `auth_redirect_test` and `app_router_test` (direct `go()` to every protected route while uninitialized or logged out, and to setup after initialization) |
| 16 Unauthenticated redirect | Same as 15 |
| 17 Brute-force mitigation | `login_lockout_tracker_test` (9 tests, controllable clock); repository (lockout, per-user, reset); UI message |
| 18 Phase 1.3 regression | All 81 carried-over tests pass; files unchanged except the timeout below |

**Phase 1.2 test change (called out deliberately).** In the first full
run, `database_connection_test.dart` → *"the same file CANNOT be read back
with the wrong key"* hit the 30-second default timeout. Diagnosis:
- its code path is unchanged (empty diff);
- run alone it takes 0–5 s;
- in a worktree at the Phase 1.3 commit `a12227d`, it varied from 1 to 9 s;
- on this branch it once took 24 s run alone.

The test is I/O-bound (each encrypted open creates 28 tables on disk) and
its runtime varies with disk and antivirus activity. The new CPU-heavy
PBKDF2 tests running in parallel pushed one slow run past 30 s. **Fix:**
the two real-disk tests get an explicit 2-minute timeout. Assertions are
unchanged. If you prefer, the alternative is to revert that change and run
the suite with `--concurrency=1`.

Every PIN in the test suite is a synthetic value made up for the tests; no
real credential appears anywhere. They are deliberately not repeated in
this document.

## 13. `flutter analyze`

**No issues found.** One error came up along the way: `flutter_test`'s
`group()` has no `timeout:` parameter. It was fixed by moving the timeout
onto the tests.

## 14. APK build

`flutter build apk --debug` succeeds; rebuilt after the UUID fix.
`libsqlite3mc.so` is still bundled for arm64-v8a, armeabi-v7a, and x86_64.
`pointycastle` adds no native libraries.

## 15. Security / PII scan

Run on the staged diff of both code commits:
- phone-shaped literals (`[6-9][0-9]{9}`): **none**;
- API-key, secret, password-assignment, private-key, and cloud-key patterns:
  **none**;
- 6-digit literals added in `lib/`: **none**, so no hardcoded PIN;
- `print`, `debugPrint`, or `log` calls in `lib/`: **none** (the only
  matches were `audit_log` SQL index names);
- credential material in seed files: **none** (seed files untouched);
- `reference_materials/`, `*.g.dart`, `build/`: **not staged**.

## 16. Git status

Clean after the docs commit. Commits: `b797ac3` (implementation), `09f4b0b`
(UUIDv4 fix), `4fe2e06` (this report and the Master Plan update). History
was not rewritten and nothing was pushed.

## 17. Commit hashes

- `b797ac37380d0a0e8044cc75a6fc454282c0068b` — implementation
- `09f4b0b` — UUIDv4 fix
- `4fe2e06` — implementation report, final decisions, Master Plan update
- `b11abf2` — verification defect fixes (§20)

## 18. Remaining limitations and TBDs

1. **Only the Admin can log in on a real device in Phase 1.4.** There is no
   in-app way to create Medical Officer or Team Member accounts; that is
   user management, which is out of scope. Their navigation is verified by
   tests with directly provisioned users, but not reachable in the app yet.
2. **No PIN recovery.** If the sole Admin forgets the PIN, the only way out
   is clearing app data, which also discards the device-bound database key
   and so all local data. There is no business data yet, but this must be
   solved (for example with a second Admin or an Admin reset flow) before
   real data is entered.
3. **KDF cost is below OWASP's current figure** (210,000 vs 600,000) and
   **not benchmarked on target hardware.** This needs an on-device
   measurement before rollout; the count can be raised without a migration.
4. **No session expiry or inactivity re-lock.** docs/08 recommends PIN
   re-entry after inactivity on shared devices. The duration is a policy
   decision nobody has made, so it was not invented.
5. **The lockout is device-local** and resettable by anyone with root on the
   device.
6. **Deactivation does not propagate across devices.** That needs the
   unscheduled sync phase.
7. **No role-restricted routes exist yet.** The guard needs a role check
   when the first Admin-only screen is added.
8. **Real-device verification is still outstanding.** Everything was
   verified with `flutter test` and an APK build; no Android device or
   emulator is available in this environment (unchanged since Phase 1.1).
9. **Process note:** the docs/27 §0 decision record was written after the
   first domain/data files were drafted (the session was interrupted
   mid-implementation). It was in place before the dependency was added and
   before the screens, router, and tests were written. The decisions it
   records are exactly the approved ones.
10. **Defect found and fixed after the first commit:** the initial id
    generator produced `user-<hex>`, which is not a valid Postgres `uuid`
    (docs/04 §0). Fixed in `09f4b0b`, with tests.
11. **Observation on the Phase 1.3 report:** `seed_runner_test.dart`
    contains 17 tests; docs/26 §K listed 16. That report's total (85) is
    correct, so this is a per-file miscount only. docs/26 has been left as
    is, since Phase 1.3 is closed.

## 19. Phase 1.5 not started

Confirmed. Nothing for School/AWC Master, Micro Plan import, visits,
screening, referral management, treatment, OCR, camera, reports, PDF/Excel,
notifications, cloud sync, Supabase, user-management CRUD, or biometrics was
added. The five destinations are empty stubs.

## 20. Independent verification (2026-09-23): PASS WITH FIXES

A separate pass re-derived the claims above from the code, the running
tests, and external references instead of from this report.

**Defects found and fixed** (commit `b11abf2`; each regression test was
confirmed to fail on the previous code and pass on the fix):

| # | Defect | Fix |
|---|---|---|
| V1 | A stored verifier with an **empty key field accepted any PIN** (an empty expected key compared equal to an empty derivation). This contradicted the documented "malformed verifier fails closed". Triggering it needs write access to secure storage or a very specific corruption, but it was fail-open. | Keys that aren't exactly 32 bytes are rejected. |
| V2 | The lockout used the wall clock, so **moving the device clock back by 6 h left the user locked for 6 h 01 min**. This contradicted the documented 60-second cooldown and could lock out the sole Admin, for example when network time corrects a fast clock. | A lockout longer than one cooldown is re-anchored to end one cooldown from now. |
| V3 | `LocalAuthRepository`'s class doc comment was attached to a different declaration. | Moved back (comment only). |

**Results re-derived independently:**
- **PBKDF2.** Python's OpenSSL-backed `hashlib.pbkdf2_hmac` recomputes a
  real stored verifier exactly: HMAC-SHA256, 210,000 iterations, 16-byte
  salt, 32-byte key. Negative controls (209,999 iterations; SHA-1) do not
  match. Salts were unique across 4 derivations.
- **Off the UI thread.** While the KDF ran in the background, a 10 ms timer
  on the calling isolate fired 97 times; running the same KDF on the calling
  isolate (1.7 s) let it fire once. The UI isolate is genuinely free.
  `Isolate.run` starts one short-lived isolate per derivation and exits; no
  isolates persist.
- **PIN policy.** Every PIN containing a newline, space, sign, decimal point,
  full-width digits, Arabic-Indic digits, or the wrong length is rejected.
- **Lockout** persists across a simulated restart (a new repository
  instance), and no session is created while locked.
- **Schema.** The full `sqlite_master` dump plus `PRAGMA table_info(users)`
  is byte-identical (same SHA-256) to the Phase 1.3 baseline `a12227d`,
  built in a separate worktree: 28 tables, 44 indexes, no triggers or views,
  13 `users` columns, none credential-related. `schemaVersion` = 1.
- **Dependencies.** The only lockfile change is `pointycastle` 4.0.0
  (pure Dart). `collection` 1.19.1 and `convert` 3.1.2 are unchanged from
  the baseline, as are drift, drift_dev, sqlite3, flutter_secure_storage,
  go_router, and flutter_riverpod.
- **Tests.** **165/165 pass** by the test runner's JSON count (163 plus the 2
  regression tests). `flutter analyze` reports no issues.
- **APK.** Package `com.rbsk.referredline`, minSdk 26, targetSdk 36.
  Native libraries: `libsqlite3mc.so` and `libflutter.so` (3 ABIs), and
  `libdartjni.so` (3 ABIs), which comes from the `jni` package used by
  `path_provider_android` and was unchanged since the baseline.
  `libVkLayer_khronos_validation.so` (arm64) ships inside Flutter's own
  debug engine jar, so it's debug-build-only. The packaged Dart program
  contains no synthetic test PIN, no test-only code, and no verifier value.
- **Security scan (whole tree).** No secrets, tokens, private keys, or
  logging calls in `lib/`. Every 10-digit match is a School Code
  (UDISE-style `9370…`) from earlier, already-reviewed docs; none is a phone
  number. Test PIN values appear in no current doc and in no committed
  revision of any doc.
- **Real device.** Real-device verification was not performed because no
  Android device or emulator was available. Real-device KDF timing was not
  verified either.

**KDF iteration count: a decision for you, not a defect.** OWASP's Password
Storage Cheat Sheet (checked at verification) recommends 600,000 iterations
for PBKDF2-HMAC-SHA256. The implementation uses 210,000, which is 35% of
that. The approved decisions required "a slow KDF, not a fast hash" but did
not fix a number, so 210,000 is not a violation. However, its justification
(device performance) is **unmeasured**, because no device was available. It
needs either your explicit acceptance as a documented trade-off or a change
to 600,000, ideally after an on-device measurement. No migration is needed
either way.

**New observation, predating Phase 1.4:** `AndroidManifest.xml` sets no
backup rules, so Android's default auto-backup applies. Keystore keys are
device-bound and are not restored, so restoring backed-up secure-storage
values (the database key since Phase 1.2, and now PIN verifiers and
sessions) on another device cannot decrypt them. This is not a recovery
route, and the post-restore behavior is unverified. It needs a deliberate
backup policy; recorded in docs/00 §10.
