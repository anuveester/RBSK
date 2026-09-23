# Phase 1.3 — Reference/Seed Data + Minimal Read Layer (Implementation Plan)

**Status: awaiting approval. No code, dependency, or schema change made yet.**

Scope reference: [21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md) §10, step 1.3
("Seed data: financial years, `disease_master` [Job Aid rows], `referral_destinations`
+ contexts [School 3, AWC 5 + routing], staff/team from the Micro Plan" — exit
criterion: *"Seeds load offline; referral picker returns the right list per
context"*).

## Inspection performed before writing this plan

1. Re-read [21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md) in full, including the
   binding approval conditions and §10's Phase 1 sequence.
2. Re-read [23_PHASE_1_1_REPORT.md](23_PHASE_1_1_REPORT.md) and
   [24_PHASE_1_2_REPORT.md](24_PHASE_1_2_REPORT.md).
3. Enumerated the current project tree directly (`lib/`, `test/`) rather than
   assuming — `lib/data/repositories/` and `lib/data/remote/` are still empty
   (`.gitkeep` only); no repository/DAO code exists anywhere yet.
4. Confirmed git state: clean, 6 commits, `1c071f6` is `HEAD`.
5. Re-verified the frozen schema directly against
   [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §2 (28 tables, per the
   now-corrected count) — the four tables this phase writes to
   (`financial_years`, `disease_master`, `referral_destinations`,
   `referral_destination_contexts`) plus `staff`/`staff_assignments` all exist
   exactly as needed; no column is missing for what this phase seeds.
6. **Re-derived the `disease_master` seed count directly from source**, rather than
   trusting the "29" figure carried in three prior documents
   ([04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §2.4,
   [16_PHASE0_DATABASE_REVIEW.md](16_PHASE0_DATABASE_REVIEW.md) (×2), and
   [21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md) §10's own Phase 1.3 row) —
   **found a second miscount, of the same kind as the 24-vs-28 table count.**
   See §7 below. Flagged, not silently carried forward into this plan or fixed
   without your sign-off.

## 1. Objective

Make the four reference/configuration tables that every later screen depends on
**populated, correct, idempotent, and provably queryable offline** — with no UI,
no auth, and no business-transaction tables touched. This is the first phase that
writes real data into the frozen schema and the first phase with any read
(repository-style) code, kept deliberately narrow: seed + read, nothing else.

## 2. Exact feature scope

**In scope:**
- Idempotent seeding of `financial_years`, `disease_master`,
  `referral_destinations` + `referral_destination_contexts`, `staff` +
  `staff_assignments`.
- A minimal, typed read layer (repository-style) over exactly those four
  domains, sufficient to prove the seed data is usable — not a general-purpose
  repository framework for the whole app.
- Tests proving: seeding is idempotent (running it twice does not duplicate or
  error), every seeded row matches its documented source, and the
  School-vs-AWC referral query returns the right list per context/category
  (the phase's own stated exit criterion).

**Not in scope:** anything listed in §12.

## 3. Files/modules expected to be created or modified

```
lib/data/local/seed/
  seed_runner.dart                       # orchestrates all seeders in one
                                          # transaction; idempotent — checks
                                          # "does this row already exist" before
                                          # inserting, never duplicates on
                                          # re-run
  financial_year_seed_data.dart          # FY 2025-26 row (source-confirmed)
  disease_master_seed_data.dart          # Job Aid codified findings (count TBD
                                          # pending §7)
  referral_destination_seed_data.dart    # 3 School + 5 AWC destinations +
                                          # context/routing rows
  staff_seed_data.dart                   # 4 Team-B members, names/designation/
                                          # qualification only — NO phone
                                          # numbers (kept unseeded; see §9)

lib/data/repositories/                   # FIRST real content in this
                                          # directory (currently .gitkeep only)
  disease_master_repository.dart
  referral_destination_repository.dart
  staff_repository.dart
  financial_year_repository.dart

lib/domain/entities/                     # plain Dart read-model classes so
                                          # repositories don't leak Drift's
                                          # generated row types past the data
                                          # layer (matches
                                          # docs/06_PROJECT_STRUCTURE.md)
  disease_finding.dart
  referral_destination.dart
  staff_member.dart
  financial_year.dart

test/data/local/seed/
  seed_runner_test.dart                  # idempotency, row counts, content
test/data/repositories/
  disease_master_repository_test.dart
  referral_destination_repository_test.dart
  staff_repository_test.dart
```

**No file under `lib/core/`, `lib/features/`, or the existing
`lib/data/local/tables/*.dart` is modified** — this phase adds data and a thin
read layer on top of the schema Phase 1.2 already froze and built.

## 4. Database tables used

| Table | Operation | Notes |
|---|---|---|
| `financial_years` | INSERT (idempotent) | FY 2025-26 confirmed from the source Micro Plan |
| `staff` | INSERT (idempotent) | 4 Team-B members |
| `staff_assignments` | INSERT (idempotent) | one open-ended assignment per member, per the source (no transfer evidence in FY2025-26 — docs/16 §8) |
| `disease_master` | INSERT (idempotent) | Job Aid codified findings — count to be confirmed, §7 |
| `referral_destinations` | INSERT (idempotent) | 3 School + 5 AWC = 8 rows |
| `referral_destination_contexts` | INSERT (idempotent) | School: 3 rows (all-category). AWC: category-routed per docs/20 §3 |

No other table is read or written.

## 5. Migration required?

**No.** This phase writes rows, not schema. `schemaVersion` stays `1`. No
`ALTER TABLE`, no new column, no new table. If implementation reveals a need for
one, that is a **SCHEMA CHANGE REQUIRING APPROVAL** and must stop and be reported
separately, per your standing instruction — not something this plan authorizes
in advance.

## 6. Dependencies required

**None.** Every package this phase needs is already in `pubspec.yaml` from
Phase 1.2 (`drift`, `flutter_riverpod`). Deliberately **not** adding `uuid`:
reference/seed data gets **stable, deterministic string IDs**
(e.g. `'fy-2025-26'`, `'disease-11'`, `'ref-dest-phc-chc'`,
`'staff-rajni-pratap'`) rather than random UUIDs. This is a better fit for seed
data specifically — it makes "does this row already exist" a trivial primary-key
lookup (the basis for idempotency) and keeps seeded rows human-readable in a
debugger — and it means this phase needs no new dependency at all, consistent
with your instruction not to add any this turn.

## 7. Seed/reference data required — and a discrepancy found

### Financial year
FY 2025-26 (01 Apr 2025 – 31 Mar 2026), confirmed from the source Micro Plan
header. **Open question, not decided here:** today's date is in FY 2026-27, which
has no source plan analyzed yet (docs/17 notes the register sample's April/May
2026 dates belong to this later FY). Recommend seeding 2025-26 only (the FY
that's actually source-confirmed) and handling "what's the current FY" as
application logic in a later phase (compute/insert on demand) rather than
pre-seeding a year with no confirmed source data — flagged for your
confirmation before implementation, not decided unilaterally here.

### Staff
4 Team-B members, names/designation/qualification only (docs/04
[reference_identity_tables.dart] and docs/16 §8) — **contact numbers
deliberately excluded**, matching the redaction already applied to
version-controlled docs in Phase 0.6. If phone numbers are wanted in the app
later, that's a separate, explicit decision (they'd need to be entered by an
ADMIN via the UI, not silently seeded from a source file already excluded from
Git). Flagged for confirmation.

### Referral destinations
3 School (all-category) + 5 AWC (category-routed) = 8 destination rows +
their context rows, exactly as tabulated in
[20_REFERRAL_CONFIGURATION.md](20_REFERRAL_CONFIGURATION.md) §2–3. No
discrepancy found here — this figure is consistent everywhere it's stated.

### Disease Master — ⚠ discrepancy found, needs your decision

[21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md) §10, and two other documents,
state **"29 Job Aid rows."** Re-enumerating the actual codified table in
[14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md) §7 directly (not
trusting the prior summary, the same discipline just applied to the table-count
correction) gives:

| Category | Rows |
|---|---|
| Defects at Birth | 11 |
| Deficiencies | 8 |
| Diseases | 9 |
| Developmental Delay & Disability | 9 |
| **Total** | **37** |

**This is a second instance of the same class of error** the table-count
correction just fixed — a stated summary figure that doesn't match direct
enumeration of the source artifact. I have not corrected the "29" references in
the three documents that carry it, and I have not decided which number is
"right" for you — I'm reporting exactly what direct enumeration of
[14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md) §7 produces (37) and
flagging the conflict. One live nuance worth your attention either way: code
`30` ("Others — Specify") is a catch-all, not a specific named finding — whether
it should become a real `disease_master` row (with `applicable_to` and a
free-text extension) or be handled differently is a design question noted but
not decided in Phase 0.5 ([01_PRD.md](01_PRD.md) FR-10.2) and still open.

**This does not block approving this plan** — the seed *mechanism* (idempotent
insert from a data file) is identical regardless of whether the final list has
29 or 37 rows. It does mean the exact seed file's row count shouldn't be
finalized until you confirm which figure (and the "Others" question) is
correct — recommend resolving this specific point before implementation
starts, as a small, separate confirmation, not as part of implementing this
plan.

## 8. Tests required

| Test | Proves |
|---|---|
| Seeding twice does not duplicate rows or throw | Idempotency |
| Every seeded `disease_master` row's `official_code` + `name` + `category` matches the source table verbatim | No transcription drift between doc and seed |
| `referral_destination_contexts` query for `(AWC, DEFICIENCIES)` returns exactly `{PHC, CHC, NRC}` and never `DEIC` | The phase's own stated exit criterion |
| `referral_destination_contexts` query for `(SCHOOL, *)` returns exactly the 3 School destinations and never DEIC/NRC/PHC/CHC/DH | Context isolation, re-confirmed at the repository layer (schema-level isolation already tested in Phase 1.2) |
| `staff_assignments` query "who's assigned as of date D" resolves to the 4 seeded members with no `end_date` | The historical-lookup pattern later phases depend on |
| No seeded `staff` row has a non-null phone number | The deliberate PII exclusion holds |
| Repository read methods work against `NativeDatabase.memory()`, never the production DB | Test isolation (unchanged discipline from Phase 1.2) |

Target: comparable rigor to Phase 1.2 (every test asserts a real behavior, not
just "no exception thrown").

## 9. Security considerations

- No new attack surface — this phase adds no network calls, no camera, no auth.
- Staff seed data is **names and work role only**, matching what's already
  committed to this repository's own documentation
  ([04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md)'s seed comment).
  Contact numbers stay excluded, consistent with the PII discipline established
  in Phase 1.2's approval.
- Seed data still lands in the **encrypted** local database (Phase 1.2's
  `openEncryptedDatabase()` — no bypass, no separate unencrypted seed path).
- `reference_materials/` stays untouched and Git-excluded; nothing in this
  phase reads from it directly — seed data files are hand-transcribed from
  already-committed, already-reviewed documentation, not from the raw source
  files.

## 10. Offline-first considerations

- Seeding runs entirely against the local encrypted database — no network
  dependency, consistent with every prior phase.
- Seeding is a one-time (idempotent, re-runnable) local operation, not a sync
  operation — it does not touch `sync_queue` or any cloud concept, both of
  which remain out of scope until the sync-engine phase.
- The read layer added here (`disease_master_repository.dart` etc.) is the
  first piece of code later *online* features (Phase 1.5 onward) will also use
  offline without modification — proving the repository pattern works
  identically online/offline from the start, rather than retrofitting it later.

## 11. Acceptance criteria

1. Running the seed step twice in a row produces identical row counts (no
   duplication) and no error.
2. Every `disease_master`, `referral_destinations`, and `referral_destination_contexts`
   row matches its documented source exactly (official code, name, category,
   label) — verified by test, not just visual inspection.
3. `flutter analyze` — zero issues.
4. `flutter test` — 100% pass, including all new tests in §8.
5. `flutter build apk --debug` — succeeds.
6. Repository queries for AWC-Deficiency and School-any-category return the
   documented, correct destination sets.
7. No phone number appears in any seeded `staff` row.
8. No production/UI code path is added that calls the seed runner
   automatically and repeatedly (it must be an explicit, one-time — or
   idempotently safe — call, not something that runs on every app boot without
   thought, to avoid becoming an accidental per-launch cost).

## 12. Explicitly NOT included in Phase 1.3

- Any UI screen (Master list/search screens are Phase 1.5).
- Authentication, RBAC enforcement, `users` table seeding (Phase 1.4 — `users`
  are admin-created accounts, not seed fixtures, and are deliberately excluded
  from this phase).
- Micro Plan import (Phase 1.6).
- Visit plans, holidays, screening, register photos, treatment (Phases
  1.7–1.10).
- `awc_checklist_items` catalogue seeding — that belongs with the AWC full-form
  work (a later phase per
  [19_AWC_SCREENING_FORM_SPEC.md](19_AWC_SCREENING_FORM_SPEC.md)), not this
  narrow reference-data phase.
- Cloud sync, OCR, reports, camera — unchanged from every prior phase's
  exclusions.
- Any change to the frozen schema, the 28-table count, or the encryption
  mechanism.

## 13. Expected Git commit structure

Mirroring the two-commit pattern used for Phases 1.1 and 1.2:

1. **Implementation commit** — `lib/data/local/seed/`, `lib/data/repositories/`,
   `lib/domain/entities/`, and the new tests. Message states what was seeded,
   the exact row counts (once §7 is resolved), and confirms idempotency.
2. **Report commit** — `docs/26_PHASE_1_3_REPORT.md`, structured like
   [24_PHASE_1_2_REPORT.md](24_PHASE_1_2_REPORT.md) (inspection performed,
   what was implemented, test results, commands run, deviations).

No unrelated work in either commit.

## 14. Risks and possible rework

| Risk | Impact | Mitigation |
|---|---|---|
| Disease Master row count resolved as 37 (or something else) after other docs already say 29 | A few hours of seed-file rework at most — the seed *mechanism* doesn't change, only the data file's row count | Resolve §7 before implementation starts, not during |
| "Others (Specify)" (code 30) design question left genuinely unresolved | Could mean re-touching the seed file once decided | Seed all *named* findings now; leave code 30 out of the initial seed with a clear TODO rather than guessing its shape, unless you decide otherwise |
| Deterministic string IDs (vs. `uuid`) turn out to collide with a later phase's ID convention | Low — reference data and transactional data are different ID spaces by design, and Phase 1.2's schema already treats all primary keys as opaque TEXT | None needed; flagged so it's a deliberate choice, not an oversight |
| Financial Year scope (2025-26 only) leaves the app without a "current" FY row when used in 2026-27 | A later phase (visit planning, most likely) would need "create FY on demand" logic anyway | Document as an explicit dependency for that later phase rather than pre-seeding an unconfirmed year now |

## 15. Recommended implementation order

1. Confirm the two open questions in §7 (Disease Master count; staff contact
   number exclusion) and the FY scope question — a short back-and-forth, not a
   redesign.
2. `lib/domain/entities/` — the four plain read-model classes (no dependencies
   on Drift types).
3. Seed data files (`*_seed_data.dart`) — pure data, reviewable independent of
   logic.
4. `seed_runner.dart` — idempotent orchestration logic.
5. Repositories — thin read layer over the seeded tables.
6. Tests — written alongside each piece above, not batched at the end.
7. Verification commands (`flutter analyze`, `flutter test`,
   `flutter build apk --debug`) and the report.

---

## Summary for approval

**A. Recommended scope:** unchanged from the originally planned Phase 1.3
(seed data for financial years, Disease Master, referral configuration,
staff/team) — confirmed still appropriate — **plus** a minimal repository/entity
read layer, added because the phase's own stated exit criterion ("referral
picker returns the right list per context") can't be proven without one, and
introducing it now, narrowly, avoids a bigger retrofit later.

**B. Files/modules:** `lib/data/local/seed/` (5 files), `lib/data/repositories/`
(4 files — first real content there), `lib/domain/entities/` (4 files), 5 new
test files. No existing file modified.

**C. Dependencies:** none new.

**D. Database impact:** rows only, into 6 existing tables
(`financial_years`, `staff`, `staff_assignments`, `disease_master`,
`referral_destinations`, `referral_destination_contexts`). No schema change,
no migration.

**E. Tests:** idempotency, source-fidelity (seeded data matches documented
source verbatim), the AWC/School referral-routing exit criterion, staff
PII-exclusion, repository read correctness.

**F. Acceptance criteria:** 8 objective checks, §11.

**G. Risks:** the Disease Master count discrepancy (29 vs. 37) is the only
one with real rework potential if resolved late; everything else is low-risk.

**H. Requires your explicit approval/decision before implementation:**
1. Disease Master seed count — 29 (as three prior documents state) or 37 (as
   direct re-enumeration of [14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md)
   §7 produces)? This is the same class of discrepancy as the table-count
   correction you just approved.
2. Should code 30 ("Others — Specify") get a seeded row now, or be deferred?
3. Staff phone numbers — confirm they stay excluded from seed data (recommended).
4. Financial Year scope — seed 2025-26 only (recommended, source-confirmed) or
   also seed 2026-27 speculatively?

No schema change is proposed or required by this plan.
