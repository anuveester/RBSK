# Phase 1.4 — Auth + RBAC Scaffolding + Navigation Shell (Implementation Plan)

**Status: IMPLEMENTED (commits `b797ac3`, `09f4b0b`), awaiting independent
verification. NOT closed.** Closure requires independent verification and
explicit user approval. Report:
[29_PHASE_1_4_REPORT.md](29_PHASE_1_4_REPORT.md). §1–§23 below are the
original plan; §0 records the final approved decisions, which supersede §7
and §19.

## 0. Final approved decisions (recorded at implementation approval)

These supersede the open questions in §7 and §19. Analysis behind them:
[28_AUTHENTICATION_ARCHITECTURE_DECISION.md](28_AUTHENTICATION_ARCHITECTURE_DECISION.md).

| # | Decision |
|---|---|
| 1 | Credential architecture: **Option A** (docs/28 §7). |
| 2 | Only a derived credential verifier is stored, in the existing Android Keystore-backed `SecureKeyStore`, keyed by `users.id`. |
| 3 | **No schema change.** No `users.pin_hash`, no `user_credentials` table, no credential column, no migration. `schemaVersion` stays 1; the 28 business tables are unchanged. |
| 4 | Authentication sits behind an `AuthRepository` abstraction, keeping the IDENTITY → CREDENTIAL → SESSION → RBAC → AUDIT separation (docs/28 §10) so the mechanism can be replaced by a future cloud identity provider. |
| 5 | Credential: **6-digit numeric PIN**. The raw PIN is never stored or logged, and never appears in source, seed files, test fixtures (synthetic test PINs only), documentation, Git, the database, or log output. |
| 6 | Derivation: a slow password-based KDF, not plain SHA-256 or any other fast hash. Selected after checking compatibility: **PBKDF2-HMAC-SHA256 via `pointycastle`**. Parameters, salt handling, and verifier format are in §0.1. |
| 7 | Bootstrap: **first-run Admin setup**. No seeded or default Admin PIN, no Admin credential in source or seed data, never logged. Once any user exists, setup cannot run again. |
| 8 | No cloud authentication and no credential synchronization. Nothing assumes verifiers sync between devices. Future cloud identity stays replaceable/TBD. |
| 9 | No biometrics in Phase 1.4. |
| 10 | `schemaVersion` = 1, 28 business tables, no migration. |

Answers to §19's remaining questions, decided at implementation time:
- **Q3 (bootstrap user ↔ `staff` row):** the bootstrap Admin is a `users` row
  with `staff_id = NULL`, which the frozen schema allows. No `staff` row is
  created or modified.
- **Q4 (`devices` row):** deferred, as recommended. No `devices` row is
  written in Phase 1.4.

### 0.1 Credential derivation: exact mechanism

| | |
|---|---|
| Algorithm | PBKDF2 with HMAC-SHA256 (`pointycastle`'s `PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))`) |
| Iterations | **210,000** (see rationale below) |
| Salt | 16 random bytes (128-bit) per credential from `Random.secure()`. The salt is unique per credential and **not secret**: it is stored inside the verifier string. |
| Derived key | 32 bytes (256-bit) |
| Verifier format | `pbkdf2-hmac-sha256$<iterations>$<base64 salt>$<base64 derived key>` |
| Comparison | Constant-time byte comparison |
| Storage key | `rbsk_credential_verifier_<users.id>` in `SecureKeyStore` |

**Why `pointycastle`:** checked on pub.dev at implementation time. It is pure
Dart, so it adds no second native build step (the project already carries
one, `sqlite3mc`). It is widely used (about 3.66M downloads, 415 likes) and
provides PBKDF2 as a standard, documented derivator. The `bcrypt` package
was also considered but has far less usage (about 50k downloads). Argon2 was
not chosen because the maintained Dart options rely on native bindings,
which would repeat the native-build fragility the project already hit with
`sqlcipher_flutter_libs`.

**Why 210,000 iterations, not OWASP's current 600,000:** OWASP's Password
Storage Cheat Sheet (2023) recommends 600,000 iterations for
PBKDF2-HMAC-SHA256. This implementation deliberately uses 210,000 because
derivation runs as pure Dart (not hardware-accelerated native code) on
Android devices as old as `minSdk 26`, and staff log in many times per field
day. **This is a trade-off, not full compliance with the current OWASP
figure.** The iteration count is embedded in each verifier, so it can be
raised later without invalidating existing verifiers. **The value has not
been benchmarked on real RBSK field hardware in this environment**;
on-device benchmarking before rollout is recommended.

### 0.2 Login identity selection

The Login screen lists active users and asks the user to pick their own
name, then enter their PIN. docs/02 says "username/email + password (or
PIN)"; a picker was chosen instead because `users.email` is nullable (no
guaranteed typed identifier exists) and this is a known team of about 8–10
people on shared devices. The user list is not secret within the team, so
showing it does not weaken the PIN.

### 0.3 Brute-force mitigation: exact behavior

- 5 consecutive incorrect PINs for one user locks that user out for 60 seconds.
- An attempt made during the lockout is rejected without checking the PIN,
  and does not extend the lockout.
- A successful login resets the counter.
- The counter is stored per user in `SecureKeyStore`, not in the database.
- **There is no permanent lockout.** The expiring cooldown is the recovery
  path, so the only Admin can never be locked out for good.
- **Limitation:** there is no "forgot PIN" flow in Phase 1.4. Resetting a PIN
  needs a second authenticated Admin and a user-management screen, which
  belong to the later Admin-tools phase. If the only Admin forgets their PIN,
  the Phase 1.4 build has no in-app recovery. Recovering would mean clearing
  app data, which also loses the device-bound database key and therefore the
  local data. This limitation is recorded rather than covered with a weak
  bypass.
- A corrupted lockout entry is treated as "not locked" rather than
  crashing login. The corrupted and unlocked outcomes are equivalent here,
  because anyone able to write to the Keystore-backed store could clear the
  entry anyway.
- The lockout counter is device-local. Someone with root access to the
  device could reset it. The lockout protects against guessing through the
  app's UI; resistance to an extracted verifier comes from the KDF.

Scope reference: [21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md) §10, step 1.4
("Auth + RBAC scaffolding (3 roles), secure token storage, role-gated navigation
shell" — exit criterion: *"Each role sees the correct navigation"*).

## Inspection performed before writing this plan

1. Read [00_PROJECT_MASTER_PLAN.md](00_PROJECT_MASTER_PLAN.md) in full (post
   Phase 1.3 closure, commit `a12227d`).
2. Re-read the Phase 0.6 freeze (§10), Phase 1.1–1.3 reports, and
   [02_SCREEN_MAP.md](02_SCREEN_MAP.md)'s Auth/navigation-shell sections and
   [08_SECURITY_ARCHITECTURE.md](08_SECURITY_ARCHITECTURE.md)'s Authentication
   section — not from memory, re-opened this turn.
3. Enumerated the current `lib/` and `test/` trees directly. Confirmed:
   `lib/features/` contains only `home/` (the Phase 1.1 placeholder);
   `lib/domain/usecases/` is still empty; no `auth` anything exists anywhere.
4. Read the frozen `users` and `devices` table definitions directly from
   `lib/data/local/tables/reference_identity_tables.dart` (not from
   documentation summaries) — see the finding in §7.
5. Confirmed git state: clean, `HEAD` at `a12227d`, Phase 1.3 formally closed.

## 1. Phase objective

Give the app a real navigation structure and an access-control gate in front
of it — so that from Phase 1.5 onward, every new feature screen has
somewhere to live and is already visible only to the roles the RBAC matrix
says should see it. This phase does not build any feature; it builds the
frame the features go into.

## 2. Why this phase comes next

It's next in the already-approved sequence (docs/21 §10), and it's a real
dependency for what follows: Phase 1.5 (School/AWC Master CRUD) needs a
place in the navigation to live and needs to know who's allowed to edit
masters vs. only view them (per the RBAC matrix, `TEAM_MEMBER` is
view/search-only on `schools`/`awcs`). Building the shell now, once, is
cheaper than retrofitting role-gating onto five already-built feature areas
later.

## 3. Exact scope

1. **Login screen** — credential entry, no self-signup (matches
   [02_SCREEN_MAP.md](02_SCREEN_MAP.md) Auth §1).
2. **A local session mechanism** — see §7, this is the phase's one open
   architectural decision.
3. **Role-gated navigation shell** — the 5-destination bottom navigation
   (Home · Visits · Referrals · Reports · More) from
   [02_SCREEN_MAP.md](02_SCREEN_MAP.md), wired with `go_router`, with `More`'s
   contents varying by role (Admin-only entries — backup export, audit log —
   hidden from non-admins).
4. **Route guarding** — every route except `/login` requires an active
   session; an unauthenticated user is redirected to `/login`.
5. **RBAC read model** — a small, testable way to ask "can the current user
   do X", derived from the frozen matrix
   ([04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §3), for the
   navigation layer to consume. Not a full permission-enforcement framework —
   just enough for "should this nav item be visible."
6. **One bootstrap ADMIN user** — see §7. `users` is currently empty (Phase
   1.3 deliberately excluded it); something has to make the first login
   possible.

## 4. Explicit out-of-scope items

Per your instruction §4, named explicitly so none of these get pulled
forward "for convenience":

| Feature | Where it actually belongs |
|---|---|
| School/AWC Master screens | Phase 1.5 |
| Micro Plan import | Phase 1.6 |
| Visit planning screens | Phase 1.7 |
| School screening workflow | Phase 1.8 |
| Register photo capture / camera | Phase 1.9 |
| OCR | not yet scheduled |
| Disease/Referred Line List | Phase 1.10 |
| AWC screening workflow | not yet scheduled |
| Cloud synchronization | not yet scheduled |
| Reporting / PDF / Excel | not yet scheduled |
| Treatment/follow-up UI | not yet scheduled |
| Dashboards, analytics, notifications | never scoped anywhere in this project |
| Full User Management (create/edit/deactivate accounts) screen | not yet scheduled — the original Phase 0 draft placed this in a later "Admin Tools" bucket ([13_IMPLEMENTATION_PHASES.md](13_IMPLEMENTATION_PHASES.md) Phase 7); Phase 1.4 needs only the one bootstrap account (§7), not a management UI |

The Home, Visits, Referrals, Reports, and More *destinations* are created as
navigation targets with minimal placeholder content (in the same spirit as
the existing `HomePlaceholderScreen`) — their real content is each later
phase's job, not this one's.

## 5. Current architecture dependencies

- `AppDatabase` / `appDatabaseProvider` (Phase 1.2) — the `users` table this
  phase reads from already exists and is already reachable through the
  centralized provider; no new database access pattern is needed.
- `DriftStaffRepository` pattern (Phase 1.3) — the repository/entity
  structure this phase's `UserRepository` should follow already exists as a
  proven, tested pattern.
- `SecureKeyStore` abstraction (Phase 1.2,
  `lib/data/local/database_connection.dart`) — already provides exactly the
  "store one secret, testable without a platform channel" shape this phase
  needs for session storage. Reusing it (or a sibling instance of it) avoids
  inventing a second secure-storage abstraction.
- `Failure` sealed class (Phase 1.1, `lib/core/errors/failure.dart`) — the
  natural place to add `InvalidCredentialsFailure` etc.
- `go_router` (Phase 1.1) — already the routing package; this phase uses its
  existing redirect/shell-route features, not a new package.

## 6. Database impact

**Reads/writes existing tables only — `users`, `staff`, `devices`.** No new
table.

- One bootstrap `users` row (+ matching `staff` row if desired) inserted the
  same idempotent way Phase 1.3 seeds reference data — see §7.
- `users.last_login_at` updated on successful login (already a frozen,
  nullable column — no schema change to use it).
- `devices` — optionally, one row per install to satisfy the frozen
  `devices` table's evident purpose (docs/04 §2.1: `user_id`, `device_label`,
  `platform`, `app_version`, `last_sync_at`). Not required for the navigation
  shell to work; flagged as optional in §16, not core scope.

## 7. Schema/migration impact — the phase's one real open question

**No schema change is required for the recommended approach below — but a
genuine alternative exists that WOULD require one, and I have not chosen
between them.** Per your instruction ("if genuine ambiguity, document it
clearly rather than guess"), both are laid out here rather than one being
silently picked.

**The finding:** the frozen `users` table
(`lib/data/local/tables/reference_identity_tables.dart`, re-read this turn)
has **no password/PIN/credential column of any kind** — only
`id, staff_id, email, phone, display_name, role, is_active, last_login_at`
plus audit fields. This isn't an oversight: `docs/08_SECURITY_ARCHITECTURE.md`
designed authentication around **Supabase Auth**, an external cloud service
that owns credential storage entirely (its own `auth.users`, not our local
table). Our local `users` table was always meant as a profile/role mirror,
never a credential store.

But Supabase integration is not part of this project yet — `supabase_flutter`
isn't a dependency, no cloud project is configured, and cloud sync has **no
phase number assigned** anywhere in the roadmap (docs/00 §4/§5). Building
real Supabase Auth in Phase 1.4 would mean adding a new dependency (forbidden
this planning turn, and arguably premature — see the still-open data
residency question, docs/00 §10 item 6, which bears directly on where
Supabase-hosted auth data would live) and reaching into a phase of work that
doesn't exist yet.

**Option A — local-only credential, no schema change (recommended):**
Store a hashed PIN per user in secure storage (via the existing
`SecureKeyStore` abstraction, keyed by `users.id`), verified entirely
on-device. No DB column, no migration. `users.last_login_at` (already
frozen) is the only row this touches. This is consistent with the
"offline-first, every field workflow works with no network" principle and
costs nothing architecturally now — it can be superseded later when a real
cloud-auth phase is scheduled, without this phase's work being wasted (the
navigation shell, route guards, and RBAC read model are identical either
way; only the credential-check implementation changes).

**Option B — add a credential column/table (schema change):** e.g.
`users.pin_hash text` or a separate `user_credentials` table. This is a
**SCHEMA CHANGE REQUIRING APPROVAL** per the standing Phase 0.6 rule
(approval condition 9) and is explicitly **not** authorized by this planning
document. If you prefer this path, it needs its own approval step before
any implementation, the same as any other schema amendment.

**Option C — defer real login entirely:** ship only the navigation shell and
RBAC visibility logic behind a non-authenticating "choose a role for
now" dev switch, with real login deferred to whenever cloud auth is
scheduled. This satisfies "role-gated navigation shell" but not "secure
token storage" from the frozen one-liner, so it under-delivers against the
approved scope rather than reinterpreting it — flagged as the least
faithful option, not recommended.

**This plan proceeds on Option A as the default for the acceptance criteria
below, but does not consider it silently approved — please confirm before
implementation starts.**

## 8. Domain/entity impact

New, additive only (mirrors the Phase 1.3 pattern exactly):

- `lib/domain/entities/app_user.dart` — plain read-model for a logged-in
  user (`id`, `displayName`, `role`, `email`). No credential material ever
  enters this type.
- `lib/domain/entities/auth_session.dart` — `userId`, `role`,
  `loggedInAt`. Represents "what's remembered locally between app launches,"
  not a cloud JWT (there is no cloud yet — naming it a "token" would
  overclaim what it is).
- `lib/domain/repositories/user_repository.dart` — abstract interface,
  read-only (`getById`, `getByEmail`) — mirrors
  `domain/repositories/staff_repository.dart`'s shape.
- `lib/domain/repositories/auth_repository.dart` — abstract interface:
  `login(...)`, `logout()`, `currentSession()`.

## 9. Repository/data-layer impact

- `lib/data/repositories/drift_user_repository.dart` — Drift-backed,
  read-only, same shape as `DriftStaffRepository`.
- `lib/data/repositories/local_auth_repository.dart` — implements credential
  verification per §7 Option A, backed by `SecureKeyStore` +
  `DriftUserRepository`. Session persistence also goes through
  `SecureKeyStore` (a new key, e.g. `rbsk_active_session_v1`, distinct from
  the DB encryption key already stored there).
- `lib/data/local/seed/bootstrap_user_seed_data.dart` +
  a `seedBootstrapAdmin()` step in `SeedRunner`, or a small sibling runner —
  idempotent (`insertOrIgnore`) the same way every Phase 1.3 seed is. Exact
  bootstrap credential handling needs your input (§16 Q1) — it must not be a
  hardcoded plaintext password committed to source.

## 10. UI impact

Yes — explicitly in scope per the frozen one-liner ("role-gated navigation
shell"), and your instruction permits UI here because the roadmap
establishes it. New:

- `lib/features/auth/presentation/screens/login_screen.dart`
- `lib/features/auth/presentation/controllers/` — Riverpod session state
- `lib/core/router/` — extended with `ShellRoute`/`StatefulShellRoute` for
  the 5-tab shell, a `/login` route, and `redirect` logic enforcing the
  session gate
- Five minimal destination screens (`lib/features/home/`,
  `visits/`, `referrals/`, `reports/`, `more/`) — placeholder-depth only,
  matching `HomePlaceholderScreen`'s existing style, **not** the real
  feature screens those folders will eventually hold
- `More` screen renders its item list from the RBAC read model (§3.5), so
  Admin-only entries are simply absent from a non-admin's list, not
  disabled-and-visible

`HomePlaceholderScreen` and the current `/` root route are restructured into
one of the 5 shell tabs, not left standing alongside it.

## 11. Dependency/package impact

**None anticipated.** Everything needed (`flutter_riverpod`, `go_router`,
`flutter_secure_storage`, `drift`) is already a dependency as of Phase 1.2.
If Option A (§7) needs a password-hashing primitive, `dart:crypto`'s
constituent (`crypto` package) is the standard, minimal choice — **flagged
as a possible small addition needing its own approval at implementation
time**, not assumed here. (Home-rolled hashing is not an acceptable
alternative — if a hashing package is needed, it should be a real,
maintained one, not invented.)

## 12. Security/privacy considerations

- No plaintext credential ever stored — hashed, and only in
  `flutter_secure_storage` (Android Keystore-backed), never in the SQLite
  database, never logged.
- Session data in secure storage contains no health information — just
  `userId`/`role`/timestamp.
- Route guarding is a UX convenience, not the security boundary — real data
  access control is enforced at the repository/RLS layer in later phases
  (unchanged principle from docs/08; this phase doesn't weaken or duplicate
  that guarantee, it just fronts the UI with it).
- The bootstrap admin credential (§9) must never be a hardcoded, committed
  plaintext value — needs an explicit, safe provisioning approach, decided
  before implementation (§16 Q1).
- No child, parent, or patient data is touched anywhere in this phase.

## 13. Offline-first considerations

- Login and session checks work with zero network access — consistent with
  every prior phase and the project's core principle (Option A is offline by
  construction; Option B/C would be too, but only Option A avoids a schema
  change).
- The session persists across app restarts (read from secure storage on
  launch) without needing connectivity.
- Nothing in this phase introduces a network call.

## 14. Source-material dependencies

None. This phase is pure architecture/scaffolding — it doesn't touch the
Micro Plan, Job Aid, or register material.

## 15. Required tests

| Area | What's tested |
|---|---|
| RBAC read model | Given a role, the correct set of nav/`More` entries is returned; Admin-only entries absent for non-admin roles |
| Route guard | Unauthenticated access to a protected route redirects to `/login`; authenticated access does not |
| `LocalAuthRepository` | Correct credential → session created; wrong credential → `InvalidCredentialsFailure`, no session; session persists via a fake `SecureKeyStore` (same test pattern as `DatabaseKeyManager` tests, Phase 1.2) |
| `DriftUserRepository` | Reads back the bootstrap user correctly |
| Seed idempotency | Re-running the bootstrap seed doesn't duplicate the user row (same pattern as Phase 1.3) |
| Widget: login screen | Renders, accepts input, shows an error on failed login, navigates to the shell on success |
| Widget: shell | Renders the correct 5 destinations; `More` content varies by injected role |
| Regression | Full existing suite (85 tests as of Phase 1.3) still passes |

## 16. Acceptance criteria

1. A user can log in with the bootstrap credential and reach the navigation
   shell.
2. An invalid credential is rejected with a clear error, no session created.
3. Each of the 3 roles sees the correct navigation — the frozen exit
   criterion, verified by test, not just visual inspection.
4. Restarting the app keeps the session (no re-login required) until an
   explicit logout.
5. Logout clears the session and returns to `/login`.
6. `flutter analyze` — zero issues. `flutter test` — 100% pass including all
   regression tests. `flutter build apk --debug` — succeeds.
7. `schemaVersion` unchanged at 1 (if Option A is used, as recommended); no
   migration added.
8. No credential material appears in source, logs, or Git history.

## 17. Definition of Done

Matches the bar every prior phase was held to: implementation complete,
independently verifiable (not just "should work"), all quality gates in §16
actually run and passing, documentation (this plan → a report →
Master Plan update) current with what was actually built, and formally
approved by you before being marked closed — Claude does not declare a
phase done unilaterally.

## 18. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Option A becomes throwaway work if cloud auth arrives sooner than expected | Rework of the credential-check implementation only | Navigation shell, route guards, RBAC read model, and session *shape* are designed to be credential-mechanism-agnostic — only `LocalAuthRepository`'s internals would be replaced |
| Bootstrap credential handled carelessly | Could become a real security hole (a hardcoded/known password) | Explicitly flagged as needing a safe provisioning decision (§16 Q1) before implementation, not assumed |
| "Role-gated navigation" scope creeps into building real destination screens | Phase boundary violation, duplicate work when Phase 1.5+ builds the real thing | §4's explicit out-of-scope table; destination screens stay placeholder-depth |
| `crypto` package need (§11) discovered only during implementation | Minor — a small, standard, easily-justified dependency, but still needs approval per this project's dependency discipline | Flagged now rather than added silently later |

## 19. Open questions/TBDs

1. **Credential mechanism — confirm Option A, B, or C (§7).** This is the
   one decision that actually changes what gets built.
2. **Bootstrap admin provisioning** — how is the first credential set
   safely? Candidates: prompt for a PIN on first launch if no user exists
   yet (no credential ever committed to source); or a documented manual
   step. Needs your preference before implementation.
3. Does the bootstrap user need a matching `staff` row, or is a `users` row
   with `staff_id = NULL` acceptable for this phase (the schema already
   allows it)? Low-stakes, but worth confirming.
4. Is a `devices` row required this phase, or genuinely deferred to the sync
   phase where it's actually used? Recommend deferring — flagged, not
   decided.

## 20. Files expected to be created/modified

**Created:**
```
lib/domain/entities/app_user.dart
lib/domain/entities/auth_session.dart
lib/domain/repositories/user_repository.dart
lib/domain/repositories/auth_repository.dart
lib/data/repositories/drift_user_repository.dart
lib/data/repositories/local_auth_repository.dart
lib/data/local/seed/bootstrap_user_seed_data.dart
lib/features/auth/presentation/screens/login_screen.dart
lib/features/auth/presentation/controllers/auth_controller.dart (or similar)
lib/features/home/presentation/screens/home_screen.dart (replaces the Phase 1.1 placeholder within the new shell)
lib/features/visits/presentation/screens/visits_placeholder_screen.dart
lib/features/referrals/presentation/screens/referrals_placeholder_screen.dart
lib/features/reports/presentation/screens/reports_placeholder_screen.dart
lib/features/more/presentation/screens/more_screen.dart
lib/core/rbac/ (or similar) — the RBAC read model
test/... (mirroring the above, per §15)
```

**Modified:**
```
lib/core/router/app_router.dart      — shell routes, /login, redirect logic
lib/core/router/routes.dart          — new route constants
lib/app.dart                          — router wiring only, if needed
lib/data/local/seed/seed_runner.dart — add the bootstrap-user step
lib/core/errors/failure.dart         — add auth-specific Failure subtypes
```

**Removed:** `lib/features/home/presentation/screens/home_placeholder_screen.dart`
and its test, once folded into the real shell — a rename/replace, not a
scope addition.

## 21. Expected Git/change boundary

Same two/three-commit pattern as every prior phase: implementation commit,
then a report + Master Plan update commit (and a formal-closure commit after
your approval, as happened for Phase 1.3). Nothing outside `lib/`, `test/`,
and the phase's own `docs/` entries.

## 22. Rollback considerations

- Additive except for the router/seed-runner modifications and the
  placeholder-screen removal (§20) — both are small, mechanical, and easily
  reverted via `git revert` if needed.
- Because Option A stores credentials only in `flutter_secure_storage` (not
  the synced/backed-up SQLite database), rolling back this phase's code
  cleanly removes all trace of the mechanism without a data-migration
  concern.
- No schema change (under Option A) means no migration to roll back either.

## 23. Phase boundary — what must NOT happen

- No School/AWC Master, Micro Plan import, visit planning, screening,
  register photo/camera, OCR, cloud sync, reporting, PDF/Excel, or
  treatment/follow-up code.
- No Supabase/cloud dependency added without a separate, explicit approval.
- No schema change/migration without a separate, explicit approval (Option
  B, if ever chosen, is that separate approval).
- No hardcoded credential of any kind committed to source.
- Phase 1.4 is not marked complete or closed by Claude — only by your
  explicit approval, following the same pattern as Phases 1.1–1.3.
