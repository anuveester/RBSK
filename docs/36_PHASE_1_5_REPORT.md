# Phase 1.5 — School/AWC Master CRUD + Search (Implementation Report)

**Status: IMPLEMENTED — awaiting user review/closure.** Phase 1.6 has not
started.

Plan: [35_PHASE_1_5_PLAN.md](35_PHASE_1_5_PLAN.md), with decisions D1–D7
(final and frozen) and plan points P1–P6, as approved on 2026-09-24.
Implementation commit: `090def5`.

## 1. What was built

### School Master (`/more/schools`)
- **List** of Active schools by default, sorted by name. Each row shows the
  name, the code or "No code", the village and block, and an Inactive label.
- **Search** covers the name or the School Code. It is case-insensitive
  substring search; `%` and `_` are taken literally. There is no fuzzy
  matching.
- **Filters:** District, Block (narrowed by the chosen district) and
  Status (Active / Inactive / All). Filter options are the stored values.
- **Add / Edit:**
  - Name is required.
  - School Code is optional. A blank code is stored as NULL, never
    generated, and never format-validated (P4).
  - Institution type is a quick pick of PS / UPS / COM / Blank (D6).
  - District, Block, Panchayat / Village and Address are optional.
- **Detail:**
  - Shows all fields and an **Active** switch with a confirmation.
  - Shows **Edit**.
  - Micro Plan data-quality notes appear read-only (P5).
  - There is no delete anywhere (D3).
- **Possible duplicates** screen: groups of same-name schools. It offers no
  merge and no delete.

### AWC Master (`/more/awcs`)
- These screens work the same way as the School Master.
- Search covers the name, the official AWC Code or the village.
- **Add / Edit** fields:
  - Name is required.
  - Panchayat / Village.
  - Subcentre no. (digits only).
  - AWC Code (official), optional and never generated.
  - Block and District.
- **The Micro Plan AWC code** (`source_plan_awc_code`) and notes are shown
  on the detail screen only, under "From the Micro Plan (reference only,
  not an ID; cannot be edited)". The form has no field for them, and the
  repository never writes them (P5).

## 2. Duplicate rules (D4, P1–P3), as implemented

Normalization (`normalizeForMatch`) trims, collapses whitespace
(including tabs and new lines) and ignores case. There is no fuzzy,
phonetic or AI matching. Values are stored as typed, apart from
surrounding whitespace.

| Case | Result |
|---|---|
| School: the same non-blank School Code | **Blocked.** "School Code already exists. This school is already in the master: <name>." The repository pre-checks, and the unique index is the final guard; a raw `UNIQUE` error is never shown |
| School: the same normalized name, with a different code or with one or both codes blank | "Possible duplicate found": the user can **Cancel** or **Save anyway** |
| AWC: the same non-blank official AWC Code | **Blocked** (same message pattern) |
| AWC: the same normalized name + village + subcentre (blank matches blank) | "Possible duplicate found" |
| Inactive records | Included in every check |
| Soft-deleted rows (none can be created in Phase 1.5) | Excluded from search and from warnings. Still counted by the code check, because the unique index covers them |
| Editing a record | The record is never its own duplicate. The warning is re-checked only if the name (School) or the name + village + subcentre (AWC) changed |

**Nothing is ever merged or overwritten.** "Save anyway" creates a
separate record.

## 3. Audit (D1)

`BusinessAuditWriter` writes **exactly one `audit_log` row** for every
School or AWC INSERT and UPDATE. That includes Active/Inactive changes,
which are audited as UPDATE. Each row has:

- `table_name` (`schools`/`awcs`), `record_id` and `action`;
- `changed_fields`, `old_values` and `new_values` as JSON with column
  names;
- `occurred_at` in UTC;
- **`actor_user_id` NULL**. `created_by`/`updated_by` stay NULL. No user is
  invented.

The row is written **inside the same `db.transaction`** as the change. A
test with a failing audit writer proves the change is rolled back.

- An edit writes only the changed columns and advances `updated_at` and
  `row_version`.
- Saving with no change writes nothing and adds no audit row.

## 4. Locked database (D5)

- The School and AWC screens use `DatabaseStateView` /
  `DataUnavailableMessage`.
- **Locked key:** "Your data is locked right now." / "Your data is NOT
  deleted." with **Try again**.
- **Any other open failure:** "Your data could not be opened right now." /
  "Your data is NOT deleted."
- A failed save shows "Your data is locked right now. Your data is NOT
  deleted. Try again."
- There is **no Restore button** and no technical detail.
- Try again re-opens the database once.
- The key fail-safe is unchanged.

## 5. Routes

Nested under the More branch. There are no guards or redirects.

| Route | Screen |
|---|---|
| `/more/schools` | School list |
| `/more/schools/add` | Add school |
| `/more/schools/duplicates` | Possible duplicate schools |
| `/more/schools/:id` | School detail |
| `/more/schools/:id/edit` | Edit school |
| `/more/awcs` | AWC list |
| `/more/awcs/add` | Add AWC |
| `/more/awcs/duplicates` | Possible duplicate AWCs |
| `/more/awcs/:id` | AWC detail |
| `/more/awcs/:id/edit` | Edit AWC |

The More screen has a new **Masters** section with "School Master" and
"AWC Master".

The router test now expects the five tabs plus exactly these ten routes.
It also checks that no login, setup, PIN, backup or restore route exists.

## 6. Files

- **Domain:**
  - `lib/domain/entities/school.dart`, `awc.dart` and
    `master_list_query.dart`;
  - `lib/domain/repositories/school_repository.dart` and
    `awc_repository.dart`.
- **Data:**
  - `lib/data/repositories/drift_school_repository.dart`,
    `drift_awc_repository.dart` and `master_query_helpers.dart`;
  - `lib/data/local/audit/business_audit_writer.dart`;
  - `lib/data/local/sqlite_errors.dart`.
- **Core:**
  - `lib/core/utils/text_normalize.dart`;
  - `lib/core/widgets/database_state_view.dart` and
    `master_widgets.dart`;
  - new failures in `lib/core/errors/failure.dart`;
  - routes in `lib/core/router/routes.dart` and `app_router.dart`.
- **Features:**
  - `lib/features/school_master/…` and `lib/features/awc_master/…`
    (providers; list, detail, form and duplicates screens);
  - the More screen's Masters entries.
- **Changed:** `lib/data/local/database_provider.dart` — no automatic retry
  (§8, deviation 2).
- **Tests:**
  - `test/core/utils/text_normalize_test.dart`;
  - `test/data/repositories/school_repository_test.dart`,
    `awc_repository_test.dart` and `master_encrypted_roundtrip_test.dart`;
  - `test/features/school_master/school_master_ui_test.dart`;
  - `test/features/awc_master/awc_master_ui_test.dart`;
  - `test/features/masters/locked_database_ui_test.dart`;
  - `test/support/master_app.dart`;
  - `test/core/router/app_router_test.dart` (updated).

## 7. Verification

| Check | Result |
|---|---|
| `flutter test` | **277 passed, 0 failed, 0 skipped.** 204 before; 73 new |
| `flutter analyze` | **No issues found** |
| `flutter build apk --release` | **Built:** `build/app/outputs/flutter-apk/app-release.apk`, 58.8 MB. The previous build was 51.9 MB; the increase is because the database layer is now reachable from the UI and is no longer tree-shaken out |
| Schema | Unchanged: `schemaVersion` 1, 28 tables. No table, column, index, constraint or migration changes. `pubspec.yaml`/`pubspec.lock`, `android/` and `lib/data/local/tables/` are untouched |
| Authentication / RBAC | None added. No login, PIN, roles, actor selection or fake user |
| Backup/Restore UI | None added. No Backup or Restore button, route or screen |
| Delete | No delete action in the UI. The repositories have no delete method and never set `is_deleted` |
| PII / hygiene | Tests use synthetic names and codes only ("Test School Alpha", `SYN-0001`, `SYN-AWC-01`, `PLAN-SYN-7`). No 8+ digit numbers appear in any new file. No `reference_materials/`, database files, APKs or secrets were committed |

**New tests (73):**
- Normalization: 7.
- School repository: 29. These cover:
  - create and read, code rules and unique-index mapping;
  - updates and `row_version`, Active/Inactive;
  - search, escaping, filters and soft-deleted rows;
  - D4 duplicates;
  - D1 audit, including transaction rollback.
- AWC repository: 16.
- Encrypted-file round trip: 1.
- School UI: 8. List, add with a blank code, the PS/UPS/COM/Blank chips,
  name required, duplicate-code error, the possible-duplicate dialog
  (Cancel / Save anyway), search and filters, edit, Active/Inactive, no
  delete, and the duplicates screen.
- AWC UI: 8. The same set plus the Micro Plan code being read-only and
  kept on edit, and the name + village + subcentre rule.
- Locked-database UI: 3. The locked message on both masters, Try again,
  and the generic message.
- Router: 1 more.

**Not done:** no real-device test was run for Phase 1.5. This is the first
feature that opens the encrypted database from the UI on a phone (docs/35
§21, first risk).

## 8. Deviations from the plan

1. **Route shapes.** The implementation instruction specified `/add` and
   `/:id/edit`. The plan (§15) had `/new` and a combined detail/edit
   route. The implementation follows the instruction.
2. **No automatic retry of the database provider or the master
   providers.**
   - `appDatabaseProvider` and every School/AWC provider now use
     `retry: noAutomaticRetry`.
   - Riverpod 3's default retry would re-open a locked database up to 10
     times, recording a journal event each time.
   - Because awaiting `appDatabaseProvider.future` rethrows the original
     exception, each dependent provider would also retry it for about 40
     seconds. The user would see a spinner instead of the D5 message.
   - Now only **Try again** retries (D5). This change touches the existing
     `database_provider.dart`, which is outside the feature folders.
3. **Non-lazy layouts.** The forms and detail screens use
   `SingleChildScrollView` + `Column` instead of a lazy `ListView`. With a
   lazy list, fields scrolled out of view were not validated, and a detail
   page could lose its top rows after navigation.
4. **Stored text** is trimmed only. Inner spacing and case are kept as
   typed; normalization is used for matching only.
5. **DV1–DV5** (docs/35 §20) apply as approved:
   - NULL `created_by`/`updated_by`/`actor_user_id`;
   - no RBAC;
   - no access control;
   - no Restore on the locked screen.

## 9. Acceptance criteria (docs/35 §18)

| # | Criterion | Result |
|---|---|---|
| 1 | Create, search, filter and edit both masters offline | Met (UI + repository tests) |
| 2 | Blank codes stay blank; none generated | Met |
| 3 | A duplicate non-blank code is blocked with a clear message | Met |
| 4 | Possible duplicates are shown on save and on the review screens; never merged | Met |
| 5 | Active/Inactive works; no delete | Met |
| 6 | One atomic audit row per INSERT/UPDATE, NULL actor | Met |
| 7 | Locked database: D5 message, Try again, no Restore; fail-safe unchanged | Met |
| 8 | Institution type is exactly PS, UPS, COM, Blank | Met |
| 9 | No schema, dependency, auth, RBAC or Backup/Restore UI change | Met |
| 10 | All tests pass, analyze is clean, APK builds | Met (277/277) |
| 11 | Report and Master Plan update | This document + docs/00 |

## 10. Inputs for later phases

- **Phase 1.6 (Micro Plan import)** must reuse these repositories and the
  same normalization. An existing official code means *match*, not
  *duplicate*. The import is the only writer of `source_plan_awc_code` and
  `data_quality_notes`.
- **Authentication rebuild (docs/00 §10 #28)** must fill `created_by`,
  `updated_by` and `actor_user_id`, and enforce the docs/04 §3 RBAC for
  master edits.
