# Security Architecture

Child health data is sensitive by default; this app is designed security-first, not
retrofitted.

## Implemented today (Phase 1.4 + security hardening, 2026-09-24)

This file's sections below describe the original target design (cloud
identity via Supabase). What is actually built today is device-local:

- **Authentication:** a 6-digit PIN per user, verified on the phone against
  a PBKDF2-HMAC-SHA256 verifier (210,000 iterations; versioned and
  upgradable) in Android Keystore-backed secure storage. No credential is
  stored in the database, no cloud identity exists, and credentials never
  sync or leave the phone. See docs/27 §0, docs/28, docs/31.
- **Recovery:** a forgotten Admin PIN is reset with the Admin Recovery Code
  (128-bit, shown once, single-use, rate-limited, audited). This never
  touches the database or its key.
- **Database key:** random 256-bit, in its own secure-storage namespace. It
  is never silently replaced or deleted. A missing or unreadable key stops
  the app with a plain-language "data is locked, not deleted" screen.
- **Backup:** Android platform backup and device-to-device transfer are
  disabled. The only backup is the app's own Encrypted Recovery Package:
  the database stays encrypted, and its key is AES-256-GCM-wrapped under a
  key derived from the separate Backup Recovery Key. The package is
  Admin-created and saved through Android's document picker.
- **Audit:** security events are recorded in `audit_log` (docs/04 §2.11)
  without secrets.

## Authentication

- Supabase Auth (email/password, or phone+OTP if preferred once confirmed) — no
  self-registration. Accounts for the ~8–10 users are created by ADMIN via the User
  Management screen (which calls Supabase's admin API, not public signup).
- Local session tokens stored via `flutter_secure_storage` (backed by Android Keystore),
  never in plain SharedPreferences.
- Recommend an app-level PIN or biometric re-entry after inactivity, given the app runs
  on shared/departmental Android devices in the field — this is a UX-light control
  (device already authenticated once) layered on top of the Supabase session, not a
  second full login.

## Authorization (RBAC)

- Enforced at two layers:
  1. **Client-side** — UI hides/disables actions not permitted for the current role
     (fast feedback, good UX).
  2. **Server-side (Postgres Row Level Security)** — the authoritative check. Every
     table's RLS policy mirrors the matrix in
     [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §3. Client-side checks
     alone are never trusted, since a compromised or modified client must not be able to
     bypass permissions.
- Three roles only (ADMIN / MEDICAL_OFFICER / TEAM_MEMBER) — deliberately coarse per
  brief §25.

## Data at rest

- **Local device:** SQLite database encrypted at rest, implemented and verified in
  Phase 1.2 via Drift + `sqlite3` with the SQLite3MultipleCiphers native build
  (`sqlite3mc`) — SQLCipher-*compatible* (same `PRAGMA key` mechanism, same cipher
  family), selected via a `hooks.user_defines` block in `pubspec.yaml`, and
  actively maintained. (The `sqlcipher_flutter_libs` package originally named here
  reached end-of-life before implementation began and is no longer used — see the
  note below.) The encryption key is a 256-bit value generated with
  `Random.secure()`, stored only via `flutter_secure_storage`/Android Keystore —
  never hardcoded, never logged, never stored in plain text alongside the database
  file, and never committed to Git. Verified end-to-end: data written with the
  correct key round-trips after reopening; the same file is unreadable with the
  wrong key; `libsqlite3mc.so` is confirmed bundled in the built APK. Full detail:
  [24_PHASE_1_2_REPORT.md](24_PHASE_1_2_REPORT.md) §C.
- **Register photos (local):** stored in app-private external/internal storage (not the
  public gallery — matching the sibling project's precedent of not requesting the
  CAMERA permission's public-storage side effects), with no additional file-level
  encryption beyond OS app-sandboxing for Phase 0 (flag as a hardening item, not a
  blocker, since Android app-private storage is already inaccessible to other apps
  without root).
- **Cloud:** Postgres database encryption at rest is provider-managed (Supabase). Photos
  live in **private** Storage buckets (not public), accessed only via short-lived signed
  URLs generated server-side — never a permanently public photo URL.

## Data in transit

- All client-cloud communication over TLS (Supabase's HTTPS endpoints exclusively; no
  custom unencrypted endpoints).
- No personal/health data ever placed in URL query strings or logs.

## Audit trail

- `audit_log` (see [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §2.9)
  captures who/when/what for every INSERT/UPDATE/SOFT_DELETE across business tables —
  append-only, never editable from the app.
- `created_by`/`updated_by` on every business row, always a real `users.id`.
- Audit log is ADMIN-viewable (read-only) via the Audit Log Viewer screen — a Phase-0-
  optional but architecturally-free addition since the table exists regardless.

## Data integrity & safe deletion

- No hard deletes anywhere in the business schema — soft-delete only
  (`is_deleted`/`deleted_by`/`deleted_at`), so nothing a user "deletes" is actually
  unrecoverable without an explicit, separate admin purge tool (out of scope Phase 0).
- Historical immutability guarantees (original planned dates, staff assignment history,
  disease-category snapshots on findings) are structural — see
  [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §0 and §7 — not just a
  policy to remember.

## Backup

- Cloud: provider-managed automated backups (tier/retention TBD — budget decision, see
  [12_RISKS_OPEN_QUESTIONS.md](12_RISKS_OPEN_QUESTIONS.md)).
- Local: ADMIN-triggered manual encrypted export as a disaster-recovery fallback (see
  [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §6). **Implemented**
  as the Encrypted Recovery Package (docs/31 §6–§7). Android platform backup
  is deliberately disabled so it can never become an uncontrolled copy
  (docs/31 §8). Where packages are kept is a custody/data-residency question
  still open (docs/00 §10).

## Data residency — open question, not an assumption

RBSK is a government health program handling child PII and health findings. Whether a
specific data-residency or government-approved-hosting policy applies (state health
department requirements, ABDM alignment, etc.) is **not assumed either way** in this
package. Supabase Cloud's default region and Supabase's self-hosting option are both
compatible with this schema/RLS design — which one to use is a policy question to
resolve with the district health authority before Phase 4 (cloud sync), not a technical
constraint. See [12_RISKS_OPEN_QUESTIONS.md](12_RISKS_OPEN_QUESTIONS.md).

## Explicitly out of scope for Phase 0

- Formal compliance certification (no specific regulatory framework is assumed/claimed
  here — resolve with the appropriate authority, don't take this document's word for
  compliance).
- Penetration testing / third-party security audit (recommended before wide rollout,
  not part of architecture planning).
