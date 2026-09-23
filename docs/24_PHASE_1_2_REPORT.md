# Phase 1.2 — Implementation Report

**Status: complete.** Frozen v1.0 schema ([04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md))
implemented in Drift with encrypted local storage. Phase 1.3 has **not** been
started.

| | |
|---|---|
| Date | 2026-09-23 |
| Flutter | 3.47.2 (stable) · Dart 3.13.2 |
| Phase 1.1 commits | `2201795`, `9e90c73`, `9d378a0` (reviewed before starting — see §Inspection) |
| Phase 1.2 commit | `6dabedc6a6cf28f31eb6a8585cf3fe0956c94b7f` |

## Inspection (performed before writing any code)

1. Read [21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md) in full — approval
   conditions and domain model.
2. Read [23_PHASE_1_1_REPORT.md](23_PHASE_1_1_REPORT.md) — confirmed the
   skeleton's dependency policy, folder structure, and that no database code
   existed yet.
3. Inspected the current project tree (`lib/`, `pubspec.yaml`) — confirmed a
   clean slate for `lib/data/local/`.
4. Read [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §2 in full
   and enumerated every `CREATE TABLE` statement with `grep`, independent of
   the document's own prose summary.
5. **Discrepancy found and resolved during inspection, not silently:** the
   freeze document's §3 "Final domain model" prose said "24 tables in four
   groups." Direct enumeration of the DDL found **28** `CREATE TABLE`
   statements. This is a documentation miscount in a summary paragraph, not a
   contradiction in the schema itself — the DDL (the actual frozen artifact)
   is internally consistent and was treated as authoritative. All 28 tables
   are implemented; the miscount is noted here rather than corrected
   silently in the frozen doc (that correction is a documentation matter for
   your review, not a schema change).
6. Catalogued every table's primary key, foreign keys, nullable/required
   columns, unique constraints (including partial/filtered ones), CHECK
   constraints, enums, audit fields, soft-delete fields, and append-only
   (history) tables — reflected 1:1 in the Dart table definitions (see
   §Schema mapping).
7. Confirmed the plan against docs/06_PROJECT_STRUCTURE.md's `lib/data/local/`
   location before creating any file.

Only after this did implementation start.

## A. What was implemented

- **28 Drift tables**, one-for-one with the frozen schema, organized into 9
  files under `lib/data/local/tables/` mirroring the document's own §2.1–§2.11
  grouping, plus `lib/data/local/enums.dart` (20 Dart enums, one per Postgres
  `ENUM` type).
- **`AppDatabase`** (`lib/data/local/app_database.dart`) — the single
  `@DriftDatabase` class registering all 28 tables, `schemaVersion = 1`, a
  `MigrationStrategy` (`onCreate` + `beforeOpen` enabling `PRAGMA
  foreign_keys`).
- **Encrypted local storage** (`lib/data/local/database_connection.dart`) —
  see §C.
- **Centralized lifecycle** (`lib/data/local/database_provider.dart`) — one
  Riverpod `FutureProvider<AppDatabase>`; nothing else in the app opens a
  connection.
- **29 tests** across 7 files under `test/data/local/`.

## B. Database / table status

All 28 tables created, verified by direct `sqlite_master` introspection in a
test (`app_database_test.dart`: *"creates all 28 tables from the frozen
schema"*), not just by absence of errors.

| Frozen doc §2.x | Tables | File |
|---|---|---|
| 2.1 Reference/Identity | `financial_years`, `staff`, `staff_assignments`, `users`, `devices` | `reference_identity_tables.dart` |
| 2.2 School/AWC Master | `schools`, `awcs`, `plan_imports` | `school_awc_tables.dart` |
| 2.3 Visit Planning | `visit_plans`, `holidays`, `visit_status_history` | `visit_planning_tables.dart` |
| 2.4 Disease Master | `disease_master`, `disease_aliases` | `disease_master_tables.dart` |
| 2.5 Session Context | `screening_sessions` | `screening_session_tables.dart` |
| 2.6 School Screening | `school_screenings`, `school_screening_findings` | `school_screening_tables.dart` |
| 2.7 AWC Screening | `awc_screenings`, `awc_screening_findings`, `awc_checklist_items`, `awc_screening_checklist_responses` | `awc_screening_tables.dart` |
| 2.8 Referral Config | `referral_destinations`, `referral_destination_contexts` | `referral_configuration_tables.dart` |
| 2.9 Treatment | `treatment_records` | `treatment_tables.dart` |
| 2.10 Register/OCR | `register_photos`, `register_photo_derivatives`, `ocr_jobs`, `ocr_results` | `register_photo_tables.dart` |
| 2.11 Audit | `audit_log` | `audit_tables.dart` |

**Preserved exactly, verified by test where the instructions called for it:**
- Client-generated **TEXT UUID primary keys** on every table (no
  autoincrement anywhere).
- **All foreign keys**, enforced (`PRAGMA foreign_keys = ON` set in
  `beforeOpen`, confirmed by test — a bad FK insert throws
  `SqliteException`).
- **Partial unique indexes** on `official_school_code` and
  `official_awc_code` (unique only among non-blank values) — `@TableIndex.sql`
  with the exact `WHERE` clause from the frozen DDL.
- **No unique index on `source_plan_awc_code`** — deliberately absent;
  regression-tested (§Test coverage).
- **All CHECK constraints** — `visit_plans` school-XOR-awc,
  `treatment_records` school-XOR-awc and further-referral-requires-destination,
  age-range checks on both screening tables — via Drift's `customConstraints`.
- **Every enum**, stored as `TEXT` via `textEnum<T>()`, with Dart enum member
  names kept identical to the frozen doc's own values (e.g. `TEAM_MEMBER`,
  not `teamMember`) so the on-disk value matches the spec and the eventual
  Postgres enum verbatim — see the file-level note in `enums.dart`.
  (`constant_identifier_names` is suppressed for that one file, deliberately,
  documented inline.)
- **Audit fields** (`created_by`/`created_at`/`updated_by`/`updated_at`/
  `row_version`) on every mutable table, **soft-delete**
  (`is_deleted`/`deleted_by` where the frozen doc specifies it — note: the
  frozen DDL itself does not list `deleted_by`/`deleted_at` columns on most
  tables despite §0's prose mentioning them; implemented exactly as the
  per-table DDL shows, not as the summary prose implies — flagged in
  §J Deviations).
- **Append-only tables** (`visit_status_history`, `staff_assignments`,
  `audit_log`, `ocr_results`) carry no `is_deleted`/`row_version` machinery,
  matching the frozen doc precisely.
- **`created_by`/`updated_by` carry no FK constraint** anywhere — this is
  what the frozen DDL literally specifies (plain nullable `uuid`, never
  `REFERENCES users(id)`), preserved as-is even though it looks like it
  "should" reference `users` — not fixed, because Phase 1.2 does not
  redesign the frozen schema.

### SQLite-specific translations (not schema changes)

Postgres constructs with no SQLite equivalent were translated mechanically,
documented inline at each site:

| Frozen (Postgres) | Local (SQLite/Drift) | Where documented |
|---|---|---|
| `jsonb` | `TEXT` (JSON-encoded) | Comment on every such column |
| `numeric(5,2)` / `numeric(10,2)` | `REAL` | `awc_screenings`, `awc_screening_checklist_responses` |
| `date` / `timestamptz` | `TEXT` (ISO-8601, via `store_date_time_values_as_text: true` in `build.yaml`) | `build.yaml` comment |
| `GIN (... gin_trgm_ops)` trigram indexes (`schools`, `awcs`, `disease_master`) | **Not created** — no SQLite equivalent; Postgres-only, applies to the cloud schema in a later phase | Comment at each affected table |
| `coalesce(finding_category::text, '*')` | `COALESCE(finding_category, '*')` (no cast needed — already TEXT) | `referral_configuration_tables.dart` |

None of these change what the schema *means* — every one is the standard,
unavoidable mapping between a Postgres-flavored spec (the frozen doc's own
framing: "Postgres-flavored DDL... SQLite/Drift mirrors this") and SQLite.

## C. Encryption approach

**The `sqlcipher_flutter_libs` package named in
[08_SECURITY_ARCHITECTURE.md](08_SECURITY_ARCHITECTURE.md) is end-of-life**
(pub.dev: `0.7.0+eol`, "This package relates to version 2.x of
`package:sqlite3`... obsolete after upgrading. Not used anymore, update to
version 3.x of `package:sqlite3` instead"). Verified directly against
pub.dev and Drift's own documentation before writing any code (Phase 1.2
instruction §3: *"verify compatibility... use a maintained package/
approach... do not invent an encryption implementation"*).

**What's implemented instead — Drift's current documented replacement:**

1. `sqlite3: ^3.6.0` (latest, published 9 days before this phase) bundles
   SQLite natively — `sqlcipher_flutter_libs` is not needed at all.
2. `pubspec.yaml` carries a `hooks.user_defines` block selecting the
   **SQLite3MultipleCiphers** (`sqlite3mc`) native build instead of plain
   SQLite. This is SQLCipher-*compatible*: same `PRAGMA key = '...'`
   mechanism, same cipher, and the Drift docs give an explicit migration path
   from legacy SQLCipher databases if one is ever needed.
   ```yaml
   hooks:
     user_defines:
       sqlite3:
         source: sqlite3mc
   ```
3. `lib/data/local/database_connection.dart`:
   - `openEncryptedDatabase()` opens a `NativeDatabase.createInBackground()`
     against a file in the app's private documents directory, running
     `PRAGMA key = '<passphrase>'` in the `setup` callback before any other
     statement executes.
   - `debugCheckHasCipher()` (via `PRAGMA cipher`) is asserted in that same
     callback — if the multi-cipher build weren't active, this would fail
     immediately in debug builds rather than silently persisting unencrypted
     data.
   - `configureSqlite3TempDirectory()` sets `sqlite3.tempDirectory` (Android
     requires this — the platform's default temp directory isn't usable by
     sqlite3 for some operations, including the rekey path).

### Key management

- `DatabaseKeyManager` generates a **256-bit** passphrase with
  `Random.secure()` (cryptographically secure, platform-backed — never the
  non-secure `Random()`), hex-encoded, on first launch only.
- Stored via `FlutterSecureStorageKeyStore` → `flutter_secure_storage`
  (Android Keystore-backed) — never hardcoded, never logged, never written
  next to the database file.
- `SecureKeyStore` is a small abstraction (`read`/`write`) introduced purely
  so `DatabaseKeyManager` is unit-testable without a platform channel — the
  only production implementation wraps `FlutterSecureStorage` directly; no
  behavior differs from calling it directly.
- PRAGMA statements can't use `?` bind parameters, so the passphrase is
  interpolated after `escapeForSqlLiteral()` (doubles embedded `'`) — the
  standard SQL-escaping approach, tested against an actual injection-shaped
  string executed on a real sqlite3 connection (not just a substring check).

### Verification performed (not just "should work")

1. **Real file, correct key, round-trip**: write via one connection, close,
   reopen via a second connection with the same (persisted) key, read the
   data back — passes.
2. **Real file, wrong key, must fail**: same file, a second `DatabaseKeyManager`
   with an unrelated key store (simulating a different device/install) —
   reading throws. This is the test that actually proves encryption is
   active, not a no-op.
3. **APK-level proof**: after `flutter build apk --debug`, the built APK was
   inspected directly —
   `lib/arm64-v8a/libsqlite3mc.so` / `armeabi-v7a/libsqlite3mc.so` /
   `x86_64/libsqlite3mc.so` are present (not plain `libsqlite3.so`),
   confirming the `hooks.user_defines` mechanism took effect through the
   **real Android Gradle build**, not just the Dart test runner.

### Why a new dependency (`flutter_secure_storage`) was justified

Already specified by [08_SECURITY_ARCHITECTURE.md](08_SECURITY_ARCHITECTURE.md)
("session tokens stored via `flutter_secure_storage`... never hardcoded,
never stored in plain text") for a different purpose (auth tokens, a later
phase) — reusing it now for the DB key avoids a second, redundant
Keystore-wrapping mechanism. Verified: actively maintained (`11.2.0`,
published 6 days before this phase, 4.49k likes, Android Keystore-backed).

## D. Migration status

- `schemaVersion = 1` **is** the frozen v1.0 schema — not a placeholder
  version with fields missing.
- `MigrationStrategy.onCreate` builds all 28 tables in one pass
  (`m.createAll()`).
- **No destructive recreation anywhere** — there is no "drop and rebuild on
  mismatch" code path. The strategy is structured so the *next* schema
  change adds a numbered `if (from < 2) { ... }` step inside `onUpgrade`
  rather than replacing this strategy (documented inline in
  `app_database.dart`).
- Tested: reopening an existing database file (same path, second connection)
  preserves previously-written data rather than being silently recreated —
  the property any future incremental migration depends on.
- No `onUpgrade` steps exist yet because there is no prior version to migrate
  *from* — this is honestly stated rather than padded with a fabricated v2
  migration that doesn't correspond to any real schema change.

## E. Dependencies added

| Package | Version | Why |
|---|---|---|
| `drift` | 2.35.0 | Type-safe SQL / query builder / migrations |
| `sqlite3` | 3.6.0 | Native SQLite, encryption via the `hooks` mechanism |
| `path_provider` | 2.1.6 | App-private documents directory for the DB file |
| `path` | 1.9.1 | Join the directory + filename safely |
| `flutter_secure_storage` | 11.2.0 | Android Keystore-backed key storage (justified above) |
| `drift_dev` | 2.35.0 (dev) | Code generation |
| `build_runner` | 2.16.1 (dev) | Code generation runner |

**Not added:** camera, OCR, Supabase, PDF, Excel, sharing, auth UI, `uuid`
(test IDs are plain strings; real UUID generation is a repository-layer
concern for a later phase) — nothing beyond what this phase's database layer
required.

## F. Test coverage

**52 tests total** (23 from Phase 1.1 + 29 new), all passing. The 29 new
tests, by file:

| File | Tests | Covers |
|---|---|---|
| `app_database_test.dart` | 12 | Opens successfully, schema version, all 28 tables exist, FK enforcement enabled, duplicate PK rejected, FK violation rejected, valid FK accepted, CHECK constraint rejects both-null, nullable/blank official codes, non-blank code uniqueness, timestamps/row_version defaults, update advances them, soft-delete without physical deletion, `visit_status_history` accumulates (3 transitions), `staff_assignments` preserves a closed row, basic insert/read/update round-trip |
| `awc_identity_test.dart` | 5 | Official AWC code nullable, two nulls coexist, non-blank uniqueness once real data exists, **regression**: two AWCs legally share one `source_plan_awc_code` (the exact HEERAPUR/BARODASWAMI scenario from docs/16), a repeated plan code never becomes a fabricated official code |
| `planned_vs_actual_test.dart` | 2 | Planned counts (verbatim, mismatch preserved) vs. actual screened count (derived from real rows) stay independent; structural check that no "actual count" column exists to accidentally use |
| `normal_child_test.dart` | 3 | Normal child = zero finding rows, no sentinel value written; `disease_master` never gains a NORMAL/NONE/NO_DISEASE row; a child with a finding is distinguishable purely by finding-row existence |
| `register_photo_provenance_test.dart` | 2 | Full chain representable (original → derivative → job → result → unreviewed), original untouched by the derivative; the confirm-then-link flow (raw extraction never overwritten by correction) |
| `referral_configuration_test.dart` | 2 | School (3, all-category) vs. AWC (5, category-routed) destinations never cross-contaminate in queries; a School finding and an AWC finding resolve independently through the same table |
| `database_connection_test.dart` | 9 | Passphrase entropy/uniqueness, SQL-escaping (behavioral, not substring), key persistence/idempotency, two independent stores diverge, **real encrypted file round-trips with correct key**, **real encrypted file unreadable with wrong key** |
| `migration_test.dart` | 3 | Schema version + migration object present, reopening preserves data, `onCreate` populates all 28 tables in one pass |

Tests run against `NativeDatabase.memory()` or real temp-directory files —
never the production database path, never real secure storage (an in-memory
`SecureKeyStore` fake is used). No real child, parent, or staff data appears
anywhere in test fixtures — `Seeds` in `test_database.dart` uses only
placeholder names ("Test School", "Normal Child") and a single School Code
(`9370301901`) already public in this project's own Phase 0.5 documentation.

## G. Commands executed and results

| # | Command | Result |
|---|---|---|
| 1 | `flutter pub get` | ✅ resolved |
| 2 | `dart run build_runner build` | ✅ generated `app_database.g.dart` (44,380 lines, 63 outputs) |
| 3 | `flutter analyze` | ✅ **No issues found** |
| 4 | `flutter test` | ✅ **52/52 passed** |
| 5 | `flutter build apk --debug` | ✅ built in 197.0s; `libsqlite3mc.so` confirmed bundled (3 ABIs) |

## H. Security / Git verification

- Staged diff scanned for API keys, secrets, private-key headers, cloud
  provider tokens — none found.
- Staged diff scanned for phone-number-shaped literals — every match traced
  individually; all are substrings of `pubspec.lock` package SHA-256 hashes
  except one deliberate test value (`9370301901`, a School Code already
  published in this project's own Phase 0.5 documentation — an institutional
  identifier, not a person).
- `app_database.g.dart` confirmed **excluded** from the commit
  (`git check-ignore` — matches the `*.g.dart` rule already in `.gitignore`
  from Phase 1.1). This is a **continuation of the existing, documented Git
  policy**, not a new decision — Phase 1.2 instruction §19 says to follow
  the project's Git policy, and Phase 1.1 already established "exclude
  generated code, regenerate after checkout."
- `reference_materials/`, `local.properties`, and all other Phase 1.1
  exclusions remain in force — none appear in the diff.
- No real register images, child names, parent names, real phone numbers, or
  health records anywhere in this phase's changes.
- Working tree confirmed clean after the commit (`git status --short` —
  empty output).

## I. Git

**Commit:** `6dabedc6a6cf28f31eb6a8585cf3fe0956c94b7f` — *"Phase 1.2: frozen
v1.0 schema in Drift with encrypted local storage"*.

29 files changed: 17 new library files (`enums.dart`, `app_database.dart`,
`database_connection.dart`, `database_provider.dart`, 9 table files),
`build.yaml` (new), `pubspec.yaml`/`pubspec.lock`/`analysis_options.yaml`
(modified), 9 new test files. Nothing unrelated to Phase 1.2 is in this
commit — no Phase 1.3 scaffolding, no UI screens.

## J. Deviations and things worth your attention

1. **Table-count discrepancy in `21_PHASE_0_6_FREEZE.md`** (§Inspection
   item 5): that document's prose says "24 tables in four groups"; the DDL
   itself has 28. Implemented all 28 per the DDL (the actual frozen
   artifact). Recommend fixing the prose count in a documentation-only edit —
   not done here since Phase 1.2 is a code phase and that number isn't part
   of the schema itself.
2. **`sqlcipher_flutter_libs` → `sqlite3` + `sqlite3mc` hooks.** Covered in
   full in §C. This is a **package substitution, not an architecture
   change** — the encryption requirement, the `PRAGMA key` mechanism, and
   the SQLCipher-family cipher are all unchanged; the specific pub.dev
   package implementing it changed because the one named in Phase 0 reached
   end-of-life in the time since that document was written. Flagged
   proactively rather than silently swapped — if you'd prefer a different
   package, this is the place to redirect before Phase 1.3 builds on top of
   it.
3. **`created_by`/`updated_by`/`deleted_by` carry no FK constraint**, on
   every table, because that's what the frozen DDL literally specifies (a
   plain nullable `uuid` column, never `REFERENCES users(id)` — only
   columns the DDL explicitly marks, like `changed_by`, `captured_by`,
   `imported_by`, `started_by`, `reviewed_by`, `actor_user_id`, do reference
   `users`). This looks slightly inconsistent on inspection, but Phase 1.2
   does not redesign the frozen schema — flagged for your awareness rather
   than "fixed."
4. **`deleted_by`/`deleted_at` are not present on any table**, despite §0's
   prose describing "is_deleted/deleted_by/deleted_at." The per-table DDL in
   the same document only ever shows `is_deleted`. Implemented per the
   per-table DDL (the more specific, actually-executable artifact) — same
   category of issue as #1, a prose/DDL mismatch in the frozen doc rather
   than a genuine contradiction requiring a stop, since only one of the two
   is executable SQL.
5. **No `sync_queue` table.** It's documented in
   [07_OFFLINE_SYNC_ARCHITECTURE.md](07_OFFLINE_SYNC_ARCHITECTURE.md) as
   "local-only," separate from the 28-table business schema in
   [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) — out of scope
   for "the frozen v1.0 schema" as that document defines it, and squarely
   sync-engine territory (explicitly excluded from Phase 1.2). Will be added
   when the sync engine phase begins.
6. **Device verification still pending** (unchanged from Phase 1.1 — no
   Android device or emulator is attached to this machine). Per your
   Phase 1.1 approval, this remains explicitly not a blocker.

None of the above required stopping or changing the frozen schema — items
1, 4, 5 are documentation/scope clarifications, item 2 is a
maintained-package substitution with the same behavior, item 3 is a
faithful (if slightly surprising) preservation of the frozen DDL exactly as
written, and item 6 was already accepted as non-blocking.
