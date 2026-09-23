# Authentication Architecture Decision

> **Decision outcome (2026-09-23):** Option A was approved together with the
> recommendations in §17: an `AuthRepository` abstraction, a slow KDF, a
> 6-digit PIN, and first-run Admin setup. The final decisions and exact
> parameters are recorded in [27_PHASE_1_4_PLAN.md](27_PHASE_1_4_PLAN.md) §0.
> The approval came separately; the analysis below is unchanged from when it
> was written.

**Status: ANALYSIS ONLY. This document does not authorize implementation.**
No code, dependency, schema, or migration change was made while producing it.
Phase 1.4 remains PLANNED, NOT APPROVED (see
[00_PROJECT_MASTER_PLAN.md](00_PROJECT_MASTER_PLAN.md) §0). Full options were
first identified in [27_PHASE_1_4_PLAN.md](27_PHASE_1_4_PLAN.md) §7/§19; this
document is the dedicated deep analysis those sections called for, not a
replacement for the plan.

## Inspection performed before writing this analysis

Re-read directly from the repository this turn (not from prior summaries):
[00_PROJECT_MASTER_PLAN.md](00_PROJECT_MASTER_PLAN.md),
[27_PHASE_1_4_PLAN.md](27_PHASE_1_4_PLAN.md),
[02_SCREEN_MAP.md](02_SCREEN_MAP.md),
[04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md),
[08_SECURITY_ARCHITECTURE.md](08_SECURITY_ARCHITECTURE.md),
[21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md),
[24_PHASE_1_2_REPORT.md](24_PHASE_1_2_REPORT.md),
[26_PHASE_1_3_REPORT.md](26_PHASE_1_3_REPORT.md); the actual
`lib/data/local/tables/reference_identity_tables.dart` (`Users`/`Devices`
table definitions), `lib/data/local/enums.dart` (`AppRole`),
`lib/data/local/database_connection.dart` (`SecureKeyStore`,
`DatabaseKeyManager`, `openEncryptedDatabase`), `lib/core/router/app_router.dart`
(current routing — a single unguarded route today), `lib/core/errors/failure.dart`
(the `Failure` sealed base), the current `lib/` tree (confirmed
`lib/domain/usecases/` and `lib/data/remote/` are still empty — no auth code
of any kind exists), and `git log --oneline --all` (confirmed HEAD at `30d89f5`,
Phase 1.3 formally closed at `a12227d`).

## 1. Context

Phase 1.4 planning (docs/27) found that the frozen `users` table has no
credential column. This is not an oversight in the frozen schema — it is a
direct consequence of how [08_SECURITY_ARCHITECTURE.md](08_SECURITY_ARCHITECTURE.md)
originally designed authentication: around **Supabase Auth**, an external
service that owns credentials entirely in its own `auth.users` table. The
local `users` table (docs/04 §2.1) was designed as a **profile/role mirror**
— `staff_id`, `email`, `phone`, `display_name`, `role`, `is_active`,
`last_login_at` — never as a credential store. That original design is
internally consistent; the problem is that Supabase integration has **no
phase number anywhere in the roadmap** (docs/00 §4/§5), and Phase 1.4 must
ship a working, offline login now. This document analyzes how to do that
without contradicting the frozen schema or the original security design.

## 2. Current architecture (as verified this turn)

- `Users` table columns, read directly from
  [reference_identity_tables.dart](../lib/data/local/tables/reference_identity_tables.dart):
  `id, staffId (nullable FK→staff), email (nullable, unique), phone (nullable),
  displayName, role (AppRole enum), isActive (default true), lastLoginAt
  (nullable)`, plus the standard audit columns (`createdBy/At`,
  `updatedBy/At`, `rowVersion`). **No credential column of any kind.**
- `Devices` table: `id, userId (FK→users), deviceLabel, platform, appVersion,
  lastSyncAt, createdAt`. One row per install, by evident design — not
  currently used for any cryptographic device-binding.
- `AppRole` enum (`lib/data/local/enums.dart`): `ADMIN, MEDICAL_OFFICER,
  TEAM_MEMBER` — exactly the three roles docs/04 §3's RBAC matrix defines.
- `SecureKeyStore` (`lib/data/local/database_connection.dart`): a small,
  already-proven abstraction (`read(key)`/`write(key, value)`) over
  `flutter_secure_storage` (Android Keystore-backed). Currently used for
  exactly one secret — the database encryption passphrase, under a single
  fixed storage key (`rbsk_db_encryption_key_v1`). It is a generic
  persistent key-value store, **not** a multi-user or multi-tenant
  mechanism by itself — see §3 Option A for what that implies.
- Routing (`lib/core/router/app_router.dart`): currently **one** route
  (`Routes.home` → `HomePlaceholderScreen`), no shell route, no redirect
  logic, no session gate of any kind. This is a fully open field, not a
  system that needs retrofitting.
- `Failure` (`lib/core/errors/failure.dart`): a minimal sealed base
  (`UnexpectedFailure` is the only subtype) — ready to grow
  auth-specific subtypes, nothing auth-specific exists yet.
- `docs/08_SECURITY_ARCHITECTURE.md`'s own words on the intended shape
  (quoted, not paraphrased): *"Supabase Auth... Local session tokens stored
  via `flutter_secure_storage`... Recommend an app-level PIN or biometric
  re-entry after inactivity... a UX-light control (device already
  authenticated once) layered on top of the Supabase session, not a second
  full login."* This matters directly for §11 below: the original design
  already describes **two tiers** — a real credential authority (Supabase),
  and a fast local re-entry convenience on top of it. Today, only the second
  tier's mechanism (local, secure-storage-backed) exists in any form; the
  first tier (a real external credential authority) does not exist yet.
- `docs/02_SCREEN_MAP.md` Auth §1 (quoted): *"Login — username/email +
  password (or PIN after first login). No self-signup."* This already
  anticipated a two-credential-weight scheme: something heavier at first
  login, something lighter (a PIN) afterward — relevant to §7.
- No `crypto`, `bcrypt`, `argon2`, or any hashing package is a dependency
  today. No `supabase_flutter` dependency exists. No cloud project is
  configured anywhere in this repository.

## 3. Problem statement

Phase 1.4 needs a way to verify "is this person who they claim to be"
entirely offline, for ~8–10 named users, using only what the frozen schema
and current dependencies already provide — or, if that is genuinely
insufficient, an explicit, separately-approved schema amendment. The
question is not "should there be authentication" (the frozen roadmap already
requires it, docs/21 §10 step 1.4) — it's **where credential material
should live**, given that its originally-intended owner (Supabase Auth)
isn't part of this project yet.

## 4. Requirements

Derived from the frozen roadmap exit criterion (*"Each role sees the correct
navigation"*, docs/21 §10), docs/02's Auth screens, and docs/08's Authentication
section — not invented for this document:

1. Offline login for ~8–10 named users, three roles.
2. No self-signup — accounts are provisioned by an ADMIN (docs/08).
3. Session persists across app restarts without network access.
4. Route guarding so unauthenticated access redirects to `/login`.
5. Audit identity (`created_by`/`updated_by` = a real `users.id`) is
   unaffected by whichever credential mechanism is chosen.
6. No plaintext credential ever stored, logged, or committed.
7. Whatever is built must not become wasted work if/when a real cloud
   identity provider (Supabase or otherwise) is eventually integrated.

## 5. Security requirements

- Credential material must be hashed, never stored or compared in plaintext.
- Hashing must use a deliberately slow/memory-hard primitive appropriate to
  low-entropy input (see §7) — not a fast general-purpose hash used alone.
- Storage must be Android Keystore-backed (`flutter_secure_storage`, the
  existing `SecureKeyStore` abstraction), never SharedPreferences, never a
  plain file, and — under the recommended option — never the SQLite database.
- Failed-attempt lockout/rate-limiting is a local, implementable control
  regardless of which option is chosen (see §6) and should be treated as a
  requirement, not a nice-to-have, precisely because this is a fully
  offline, no-server-side-throttling design.
- No credential material may appear in `git log`, seed data, or source at
  any point — stronger than "not in the final commit": it must never be
  staged even transiently.

## 6. Offline requirements

- Login, session check, and session restoration must work with zero network
  access — true of every option analyzed below; none of A/B/C introduce a
  network call.
- A newly added user becomes able to log in only once their device has the
  corresponding local state (a `users` row **and**, under Option A, a
  locally-established credential hash for that specific device — see §12).
  There is no cloud to push a new user's credential to other devices yet;
  this is a genuine limitation of every offline-only option, not specific
  to one of them.
- A user disabled while a device is offline: `users.is_active = false` set
  on one device does not propagate to any other device or to that user's
  own second device until a future sync mechanism exists. This is
  explicitly **not decidable now** — it depends on the unscheduled sync
  phase's conflict-resolution design (docs/07) — and must remain TBD (§17).
- Two devices with divergent user state (one shows a user active, another
  shows them deactivated) is an expected, acceptable transient state for an
  offline-first app with no sync yet; reconciling it is future-sync's job,
  not something Phase 1.4 can or should solve.

## 7. Option A — local-only credential, no schema change

**Mechanism:** a hashed PIN (or password) per user, stored in the existing
`SecureKeyStore` (Android Keystore-backed), keyed by `users.id` (e.g.
`rbsk_credential_hash_<userId>`), verified entirely on-device against a
freshly-hashed login attempt.

| Dimension | Analysis |
|---|---|
| Security properties | Depends entirely on (a) using a slow/memory-hard hash — see §9 — and (b) Android Keystore's hardware-backed protection where the device supports it. A weak hash choice would undermine this option regardless of where the hash is stored; storage location alone is not a security guarantee. |
| Offline authentication | Native fit — no network call anywhere in the path. |
| Multi-user support | Achieved purely by keying each stored hash with `users.id`, the same pattern already used for the single DB-encryption-key entry. `SecureKeyStore` itself has no concept of "users" — it is a flat key-value store; multi-user separation is an application-level convention, not a platform guarantee. Since Android typically runs one OS-level app-user regardless of which of the 8–10 staff is physically holding a shared device, **every stored hash is readable by whichever human is holding the device** at the storage-API level — this is normal (it's how the app decides who's logging in) and is not a weakness distinct from any local-auth design. |
| Backup/restore | **Real limitation, stated plainly:** Android Keystore-backed secrets are device-tied and are **not** included in an encrypted database export (docs/04 §6). If the SQLite DB is backed up and restored onto a new device, the `users` rows survive but every credential hash under Option A does **not** — every user would need to re-establish a credential on the restored install. This exactly mirrors the existing, already-shipped behavior of the DB encryption passphrase itself (also `SecureKeyStore`-backed, also lost on reinstall, per docs/24 §C) — a real cost, but not a new category of cost this project hasn't already accepted once. |
| Device migration | Same as backup/restore: a credential hash never migrates automatically; each device needs its own locally-established hash per user. |
| Credential reset | Fully local: an ADMIN-mediated reset simply overwrites that user's stored hash entry — no network, no external provider. |
| Admin user management | The one bootstrap ADMIN (§10) plus any future "create user" flow both stay entirely local; no dependency on an external identity provider. |
| Future cloud sync | Does not block it. `users.id` (UUID) is already designed (docs/04 §0) to be the same identifier a future cloud `auth.users` row would key against. The credential hash itself is local-only and — per docs/08's own stated design intent — should never be assumed to sync (see §12). |
| Audit identity | Unaffected — `created_by`/`updated_by` already reference `users.id`, never anything credential-related. |
| Account deletion/deactivation | `users.is_active` already exists and is orthogonal to Option A; deactivation is checked at login time in addition to the credential match, an implementation detail, not a schema concern. |
| Reinstall behavior | Every locally-stored hash is lost (see Backup/restore); users must re-establish credentials. Data rows are unaffected if the DB itself was separately restored. |
| Multiple Android devices | Each device needs its own independently-established hash per user — there is no automatic cross-device recognition without a cloud layer that doesn't exist yet. |
| Encrypted database interaction | None — this is the option's defining property. The credential hash never enters the SQLite file, so it is outside the scope of the DB encryption mechanism entirely (a second, independent protection boundary, not a substitute for it). |
| Feasibility with current architecture | High — reuses `SecureKeyStore` exactly as already proven in Phase 1.2, no new abstraction invented. |
| Complexity | Low — one new repository (`LocalAuthRepository`), no migration, no new table. |
| Long-term maintainability | Good, **conditional on** implementing the credential-verification logic behind a swappable interface (`AuthRepository`) from the start — see §11 — so replacing the mechanism later doesn't require touching session/RBAC/audit code. |

## 8. Option B — credential column/table (schema change)

**Mechanism:** e.g. `users.pin_hash text`, or a separate `user_credentials`
table (`user_id`, `credential_hash`, `algorithm`, `updated_at`).

| Dimension | Analysis |
|---|---|
| Security properties | Equivalent to Option A **if** the same slow/memory-hard hashing is used — the storage location (Keystore vs. encrypted SQLite) is not itself a security downgrade or upgrade, since the SQLite file is already encrypted at rest (Phase 1.2, verified). The meaningful difference is architectural, not cryptographic. |
| Offline authentication | Also native — no network call either way. |
| Encrypted DB protection | The hash would inherit the same at-rest encryption as every other business row — a genuine, real protection, contingent entirely on the DB encryption key itself staying safe (which is, itself, `SecureKeyStore`-protected — so Option B doesn't remove dependence on `SecureKeyStore`, it just adds a second protected value instead of storing the credential there directly). |
| Credential lifecycle | A reset is a normal `UPDATE` through the existing repository pattern — arguably simpler to reason about than Option A's keyed secure-storage entries, since it's ordinary SQL. |
| Multi-device synchronization | **This is Option B's one genuine structural advantage over Option A today:** because the hash would live in the same SQLite database that docs/04 §6 already describes exporting/restoring, a full DB export/restore would carry credentials along with it, surviving device migration in a way Option A's Keystore-only storage does not. This is a real, honest point in Option B's favor for this specific dimension — stated plainly, not glossed over. |
| Cloud synchronization | Same caveat as Option A applies with more force: if this table/column were ever synced to a future cloud Postgres schema (the same UUID-upsert mechanism docs/04 §0 describes for every other table), a **hashed** credential would sync too, by default, unless explicitly excluded from the sync payload. This is a deliberate, non-trivial design decision that doesn't exist as a problem under Option A (nothing credential-shaped is in the syncable schema at all). Do not assume this is automatically fine — see §12. |
| Backup/restore | Better than Option A on this axis, per Multi-device synchronization above. |
| Credential reset | Ordinary UPDATE, no `SecureKeyStore` interaction needed for this table specifically. |
| Admin user management | Same as Option A — local, no external dependency required. |
| Audit identity | Unaffected, same as Option A. |
| Schema migration implications | **This is the option's defining cost.** Per Phase 0.6 approval condition 9 (docs/21 §condition 1), any change to the frozen v1.0 schema requires an explicit, numbered, separately-approved amendment — not something this analysis document authorizes, and not something Phase 1.4 planning silently assumed (docs/27 §7 already flagged this identically). If chosen, it needs its own amendment write-up (what source/requirement justifies it, exact DDL, migration version bump from `schemaVersion = 1` to `2`) before any implementation. |
| Future authentication provider compatibility | Slightly worse than Option A: a future Supabase Auth integration would make a local `pin_hash` column redundant, and redundant credential-shaped columns in a schema that's supposed to mirror a future external identity system are exactly the kind of thing docs/08's original design was trying to avoid by keeping `users` credential-free in the first place. |
| Separation of identity and credentials | Weaker than Option A: blending a credential hash into the `users` table (or even a sibling `user_credentials` table inside the *same* local database that later syncs to cloud Postgres) works against the separation the frozen schema's own design already implies — `users` was deliberately built as a role/profile mirror, not a credential store, and Option B reverses that without a stated reason beyond convenience. |
| Long-term maintainability | Workable, but carries a permanent schema artifact (a migration, a column) for what may be a temporary bridge until real cloud auth exists — a cost Option A avoids entirely. |

**This option is NOT selected by this document.** If preferred, it requires
its own formal schema-amendment approval per Phase 0.6 condition 9, exactly
as docs/27 §7 already stated — this analysis does not change that
requirement or treat it as satisfied.

## 9. Option C — development-only role switch / simulated authentication

| Dimension | Analysis |
|---|---|
| Why useful for development | Lets navigation-shell and RBAC-visibility work be built and tested (widget tests, manual QA) without a working credential mechanism blocking every other part of the phase. |
| Why insufficient as production authentication | Provides no actual identity verification — anyone can select any role. Fails requirement 2 (no self-signup / ADMIN-provisioned accounts) and requirement 6 (real credential material) outright. Explicitly under-delivers against the frozen roadmap's own one-liner, which names *"secure token storage"* as in-scope for Phase 1.4 (docs/21 §10), not just navigation gating. |
| Should it exist only as a test/dev mechanism | Yes, if it exists at all — e.g. as a Riverpod override used only in widget tests, never reachable from a real build. It must never be a shipped, always-available bypass. |
| Security implications | If accidentally left reachable in a release build, this would be a complete authentication bypass — categorically worse than a weak credential, not a lesser version of one. |

**Not recommended as Phase 1.4's actual mechanism** — consistent with
docs/27 §7's original flag ("least faithful option"). May legitimately exist
as an internal test fixture regardless of which of A/B is eventually chosen;
that's a testing-strategy detail, not a competing production architecture.

## 10. Possible fourth/hybrid architecture

The instruction asked whether a materially different architecture — beyond
a flat A/B/C storage choice — exists. Having read docs/08's own original
text closely (§2 above), the honest answer is: **there is no fourth
credential *storage location*** beyond "device-local secure storage" or
"the local encrypted database" for a fully offline app with no cloud
project configured. Inventing a third storage location would not be
grounded in anything this project actually has. What **is** materially
different, and *is* directly supported by docs/08's own already-written
design intent, is a layering discipline that the A/B/C framing doesn't
surface on its own:

```
IDENTITY            → users table (role/profile mirror) — unchanged either way
CREDENTIAL           → behind an AuthRepository interface — the ONLY layer
                       that differs between Option A and Option B
SESSION              → AuthSession + SecureKeyStore — already device-local,
                       already credential-mechanism-agnostic
RBAC / AUTHORIZATION → AppRole read model — orthogonal to credential mechanism
AUDIT IDENTITY       → created_by/updated_by = users.id — orthogonal to
                       credential mechanism
```

This is not a new invention — it is what docs/08 already describes as the
eventual shape (*"a UX-light control... layered on top of the Supabase
session"*): a real credential authority underneath, and a fast local
re-entry layer on top, with everything else (session bookkeeping, RBAC
visibility, audit attribution) indifferent to which authority is under it.
Today, only the "local, fast" layer exists as a buildable thing (no
external authority exists yet), so it temporarily does double duty as the
*only* tier. The materially useful conclusion is: **implement Option A's
credential check behind an explicit `AuthRepository` interface** (already
planned in docs/27 §8 — `login()`, `logout()`, `currentSession()`), so that
the actual decision this phase requires is narrower than "choose
authentication forever" — it is "what does `LocalAuthRepository` do today,"
with `SupabaseAuthRepository` (or a hybrid) as a strict, non-disruptive
future replacement of that one interface implementation, never touching
session, RBAC, or audit code. This reframes Option A from "the recommended
permanent design" to "the correct, non-wasted first implementation of a
design that was already layered this way in docs/08, just never built."

## 11. PIN vs. password analysis

**PIN:**
- Usability: fast entry, well-suited to frequent re-entry through a field
  day (docs/02 describes exactly this: password once, PIN thereafter).
- Entropy: low by construction — a 4-digit PIN has 10,000 possibilities, a
  6-digit PIN has 1,000,000. This matters most for the **offline hash
  extraction** threat (see Security analysis, §12) more than for on-device
  guessing (which lockout mitigates regardless of length).
- Offline use: no disadvantage — this whole option set is offline by
  construction.
- Brute-force protection: **length alone is not sufficient.** A fast,
  general-purpose hash (e.g. unsalted or lightly-salted SHA-256, the
  `crypto` package's most basic use) makes even a 6-digit PIN's ~1M
  keyspace trivial to exhaust offline if the stored hash is ever extracted
  (rooted device, backup extraction, compromised app process). A
  deliberately slow/memory-hard KDF (PBKDF2 with a high iteration count,
  bcrypt, or Argon2) is what actually provides meaningful resistance here —
  **this is a more specific and stricter dependency requirement than docs/27
  §11's generic "a hashing package" flag**, and should be treated as its own
  explicit item requiring approval (see §18), not assumed satisfied by
  adding any package named "crypto."
- Shoulder surfing: a real risk on a shared field device; mitigated only by
  UX choices (masked entry, timeout-to-relock), not by the credential
  architecture itself.
- Reset: trivial under either Option A or B (an ADMIN-mediated overwrite).

**Password:**
- Usability: higher friction for the frequent, on-the-go re-entry pattern
  docs/02 describes; more error-prone to type repeatedly through a field
  day (a reasonable inference from the frequent-re-entry usage pattern
  already documented, not a claim about field conditions this project has
  no direct evidence for).
- Security: materially higher entropy potential than a short PIN, for users
  willing/able to use it well.
- Storage/reset: identical mechanism to a PIN once hashed — the
  architecture doesn't distinguish between the two beyond input validation.
- Offline authentication: no disadvantage, same as PIN.

**Length/format recommendation:** docs/02's own stated design (*"password
[first login] ... PIN after first login"*) already anticipates a two-weight
scheme. Given the offline extraction threat is mitigated primarily by
**hashing strength, not PIN length**, a **6-digit numeric PIN**, combined
with a slow KDF and local lockout after repeated failures, is a defensible,
non-arbitrary choice — stricter than the minimum (4-digit) without adding
meaningful typing friction, and consistent with widely-used device-unlock
conventions the target users are likely already familiar with. **This is
presented as a factual comparison, not a unilateral final decision** — you
may prefer 4-digit for simplicity or alphanumeric for extra margin; either
remains compatible with the same architecture.

**Biometric:** if ever added, it must be a convenience unlock for an
*already-established* local session (matching docs/08's own "re-entry, not
a second full login" framing) — never the primary credential. Not
implemented by this document or by Phase 1.4 under any option.

## 12. Bootstrap Admin analysis

| Approach | Security | Usability | Offline | Recovery/reset |
|---|---|---|---|---|
| A. Seeded fixed bootstrap credential | **Rejected outright** — a fixed/known credential shipped in source or seed data is a real vulnerability from install day one; explicitly forbidden by both docs/27 §12 and this project's standing privacy/secrets discipline. | Trivial (no setup step) — but the ease is exactly the problem. | N/A | N/A — the flaw is structural, not fixable by "resetting" it. |
| B. First-run Admin setup | No credential ever touches source, seed data, or Git — the ADMIN chooses their own PIN/password the first time the app runs with an empty `users` table. | One extra setup screen, once, industry-standard pattern. | Fully offline — no external dependency. | Standard: a future ADMIN-reset flow (not built this phase) overwrites the stored hash the same way any other user's reset would. |
| C. Secure device-bound first-run enrollment (e.g., an out-of-band enrollment code) | Strictly stronger than B — prevents "whoever launches the fresh install becomes ADMIN" from being purely a physical-possession assumption. | Requires an operational distribution channel (SMS, printed code, coordinated handoff) that **does not exist in this project today** — no SMS gateway, no defined provisioning process. | Fully offline once the code exists, but the code itself needs an out-of-band delivery mechanism. | Same as B once enrolled. |

**Recommendation:** Approach B (first-run Admin setup) is the only one that
satisfies "never hardcode a credential" without inventing operational
infrastructure (an enrollment-code distribution process) this project
hasn't built or scoped anywhere. Approach C is noted as a legitimate future
hardening step once the RBSK rollout process defines how devices are
physically provisioned to the team — **that is a deployment/coordination
question for the RBSK team, not a coding question Phase 1.4 can resolve**.
Not implemented by this document.

## 13. Future user-management implications

The chosen architecture must not block (all deferred to the unscheduled
Admin-tools phase per docs/13 Phase 7, not built now):

- **Create user:** works identically under Option A or B — insert a `users`
  row, then (A) establish a `SecureKeyStore` entry or (B) an `UPDATE` on the
  credential column/table, on whichever device performs the creation.
- **Deactivate user:** already supported structurally (`users.is_active`),
  independent of credential option.
- **Change role:** an `UPDATE users.role` — independent of credential option.
- **Reset credential:** local overwrite either way (§7/§8 lifecycle rows).
- **Revoke sessions:** requires session state to be device-local and
  inspectable — already true of the planned `AuthSession`/`SecureKeyStore`
  design regardless of option.
- **Audit user actions / last login:** `users.last_login_at` already exists,
  frozen, nullable — usable under either option with no schema change.
- **Device association / multiple devices:** the `devices` table already
  exists (docs/04 §2.1) and is orthogonal to the credential decision; using
  it is optional in Phase 1.4 (docs/27 §6, §19 Q4) either way.
- **Staff/team changes:** already modeled by the append-only
  `staff_assignments` table (Phase 1.2/1.3), entirely separate from `users`
  and unaffected by this decision.

## 14. Cloud/future-sync implications

**Can be safely decided now:**
- Local `users.id` stays the identity key, already designed (docs/04 §0) to
  be the same UUID a future cloud `auth.users`-linked row would use.
- Whatever local credential mechanism Phase 1.4 builds should be treated as
  **not** a candidate for syncing to any future cloud schema — under Option
  A this is automatic (nothing credential-shaped exists in a syncable
  table); under Option B it would need an explicit, deliberate exclusion
  from any future sync payload (a real design cost Option A avoids, stated
  plainly per §8).
- UUID identity, role, and audit identity are all safely stable regardless
  of which future cloud auth provider (if any) is eventually chosen —
  nothing here is Supabase-specific.

**Must remain flexible / TBD until cloud architecture is finalized:**
- Whether credentials should EVER be synchronized — **no.** Not assumed
  under either option; explicitly flagged here so it is never silently
  assumed later either.
- Token/session synchronization across devices — not decidable without a
  real sync design (docs/07, unscheduled).
- Device-specific sessions vs. a single cross-device session — same, not
  decidable now.
- Whether Supabase specifically (vs. another provider, vs. self-hosted
  Postgres per docs/08's own "data residency... explicit architecture
  decision" language) is ever adopted — genuinely open, tracked already at
  docs/00 §10 item 6, not resolved or assumed by this document.

## 15. Security threat considerations

Distinguishing exactly what protects what, as instructed — not overclaiming:

| Threat | What actually protects against it |
|---|---|
| Device lost/stolen, screen unlocked | Nothing here — that's the OS lock screen's job, out of scope for this app. |
| Someone picks up an unlocked device and opens the app | The session gate (route guard) plus, if configured, a re-entry PIN timeout — a UX control, not a cryptographic one (docs/08 already frames it this way). |
| Repeated PIN guessing through the app's own UI | Local failed-attempt lockout — a control this document recommends as a requirement (§5), not yet implemented anywhere. |
| Full device/backup extraction, credential hash recovered | The KDF's strength (§11) — this is the layer that actually matters here, not PIN length or storage location. |
| Rooted/compromised device, live process inspection | Android Keystore's hardware-backed protection (where the device supports it) raises the bar but is not absolute against a fully compromised, rooted device running as the same app — this project cannot claim otherwise. |
| SQLite DB file copied off the device | Already mitigated for all business data (Phase 1.2, verified round-trip + wrong-key-rejection tests) — extends automatically to a credential hash *only* under Option B, since Option A's hash never enters that file. |
| Accidental credential inclusion in Git | Process discipline (the pre-commit PII/secret scans already run every phase) plus the structural fact that neither option stores raw/plaintext credentials anywhere a file-based scan would need to catch mid-transit. |
| Server/cloud-side protections (RLS, TLS) | **Not applicable yet** — there is no server. Nothing in this document claims server-side protection exists. |

## 16. Decision matrix

Factual comparison only — no scores, no "winner."

| Area | Option A (local, no schema change) | Option B (schema change) | Option C (dev-only) | Hybrid/Future (layered interface, §10) |
|---|---|---|---|---|
| Offline login | Yes | Yes | Yes (trivially — no real check) | Yes |
| Security (given a strong KDF) | Equivalent to B for the credential itself; adds Keystore as a second boundary | Equivalent to A; inherits SQLite's existing at-rest encryption | None — not real authentication | Same as whichever concrete implementation is behind the interface |
| Credential storage | `SecureKeyStore`, keyed by `users.id` | `users` table or sibling table, inside the encrypted SQLite DB | None persisted | Delegated to the active `AuthRepository` implementation |
| Multi-user | Via key-naming convention | Via row-per-user | N/A | Same as underlying option |
| Multi-device | Independent per-device setup required | Same, unless DB is restored (see Backup/restore) | N/A | Same as underlying option |
| Backup/restore | Credential lost on reinstall; DB rows unaffected | Credential survives a DB export/restore | N/A | Same as underlying option |
| Reset | Overwrite a `SecureKeyStore` entry | Ordinary `UPDATE` | N/A | Same as underlying option |
| Admin management | Local, no external dependency | Local, no external dependency | N/A | Same as underlying option |
| Cloud sync | Credential never in a syncable table (safe by construction) | Credential would need explicit exclusion from any future sync payload | N/A | Deliberately isolated behind the interface either way |
| Audit | Unaffected (identity-based, not credential-based) | Unaffected | Unaffected | Unaffected |
| Schema impact | None | **Requires a formal amendment (Phase 0.6 condition 9)** | None | None (the interface itself is code-only) |
| Complexity | Low | Low–Medium (adds a migration) | Very low | Low, with a small upfront interface-design cost |
| Future flexibility | High if built behind an interface (§10) | Slightly lower — a schema artifact persists even if superseded | None — must be replaced entirely | Highest — explicitly designed for replacement |
| Production suitability | Yes, with a strong KDF and lockout | Yes, with a strong KDF and lockout | **No** | Depends entirely on the concrete implementation chosen |

## 17. Recommended architecture

**Option A, implemented behind an explicit `AuthRepository` interface
boundary (the layering described in §10), using a slow/memory-hard KDF
(§11) and a first-run Admin setup flow (§12).**

This is not "Option A because it avoids a schema change" as a standalone
justification — it is recommended because:

1. It is the only option that requires no separately-approved schema
   amendment (Phase 0.6 condition 9) to even begin, which matters given
   nothing here currently justifies reopening the frozen schema — no source
   material or requirement newly demands a credential column; the need is
   purely an artifact of Supabase integration not being scheduled yet.
2. It is **more**, not less, consistent with the frozen schema's own
   original intent (`users` as a profile/role mirror, never a credential
   store) than Option B would be — Option B would reverse a deliberate
   design choice without new justification.
3. Its real costs (credential loss on reinstall, per-device setup) are
   costs this project has **already accepted once**, for the DB encryption
   passphrase itself (Phase 1.2) — not a new category of risk being
   introduced here.
4. Built behind an interface (§10), it does not foreclose Supabase Auth or
   any other future provider — replacing `LocalAuthRepository` later
   touches nothing in session, RBAC, or audit code, which is precisely the
   layering docs/08 already implied.

**What would change this recommendation:** if a concrete, dated cloud/sync
phase gets scheduled soon, and multi-device credential portability (Option
B's one genuine advantage, §8) becomes an actual near-term requirement
rather than a hypothetical one, Option B's tradeoff could reasonably shift.
That is not the situation today (docs/00 §5: cloud sync has no phase number
anywhere in the roadmap) — so this recommendation is made for the
architecture as it actually stands, not a forecast.

**No single option is being silently treated as approved.** Per your
instruction, this remains a recommendation, not a decision — §18/§19 state
exactly what still needs your sign-off.

## 18. Decisions that require your approval

1. **Option A vs. Option B** — the one decision that actually changes what
   gets built. Option B additionally requires its own separate,
   numbered schema-amendment approval per Phase 0.6 condition 9 if chosen.
2. **KDF/hashing package choice** — a more specific ask than docs/27 §11's
   generic "a `crypto` package" flag: the requirement is specifically a
   slow/memory-hard KDF (PBKDF2-with-many-iterations, bcrypt, or Argon2),
   not a fast general-purpose hash. This is a new dependency and needs its
   own approval regardless of which option is chosen.
3. **PIN length/format** — 6-digit numeric is presented as defensible and
   consistent with docs/02's own stated design, not as a unilateral choice.
4. **Bootstrap approach** — first-run Admin setup (§12 approach B) is
   recommended; approach C (out-of-band enrollment code) is flagged as a
   future hardening step contingent on an RBSK rollout/provisioning process
   that doesn't exist yet.

## 19. Decisions that should remain TBD

- Whether user state (active/inactive, role) ever synchronizes across
  devices, and how conflicts resolve — depends on the unscheduled sync
  phase (docs/07).
- Whether credentials specifically should ever synchronize — presumptively
  **no** under either option, but not something this document can finalize
  in the absence of a real sync design.
- Data residency / eventual cloud identity provider choice — already
  tracked at docs/00 §10 item 6; unaffected by, and not resolved by, this
  document.
- Whether a `devices` row is required this phase — unchanged from docs/27
  §19 Q4 (recommended deferred, not decided here).
- Exact lockout policy (attempt count, cooldown duration) — a reasonable
  implementation-time detail once an option is approved, not an
  architectural fork.

## 20. Phase 1.4 implementation prerequisites

Before any Phase 1.4 code is written:

1. You approve Option A **or** Option B (§18 item 1). If Option B, a
   separate schema-amendment approval is required first, per standing
   project rule.
2. You approve (or redirect) the specific KDF/package (§18 item 2).
3. You approve (or redirect) the PIN length/format recommendation (§18
   item 3).
4. You approve (or redirect) the bootstrap approach (§18 item 4).
5. You approve the docs/27 plan itself (still pending, unaffected by this
   document — this analysis narrows §7/§19's open questions, it does not
   substitute for approving the plan as a whole).

## 21. This document does not authorize implementation

No code was written. No dependency was added. No schema, migration, table,
or seed data was created or modified. `lib/`, `test/`, `pubspec.yaml`,
`pubspec.lock`, and all Android build files are untouched by this turn —
confirmed by `git diff --stat` (see the Final Report). Phase 1.4 remains
PLANNED and NOT APPROVED. Nothing here is implemented until you explicitly
approve a specific option and the plan itself.
