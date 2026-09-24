# Phase 1.5 — School/AWC Master CRUD + Search (Implementation Plan)

**Status: IMPLEMENTED (commit `090def5`), awaiting user review/closure.**
Results, evidence and deviations: [36_PHASE_1_5_REPORT.md](36_PHASE_1_5_REPORT.md).
The plan text below is kept as approved. Where the implementation differs
(routes `/add` and `/:id/edit` instead of `/new`; no automatic provider
retry; non-lazy form and detail layouts), docs/36 §8 records it.

Scope reference: [21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md) §10, step 1.5:
"School/AWC Master CRUD + search; blank official codes preserved; duplicate
review surface". Exit criterion: *"Can create/search both masters offline;
blank codes stay blank."*

Decisions D1–D7 (§20 and throughout) were approved by the project owner on
2026-09-24 as **final and frozen for Phase 1.5**.

## Inspection performed before writing this plan

1. **Git state:**
   - clean working tree, `HEAD` = `3a499e4`;
   - the authentication removal is `2854fe4` (+ `0783667`);
   - the backup/restore infrastructure restoration is `81242cc` (+ `3a499e4`).
2. **Current code** (`lib/`, `test/`), read directly:
   - `schools` and `awcs` exist in Drift
     (`lib/data/local/tables/school_awc_tables.dart`), with partial unique
     indexes on non-blank official codes and `(district, block)` indexes;
   - there is **no** School/AWC entity, repository, provider, screen or
     route yet;
   - Phase 1.3 established the pattern of a domain entity, an abstract
     repository interface in `lib/domain/repositories/` and a
     `Drift…Repository` in `lib/data/repositories/`, with no providers yet;
   - `appDatabaseProvider` (`lib/data/local/database_provider.dart`) opens
     the database lazily. Before opening, it resolves any interrupted
     restore and removes leftover files. It fails with
     `DatabaseKeyUnavailableException` when the key is unavailable, and
     **nothing in the app currently opens it**;
   - the More tab (`lib/features/more/…/more_screen.dart`) is a
     placeholder;
   - `test/core/router/app_router_test.dart` asserts that **exactly** the
     five tab routes exist;
   - the security-event writer (`lib/data/local/security/security_audit.dart`)
     writes `audit_log` rows with `table_name = 'security_event'`; no
     business-row audit writer exists;
   - `AuditAction` = `INSERT | UPDATE | SOFT_DELETE | RESTORE`.
3. **Authoritative requirements re-read:**
   - [01_PRD.md](01_PRD.md) FR-1 and NFR-1–3;
   - [02_SCREEN_MAP.md](02_SCREEN_MAP.md) screens 18–23;
   - [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §0, §2.2, §3,
     §4 and §5;
   - [06_PROJECT_STRUCTURE.md](06_PROJECT_STRUCTURE.md);
   - [17_SOURCE_DATA_QUALITY_REPORT.md](17_SOURCE_DATA_QUALITY_REPORT.md)
     §4–§5 and rules 5–7;
   - [21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md) §10;
   - [24_PHASE_1_2_REPORT.md](24_PHASE_1_2_REPORT.md) (known prose/DDL
     deviations 3–4).
4. **Schema check:** everything this phase needs already exists.
   **No schema change is required.** §J of the readiness review listed
   nothing blocking.

## 1. Phase objective

Give the team **offline School and AWC master lists** they can search,
filter, add to and correct, with official codes kept exactly as entered
(blank stays blank), records retired by **Active/Inactive** rather than
deleted, possible duplicates shown for a person to judge (never merged),
and every change recorded in `audit_log`. This is the first phase that
writes business data, and the first feature that opens the database.

## 2. Scope

- **School Master:** list with search and filters; detail/edit; add
  (manual); Active/Inactive.
- **AWC Master:** the same.
- **Duplicates:** checks during save, and a "Possible duplicates" review
  screen for each master.
- **Audit:** `audit_log` rows for every School/AWC INSERT and UPDATE, with no
  actor.
- **Database-locked state:** a plain-language message on the master screens,
  with Try again.
- **Navigation:** More → School Master / AWC Master, and their routes.
- **Code:** domain entities, repository interfaces, Drift repositories,
  Riverpod providers and controllers, and tests.

## 3. Explicitly out of scope

- Micro Plan import (Phase 1.6), including `plan_imports`, filling
  `source_plan_awc_code`, import-time deduplication and `data_quality_notes`
  from the parser.
- Visit plans, special/missed/reschedule visits, holidays (1.7).
- Screening sessions and entry (1.8); register photos (1.9); OCR; the AWC
  full form; the referred line list; treatment follow-up; reports and
  exports; sync and cloud.
- **Authentication, users, roles and RBAC enforcement** (deleted; to be
  rebuilt later).
- **Backup/Restore UI** (the infrastructure stays unexposed).
- Staff, Disease Master and referral-configuration screens.
- Running seed data at start-up.
- Any delete action, any merge tool, and any automatic overwrite of
  another record.
- Filling or generating any official code.
- Fuzzy or phonetic matching.
- **Any schema change and any new dependency.**

## 4. Frozen requirements this phase follows

| # | Requirement | Source |
|---|---|---|
| R1 | Primary keys are client-generated UUIDv4 | docs/04 §0 |
| R2 | Official codes are nullable business identifiers, never the database identity. **A blank code stays blank**: never invented, never back-filled | docs/04 §0, PRD FR-1.3, docs/00 §14 |
| R3 | School code uniqueness **only among non-blank codes**; several blanks are valid (enforced by `uq_schools_code`) | docs/04 §2.2, §4 |
| R4 | `official_awc_code` stays NULL unless a genuine government code is supplied. Unique only among non-blank values (`uq_awcs_official_code`) | docs/04 §2.2, §8 |
| R5 | `source_plan_awc_code` is non-authoritative: never identity, never unique. `subcentre_no` is informational | docs/04 §2.2 |
| R6 | Duplicates are surfaced for human review and **never auto-merged** | docs/04 §2.2, docs/17 rules 6 |
| R7 | One master record per school or AWC | PRD FR-1.1, FR-1.2 |
| R8 | Records support **Active/Inactive**; **no hard delete** | PRD FR-1.4, docs/04 §0 |
| R9 | Mutable rows maintain `updated_at` and `row_version`; soft-deleted rows are filtered out in the repository | docs/04 §0, §5, docs/06 |
| R10 | Minimal typing: searchable lists, pickers | PRD product principle, NFR-1 |
| R11 | Fully offline; no data loss | PRD NFR-2, NFR-3 |
| R12 | Feature folders `features/school_master`, `features/awc_master`. Controllers call repositories directly (no use-case class for simple CRUD) | docs/06 |
| R13 | The database-key fail-safe is preserved unchanged | docs/00 §7 |
| R14 | No schema change without a numbered, approved amendment | docs/00 §14 |

## 5. School Master requirements

**Fields:**

| Field (column) | Editable | Rule |
|---|---|---|
| Name (`name`) | Yes | **Required**. Stored trimmed; blank after trimming is refused |
| Official school code (`official_school_code`) | Yes, optional | Stored with leading and trailing whitespace trimmed, otherwise verbatim. **Empty → NULL** (blank stays blank). No format rule is enforced (docs/04 §4 specifies none). **A duplicate non-blank code is a hard save error (D4).** |
| Institution type (`institution_type`) | Yes, optional | Quick-pick **PS / UPS / COM / Blank** (D6, §12) |
| District, Block, Panchayat/Village, Address | Yes, optional | Free text, trimmed; empty → NULL |
| Data-quality notes (`data_quality_notes`) | **Read-only** (shown if present) | Parser-raised flags for human review (docs/04 §2.2). Populated by the Phase 1.6 import, not by manual entry |
| Active (`is_active`) | Yes (toggle) | §9 |
| System fields | Never | `id` (UUIDv4); `created_at`/`updated_at`; `row_version`; `created_by`/`updated_by` = **NULL** (D1); `is_deleted` = false |

**Behaviours:**

- **Create:** a new UUIDv4, `row_version` 1, and one `INSERT` audit row in
  the same transaction.
- **Edit:** change only what the user changed. `updated_at` is set to now,
  `row_version` goes up by 1, and one `UPDATE` audit row is written in the
  same transaction. **If nothing changed, nothing is written.**

## 6. AWC Master requirements

**Fields:**

| Field (column) | Editable | Rule |
|---|---|---|
| Name (`name`) | Yes | **Required**, trimmed |
| Official AWC code (`official_awc_code`) | Yes, optional | Only a genuine government AWC code. Help text: "Leave blank unless you have the official government AWC code". Trimmed; **empty → NULL**; never filled automatically. A duplicate non-blank code is refused by `uq_awcs_official_code`, and shown as a clear save error |
| Subcentre no. (`subcentre_no`) | Yes, optional | Whole number (digits only) or blank |
| Panchayat/Village, Block, District | Yes, optional | Free text, trimmed; empty → NULL |
| Micro Plan AWC code (`source_plan_awc_code`) | **Read-only** (shown if present, labelled "reference only, not an ID") | Non-authoritative. Populated by the Phase 1.6 import only (R5) |
| Data-quality notes | **Read-only** | As for schools |
| Active | Yes (toggle) | §9 |
| System fields | Never | As for schools |

Create and edit behave as for schools, with audit rows for `awcs`.

## 7. Duplicate detection rules (D4)

**Normalization, for comparison only (stored values are not altered beyond
trimming):**

1. trim leading and trailing whitespace;
2. collapse runs of whitespace to one space;
3. compare case-insensitively.

**Nothing else:** no fuzzy or phonetic matching, and no removing
punctuation or look-alike characters.

**Schools:**

- **Hard error:** a non-blank official school code already used by another
  (non-deleted) school. The database also enforces this (`uq_schools_code`),
  so the repository checks first to give a clear message naming the other
  school, and maps any constraint failure to the same error.
- **Possible-duplicate warning:** another school with the same normalized
  name and a different official code (see §20 open point P1 for blank
  codes).

**AWCs:**

- **Possible-duplicate warning:** another AWC whose normalized name,
  normalized panchayat/village and subcentre number all match (see P2 for
  blanks).
- **Hard error:** a duplicate non-blank official AWC code (the schema's
  unique index).

**Both masters:**

- Checks run against **non-deleted** records, active and inactive (P3), and
  never against the record being edited.
- **During save:** if possible duplicates exist, a dialog lists them (name,
  code, village, active state) with **Save anyway** and **Cancel**. Nothing is
  merged, linked or overwritten.
- **Review screen:** "Possible duplicates" for each master lists groups of
  records that match the rule. It is read-only; tapping a record opens its
  detail. There is no merge or delete action.

## 8. Search/filter behavior

- **Search box (both masters):** a case-insensitive substring match on
  **name or official code**. Implemented with SQLite `LIKE`, with `%`, `_`
  and the escape character escaped in user input. There is no trigram index
  (it is Postgres-only, per `school_awc_tables.dart`).
- **Filters (docs/02 screens 18 and 21):**
  - **District** and **Block**: pick lists built from the distinct values
    already stored (no invented values). Block values narrow to the chosen
    district.
  - **Status**: **Active** (default), Inactive or All (P6).
- **Sort** by name (case-insensitive), then official code.
- **Soft-deleted rows** never appear.
- **Performance:** the source volume is about 149 schools and 196 AWC rows
  before deduplication. Plain queries are enough; the list uses lazy
  building.

## 9. Active/Inactive behavior (D3)

- **Detail screen:** a clear **Active / Inactive** switch with a short
  confirmation ("Mark as inactive? It stays in the records and can be
  reactivated.").
- **Effect of a change:** an `UPDATE` of `is_active`, with `updated_at`,
  `row_version` and one `UPDATE` audit row.
- **Inactive records** stay searchable (Status filter), are shown with an
  "Inactive" label, and are editable.
- **No delete button or action exists** in this phase.
  - The repository keeps its soft-delete read filter (`is_deleted = false`).
  - No soft-delete operation is exposed in the UI.
  - No soft-delete write method is added to the repository in this phase
    (nothing would call it).

## 10. Audit behavior (D1)

- **Scope:** every School/AWC **INSERT** and **UPDATE** (including an
  Active/Inactive change) writes exactly one `audit_log` row, **in the same
  database transaction** as the change. If either fails, neither is saved.
- **Row contents:**

| Column | Value |
|---|---|
| `id` | new UUIDv4 |
| `table_name` | `schools` or `awcs` |
| `record_id` | the School/AWC `id` |
| `action` | `INSERT` or `UPDATE` |
| `changed_fields` | UPDATE: JSON list of the column names that changed; INSERT: NULL |
| `old_values` | UPDATE: JSON of the changed columns' previous values; INSERT: NULL |
| `new_values` | INSERT: JSON of all business columns; UPDATE: JSON of the changed columns' new values |
| `actor_user_id` | **NULL** (no authentication exists; no invented identity) |
| `actor_device_id` | NULL |
| `occurred_at` | now (UTC) |

- **Business columns** are the entity fields in §5/§6 (snake_case column
  names). System and attribution columns are not repeated.
- **Separation:** business audit rows use the table names `schools`/`awcs`,
  never `security_event`, so they stay separate from security events.
- **No other writes:** there is no audit row for reads or searches, and no
  `SOFT_DELETE`/`RESTORE` audit in this phase (no such action exists).
- **Attribution later:** real actor attribution (`actor_user_id`,
  `created_by`, `updated_by`) will be added when authentication is rebuilt.

## 11. Database-locked behavior (D5)

- **When:** the master screens are the first feature to read
  `appDatabaseProvider`. If it fails with `DatabaseKeyUnavailableException`,
  the screen shows:

  > **Your data is locked.** The app could not unlock the data saved on this
  > phone. Your data has **NOT been deleted**.
  > [**Try again**]

  It also shows a short reference (the reason name, never key material).
- **Try again** invalidates `appDatabaseProvider` and re-reads it.
- **No Restore button**, and no restore or backup UI. Backup/Restore UI stays
  out of scope.
- **Other open failures** (for example, the interrupted-restore resolution
  could not complete) show "Could not open the local data. Nothing has been
  deleted. Try again". This never suggests deleting data or reinstalling.
- **The database-key fail-safe is unchanged.** Nothing in this phase
  generates, replaces or deletes a key.
- **Implementation:** one shared widget, `DatabaseStateView`, handles the
  `AsyncValue` loading and error states for both masters.

## 12. Institution type behavior (D6)

- **Control:** an optional quick-pick of **PS**, **UPS**, **COM** and
  **Blank**. Blank stores NULL. No other values can be chosen or typed.
- **Existing values:** a value outside the four options that is already
  stored (possible only through a later import) is displayed as stored and
  kept unless the user picks a new value. It is never silently rewritten.

## 13. Repository/data-layer design

Follows the Phase 1.3 pattern (docs/06: entities in `domain/`, interfaces in
`domain/repositories/`, Drift implementations in `data/repositories/`).

| File | Purpose |
|---|---|
| `lib/domain/entities/school.dart` | `School` (id, officialSchoolCode, name, institutionType, district, block, panchayatVillage, address, dataQualityNotes, isActive, createdAt, updatedAt, rowVersion) |
| `lib/domain/entities/awc.dart` | `Awc` (id, officialAwcCode, sourcePlanAwcCode, name, subcentreNo, panchayatVillage, block, district, dataQualityNotes, isActive, createdAt, updatedAt, rowVersion) |
| `lib/domain/entities/master_record_input.dart` | `SchoolInput`, `AwcInput`: the editable fields only, with the trimming and empty-to-NULL rules in one place |
| `lib/domain/repositories/school_repository.dart` | `SchoolRepository` (below) |
| `lib/domain/repositories/awc_repository.dart` | `AwcRepository` (same shape) |
| `lib/data/repositories/drift_school_repository.dart` | Drift implementation |
| `lib/data/repositories/drift_awc_repository.dart` | Drift implementation |
| `lib/data/local/audit/business_audit_writer.dart` | Writes the §10 rows; used inside the repositories' transactions |
| `lib/core/utils/text_normalize.dart` | The §7 normalization (one function, shared by both masters) |
| `lib/core/errors/failure.dart` (edit) | Adds `NameRequiredFailure`, `DuplicateOfficialCodeFailure` (with the conflicting record's id and name), `MasterRecordNotFoundFailure` |

**Repository interface (School; the AWC one is equivalent):**

- `Future<List<School>> search({String query, String? district, String? block, ActiveFilter status})`
- `Future<School?> getById(String id)` (non-deleted only)
- `Future<List<String>> districts()` and `Future<List<String>> blocks({String? district})`
  (distinct stored values)
- `Future<List<School>> possibleDuplicatesFor(SchoolInput input, {String? excludeId})`
- `Future<List<List<School>>> possibleDuplicateGroups()`
- `Future<School> create(SchoolInput input)`: throws `NameRequiredFailure` or
  `DuplicateOfficialCodeFailure`
- `Future<School> update(String id, SchoolInput input)`: the same failures,
  plus `MasterRecordNotFoundFailure`; no write if nothing changed
- `Future<School> setActive(String id, {required bool active})`

**Rules:**

- The repositories are the **only** place that writes `schools`/`awcs`, and
  they always write the audit row in the same transaction.
- There is **no** delete method.
- Duplicate checks never write anything.

## 14. UI/screen list (docs/02 §Master Data)

| # (docs/02) | Screen | Contents |
|---|---|---|
| 18 | **School Master List** | Search box; District, Block and Status filters; results list (name, code or "No code", village, Inactive label); **Add school** button; **Possible duplicates** entry |
| 19 | **School Detail / Edit** | All §5 fields, read-only fields labelled; **Edit**, then **Save**; Active/Inactive switch |
| 20 | **Add School (manual)** | §5 editable fields; save with duplicate checks (§7) |
| — | **School — Possible duplicates** | Read-only groups (§7) |
| 21 | **AWC Master List** | As 18, for AWCs |
| 22 | **AWC Detail / Edit** | §6 |
| 23 | **Add AWC (manual)** | §6 editable fields; duplicate checks |
| — | **AWC — Possible duplicates** | Read-only groups |
| — | **More** (updated) | A "Masters" section with **School Master** and **AWC Master** entries. No other entries are added |

All screens use the shared `DatabaseStateView` (§11), and form fields use
plain text keyboards. The Add and Edit forms share one form widget per
master.

## 15. Navigation/routes

Nested under the existing **More** branch of the shell (no new tab):

| Route | Screen |
|---|---|
| `/more/schools` | School Master List |
| `/more/schools/new` | Add School |
| `/more/schools/duplicates` | School — Possible duplicates |
| `/more/schools/:id` | School Detail / Edit |
| `/more/awcs` | AWC Master List |
| `/more/awcs/new` | Add AWC |
| `/more/awcs/duplicates` | AWC — Possible duplicates |
| `/more/awcs/:id` | AWC Detail / Edit |

> **As implemented** (per the implementation instruction; docs/36 §5):
> `/add` replaces `/new`, and editing has its own `/:id/edit` route, for
> both masters.

- **No redirects or guards**, since authentication is deleted (D2).
- **Constants** go in `Routes`.
- **Router test:** `test/core/router/app_router_test.dart` changes from
  "exactly five routes" to "the five tab routes plus exactly these master
  routes, and no authentication route".

## 16. Provider/controller structure (Riverpod 3, as used in the codebase)

- **Repository providers:** `schoolRepositoryProvider` and
  `awcRepositoryProvider` are `FutureProvider`s built from
  `appDatabaseProvider`, in `features/<master>/…/providers.dart`.
- **List controller:** `SchoolListController` / `AwcListController`
  (`AsyncNotifier`) hold the search text and filters, and expose results.
  Search is debounced by about 300 ms.
- **Detail:** `schoolDetailProvider(id)` / `awcDetailProvider(id)`
  (`FutureProvider.family`).
- **Form controllers:** `SchoolFormController` / `AwcFormController` run
  validation, the duplicate check and the save flow, and on success refresh
  the list and detail providers.
- **Duplicates:** `schoolDuplicateGroupsProvider` /
  `awcDuplicateGroupsProvider`.
- **Test overrides:** widget tests override `appDatabaseProvider` with an
  in-memory database (as existing tests do with `openTestDatabase()`), so
  they never touch path_provider or the Keystore.

## 17. Test plan

**Repository tests (in-memory Drift):**

- **Create:**
  - a UUIDv4 id, `row_version` 1 and timestamps are set;
  - `created_by`/`updated_by` are NULL;
  - a name is required;
  - fields are trimmed.
- **Blank codes:**
  - an empty or whitespace code is stored as NULL, never generated;
  - **several schools with blank codes** are allowed.
- **Duplicate codes:**
  - a duplicate non-blank school code gives `DuplicateOfficialCodeFailure`
    naming the other school, and nothing is written;
  - the same when the unique index is hit directly;
  - AWC official code: optional, blank allowed repeatedly, a duplicate
    non-blank code is refused.
- **Reference fields:**
  - `source_plan_awc_code` is never set by manual create or update, and is
    not unique;
  - the AWC subcentre number is an integer or NULL.
- **Update:**
  - only changed fields are written;
  - `updated_at` advances and `row_version` goes up by 1;
  - no change means no write and no audit row.
- **Active/Inactive:** round trip; inactive rows appear only in the matching
  filter.
- **Deleted rows:** soft-deleted rows (inserted directly) never appear in
  search, `getById`, filters or duplicate checks.
- **Search:**
  - case-insensitive substring on name and code;
  - `%` and `_` in the query are taken literally;
  - district and block filters use distinct stored values only;
  - results are sorted.
- **Duplicates (§7):**
  - schools: same normalized name with a different code warns (case,
    spacing and surrounding whitespace variants), with no fuzzy match (for
    example `LAGAUN` vs `LAGON` does **not** match);
  - AWCs: name + village + subcentre match warns; a different subcentre
    does not;
  - checks exclude the record itself;
  - groups are correct;
  - **nothing is ever merged or modified**.
- **Audit:**
  - exactly one row per INSERT and UPDATE, with the correct
    `table_name`, `record_id`, `action`, `changed_fields` and old/new values;
  - `actor_user_id` is NULL;
  - no audit row when a save fails or nothing changed;
  - the audit row is written in the same transaction (a forced failure
    leaves neither the change nor the audit row).

**Encrypted real-file test:** create a school and an AWC in an encrypted
file database, reopen it, read them back, and check their audit rows.

**Widget tests** (the app with `appDatabaseProvider` overridden):

- More shows School Master and AWC Master; each list opens.
- Search and filters narrow the list.
- Add school (with a blank code), save, and it appears showing "No code".
- A duplicate code shows the hard error.
- A same-name save shows the warning dialog: **Cancel** saves nothing;
  **Save anyway** saves a separate record.
- Edit, save, and the change is visible.
- Deactivate (confirmation), then Inactive filter, then reactivate.
- There is **no delete control** anywhere.
- The Institution type picker offers exactly PS, UPS, COM and Blank.
- The Possible duplicates screen lists groups and has no merge or delete
  actions.
- AWC equivalents of these checks.

**Database-locked tests:** `appDatabaseProvider` fails with
`DatabaseKeyUnavailableException`, so the locked message, the NOT deleted
wording and Try again appear, and there is no Restore button. **Try again**
re-reads the provider. The generic open-failure message is also shown for
other errors.

**Router tests:** the master routes exist; there is no authentication route;
the app still starts on Home.

**Regression:** all **204** existing tests stay green, with the router test
updated as in §15.

## 18. Acceptance criteria

1. Both masters can be **created, searched, filtered and edited offline**.
2. **Blank official codes stay blank** (NULL); none is ever generated.
3. A **duplicate non-blank official code** cannot be saved (clear message).
4. **Possible duplicates** (D4 rules exactly) are shown during save and on
   the review screens. **Nothing is ever auto-merged or overwritten.**
5. **Active/Inactive** works; there is **no delete action** and no hard
   delete.
6. **Every INSERT and UPDATE writes one `audit_log` row**, atomically, with
   a NULL actor.
7. **A locked database** shows the D5 message with Try again and no Restore
   button. The key fail-safe is unchanged.
8. The **Institution type** options are exactly PS, UPS, COM and Blank.
9. **No schema change, no new dependency, no authentication, no RBAC
   enforcement, and no Backup/Restore UI**, and none of the §3 items.
10. All tests pass (204 existing + new), `flutter analyze` is clean, and the
    release APK builds.
11. A report (`docs/36_PHASE_1_5_REPORT.md`) and a Master Plan update follow
    docs/00 §13.

## 19. Implementation sequence

Each step is followed by its tests before the next begins.

1. **Normalization and failures:** `text_normalize.dart`, the new failures,
   and unit tests.
2. **Entities and interfaces:** entities, input objects and repository
   interfaces.
3. **Audit writer:** `business_audit_writer.dart` and tests.
4. **School repository:** `DriftSchoolRepository` (search, filters, get,
   create, update, set active, duplicates) and tests, including the
   encrypted-file round trip.
5. **AWC repository:** `DriftAwcRepository` and tests.
6. **Providers and controllers.**
7. **Shared database state view:** `DatabaseStateView` (§11) and its tests.
8. **School screens:** list, detail/edit, add, duplicate dialog and review
   screen, with widget tests.
9. **AWC screens:** the same, with widget tests.
10. **Navigation:** the More "Masters" entries, routes, and the router test
    update.
11. **Checks:** full suite, `flutter analyze`, release APK build, and hygiene
    and PII scans (synthetic test data only; no real school codes, because
    source codes are real government identifiers).
12. **Commit 1** (implementation and tests). **Commit 2** (report
    `docs/36`, Master Plan update per §13, and the doc-staleness notes the
    readiness review listed). Then stop for review.

## 20. Known deviations caused by deferred authentication

| # | Frozen/future requirement | Phase 1.5 state (approved) | Resolved by |
|---|---|---|---|
| DV1 | docs/04 §5: `created_by`/`updated_by` "always a real user" | **NULL** on every School/AWC row (D1) | Authentication rebuild (docs/00 §10 #28) |
| DV2 | docs/04 §5: an audit row per change, attributed to a user | Audit rows written with **`actor_user_id` NULL** (D1) | Same |
| DV3 | docs/04 §3 RBAC: School/AWC create/edit is ADMIN and MO only; TEAM_MEMBER view/search | **Not enforced.** The available user can create and edit. No stand-in roles or fake authentication (D2) | Same |
| DV4 | PRD NFR-5: access limited to authenticated, authorized users | No access control | Same (production blocker #28) |
| DV5 | docs/00 §4 / D5: the locked-data screen originally offered Restore | Locked message **without** Restore (D5) | Backup/Restore UI (#29) |
| — | Pre-existing, not caused by auth: docs/04 §0 names `deleted_by`/`deleted_at`, which no table has (docs/24 deviation 4) | Unchanged; no soft-delete action in this phase | Future schema amendment, if ever needed |

**Open plan-level points** (each follows from D4, D6 or docs/02; each is
proposed here for confirmation at implementation approval):

- **P1:** two schools with the same normalized name where **one or both
  codes are blank** are treated as possible duplicates. "A different
  official code" is read as "not the same non-blank code", since two
  identical non-blank codes cannot coexist.
- **P2:** for AWCs, a blank village or subcentre number matches another
  blank (blank equals blank).
- **P3:** duplicate checks include **inactive** records (non-deleted only).
- **P4:** the official school code format (UDISE-style 10 digits) is **not
  validated**, because docs/04 §4 defines no such rule.
- **P5:** `data_quality_notes` and `source_plan_awc_code` are
  **read-only** in manual screens; they are populated by the Phase 1.6
  import.
- **P6:** the lists default to the **Active** status filter.

## 21. Risks and mitigations

| Risk | Mitigation |
|---|---|
| **First feature to open the database:** the start-up restore recovery, key fail-safe and journal flush run for the first time outside tests | A locked-state UI, the real-file encrypted test, and the fail-safe left unchanged. Widget tests override the provider, so they never touch the platform |
| **Unique-constraint error mapping** depends on the SQLite error | A repository pre-check gives the friendly message; the constraint is the final guard; both paths are tested |
| **Manual records vs the Phase 1.6 import:** manually created schools and AWCs may later meet imported ones with the same code or name | Phase 1.6 must reuse this repository and the same §7 normalization. An existing code means **match, not duplicate** (recorded as an input to the 1.6 plan) |
| **Real government codes in tests** | Only synthetic codes and names in tests and fixtures; hygiene scan before commit |
| **The `LIKE` search** could misbehave on special characters | Escaping, with tests |
| **Scope creep** into import, visits or auth | §3 list; review against it before each commit |
| **Release tree-shaking** will now include the database layer (it was previously unused) | Release APK build and a size and contents check in step 11 |

## 22. Definition of Done

- [x] §18 acceptance criteria 1–11 all met, with evidence in the report
- [x] New tests for every §17 item; all tests pass; `flutter analyze` clean;
      release APK builds
- [x] No schema, dependency, authentication or Backup/Restore UI change
      (verified by diff)
- [x] Deviations DV1–DV5 documented in the report and the Master Plan
- [x] Plan points P1–P6 implemented as confirmed at approval
- [x] Master Plan updated per docs/00 §13 (status, §4 feature map, §5
      roadmap, results, commits, §10 and §11 changes)
- [x] Hygiene and PII scan clean (no real codes, names or personal data in
      Git)
- [x] Phase 1.5 left **awaiting user review/closure**, and Phase 1.6 not
      started

## Summary for approval

- **Phase 1.5** delivers School and AWC masters (list, search, filter, add,
  edit, Active/Inactive), with duplicate warnings and review screens, an
  `audit_log` row for every change, and a plain locked-data message. It is
  fully offline.
- **No schema change, no new dependency, no authentication, and no
  Backup/Restore UI.**
- **To confirm at implementation approval:** points P1–P6 (§20).
