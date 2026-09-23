# RBSK Referred Line — Project Master Plan

**This is the single authoritative project-status and roadmap document.**
It summarizes the project; it does not redefine it — where this document and a
detailed phase document disagree, the source-of-truth hierarchy in §6 decides,
and the disagreement is fixed here, not hidden. Existing phase documents remain
the detailed technical record and are **not** replaced or deleted by this file.
[`00_EXECUTIVE_SUMMARY.md`](00_EXECUTIVE_SUMMARY.md) is the earlier Phase-0-only
summary; it stays as a historical snapshot, superseded by this document as the
living entry point.

**This file must be updated at every phase start, approval, completion, change,
block, or material revision — not only at project end.** See §13.

---

## 0. Current Status

```
CURRENT PHASE:          Phase 1.4 — Auth + RBAC Scaffolding + Navigation Shell
PHASE STATUS:           PLANNED — plan written (docs/27_PHASE_1_4_PLAN.md),
                         NOT YET APPROVED, NOT implemented. Phase 1.3
                         remains CLOSED / APPROVED, unaffected by this.
LAST COMPLETED PHASE:   Phase 1.3 — Reference/Configuration Seed + Read
                         Layer. Implementation complete, independently
                         verified (PASS, no defects, no fixes required),
                         and formally APPROVED/CLOSED by explicit user
                         instruction.
CURRENT TASK:           None — Phase 1.4 plan delivered
                         (docs/27_PHASE_1_4_PLAN.md); awaiting your
                         decisions on its open questions and your approval
                         before any implementation begins
NEXT APPROVAL REQUIRED: Resolve docs/27 §19 open questions (credential
                         mechanism: Option A/B/C; bootstrap provisioning),
                         then approve the plan
BLOCKERS:               Credential mechanism choice (docs/27 §7/§19 Q1) —
                         implementation cannot start until this is decided
LAST UPDATED:           2026-09-23 (Phase 1.4 planning)
```

---

## 1. Project Identity

| | |
|---|---|
| Project Name | RBSK Referred Line |
| Project Path | `D:\Claude\Projects\Rajni\RBSK Referred Line` |
| Technical identifier | `com.rbsk.referredline` (Android `applicationId`) |
| Display name | RBSK Referred Line |
| Platform | Android-first (Flutter; no iOS/web/desktop target built) |
| Primary users | RBSK Medical Officers and field team members |
| Authorized user count | ~8–10 (single team, "Team-B", confirmed from source Micro Plan) |
| Current technology stack | Flutter 3.47.2 · Dart 3.13.2 · Riverpod · go_router · Drift (SQLite) · `sqlite3` + SQLite3MultipleCiphers encryption |
| Current project status | Foundation phases complete (skeleton + encrypted schema + seed data/read layer, Phases 1.1–1.3 all approved & closed); no feature UI built yet; Phase 1.4 planned (docs/27), not yet approved |
| Git | 8 commits on `main` (as of Phase 1.3 implementation), working tree otherwise clean |

---

## 2. Project Objective

RBSK Referred Line digitizes the real-world field workflow of an RBSK
(Rashtriya Bal Swasthya Karyakram) team: visiting schools and Anganwadi Centres
(AWCs) on a planned schedule, screening children for defects, deficiencies,
diseases and developmental delay, referring affected children to the right
facility, following up on treatment, and reporting on all of it upward — while
replacing a paper register, not turning it into enterprise software a
non-technical Medical Officer would struggle with.

Concretely, the application exists to:

- Digitize **school screening** (all children, not just affected ones) and
  **AWC 0–6 years screening** (the full official Job Aid structure).
- Record **disease/finding** and route **referrals** through the right,
  context-specific destination (School vs. AWC have different, non-overlapping
  destination lists).
- Track **treatment/follow-up** for referred children over time.
- Maintain the **annual visit plan** (imported from the official Micro Plan),
  including special visits, missed visits, and rescheduling — without ever
  losing the original planned date.
- **Preserve the physical register as photographic evidence**, permanently and
  unmodified, with OCR-assisted (never OCR-trusted) data entry as an
  optional accelerator, always subject to human verification.
- **Report and export** (PDF/Excel) the required department views, shareable
  through Android's own share mechanism.
- Do all of the above **fully offline**, syncing to the cloud only when
  connectivity allows, and protect child health data with encryption, RBAC,
  and audit history throughout.

---

## 3. Core Product Principles

Non-negotiable, unless explicitly revisited and re-approved:

1. **Offline-first.** Every field workflow works with no network; sync is
   best-effort and never blocks data entry.
2. **Human verification of OCR is mandatory.** No OCR/AI output becomes a
   trusted screening record without explicit confirmation.
3. **Original register images are immutable.** Preprocessing writes separate
   derivative rows; the original is never overwritten and never auto-deleted.
4. **Never invent medical information** — no clinical criterion, disease code,
   classification threshold, or Job Aid meaning is guessed. Unclear source
   material is marked TBD, not filled in.
5. **Never invent government identifiers** — a blank official code (School or
   AWC) stays blank; an unstable source-plan code is never promoted to an
   official one.
6. **Planned/enrolment counts are strictly separate from actual screening
   counts** — never mixed into one field, never reconciled automatically.
7. **Normal children must be representable** — a screened child with no
   finding is a first-class record with zero finding rows, never a sentinel
   "NORMAL"/"NONE" value.
8. **School and AWC referral routing remain separate** — configuration-driven,
   never one shared hard-coded list.
9. **Historical records are never silently overwritten** — visit status,
   staff assignments, and audit events are append-only.
10. **Auditability** — every business row carries who/when created and
    updated; nothing is hard-deleted (soft-delete only).
11. **Security and privacy by design** — encryption at rest, RBAC enforced
    both client- and server-side, no child/parent/staff PII in version
    control.
12. **Source documents are authoritative** — the Micro Plan, the Job Aid, and
    the physical register govern their respective domains; conversational
    assumptions yield to them when they conflict.
13. **Schema changes require explicit approval once frozen.** The v1.0 schema
    (Phase 0.6) is frozen; any change is proposed as a numbered, approved
    amendment, never applied silently.

---

## 4. Complete Feature Map

Status legend: **DONE** (implemented & tested) · **IN PROGRESS** · **PLANNED**
(designed, not built) · **BLOCKED** · **TBD** · **DEFERRED** ·
**REQUIRES APPROVAL**.

Nothing below is marked DONE unless code exists and tests pass for it — as of
this update, that is the database schema + encryption layer (Phase 1.2) and
the four reference-data domains' seed data + read layer (Phase 1.3).
Everything else remains architecture/design (Phase 0.x) with no application
code yet.

### Planning
| Feature | Status |
|---|---|
| Financial Year | Schema: DONE. Seed data: **DONE** (FY 2025-26 seeded, tested; FY 2026-27 deliberately not seeded — Phase 1.3, commit `30d01ff`) |
| School/AWC Master | Schema: DONE. Feature: PLANNED (Phase 1.5) |
| Micro Plan import | Schema: DONE. Feature: PLANNED (Phase 1.6) |
| Visit Plan | Schema: DONE. Feature: PLANNED (Phase 1.7) |
| Planned/enrolment counts | Schema: DONE, tested separate from actual counts (Phase 1.2) |
| Holiday Calendar | Schema: DONE. Feature: PLANNED (Phase 1.7) |
| Special Visit | Schema: DONE (no date restriction enforced). Feature: PLANNED (Phase 1.7) |
| Missed Visit | Schema: DONE (append-only history). Feature: PLANNED (Phase 1.7) |
| Rescheduling | Schema: DONE. Feature: PLANNED (Phase 1.7) |
| Staff/team assignment history | Schema: DONE, tested (Phase 1.2). Seed data: **DONE** (4 Team-B members, tested, no phone numbers — Phase 1.3, commit `30d01ff`) |

### School Screening
| Feature | Status |
|---|---|
| Screening session (active School/date/class context) | Schema: DONE. Feature: PLANNED (Phase 1.8) |
| All screened children retained | Schema: DONE, tested (Phase 1.2) |
| Normal children as first-class records | Schema: DONE, tested (Phase 1.2) |
| Disease/finding children | Schema: DONE. Feature: PLANNED (Phase 1.8) |
| Referral (School vocabulary) | Schema: DONE, seed data **DONE** (3 destinations, tested — Phase 1.3). Feature: PLANNED (Phase 1.8) |
| Disease/Referred Line List | Schema: DONE (a query, not a table). Feature: PLANNED (Phase 1.10) |
| Screening counts | Derived-by-design (no stored counters). Feature: PLANNED (Phase 1.10) |

### AWC Screening
| Feature | Status |
|---|---|
| Full digital AWC screening form (Option B, not summary-only) | Schema: DONE (§2.7, incl. versioned checklist catalogue). Form/UI: PLANNED, not yet scheduled to a numbered sub-phase |
| 0–6 years scope | DONE (schema-enforced age bound) |
| Official Job Aid structure (Defects/Deficiencies/Diseases/Developmental Delay) | Schema: DONE. Checklist item catalogue seeding: DEFERRED (explicitly excluded from Phase 1.3 — belongs with the AWC form work) |
| Measurements + classification | Schema: DONE (enums for weight/height/HC/MUAC classification) |
| Developmental screening (age-banded, incl. polarity flip) | Schema: DONE. Content: TBD — Job Aid gaps (B6/B7, D10.3.x, D11 numbering) — see §9 |
| Referral findings (AWC vocabulary) | Schema: DONE, seed data **DONE** (5 destinations, category-routed, tested — Phase 1.3) |
| Doctor/MHT info, visit info | Schema: DONE |

### Register / Evidence
| Feature | Status |
|---|---|
| Original register photo capture | Schema: DONE. Feature: PLANNED (Phase 1.9) |
| Permanent original preservation | Schema: DONE (soft-delete only, derivatives are separate rows) |
| School/AWC/visit/date association | Schema: DONE |
| Multiple photos per visit | Schema: DONE (`sequence_no`) |
| Image quality/preprocessing | Schema: DONE (`register_photo_derivatives`). Implementation: NOT STARTED |
| OCR / handwriting recognition | Architecture: DONE (docs/09, docs/18). Implementation: NOT STARTED, no phase number assigned yet |
| Row/column detection | Architecture: DONE (header-text-based, not fixed-position — docs/18 finding). Implementation: NOT STARTED |
| Human review / correction / verification | Schema: DONE (`verification_status`, `corrected_fields` kept separate from raw). Implementation: NOT STARTED |
| Source-row linkage | Schema: DONE (`source_region`, `linked_school_screening_id`/`linked_awc_screening_id`) |
| Duplicate/confidence handling | Schema: DONE (`duplicate_candidate_of`, `confidence_scores`). Implementation: NOT STARTED |

### Referral
| Feature | Status |
|---|---|
| School referral (PHC/CHC, District Hospital, Higher Center) | Schema: DONE. Seed: **DONE** (Phase 1.3, commit `30d01ff`) |
| AWC referral (PHC, CHC, DH, DEIC, NRC — category-routed) | Schema: DONE. Seed: **DONE** (Phase 1.3, commit `30d01ff`) |
| Context-specific destinations (never merged) | Schema: DONE, tested (Phase 1.2) |
| Referral tracking | Schema: DONE (finding-level, not child-level) |

### Treatment / Follow-up
| Feature | Status |
|---|---|
| Referred child worklist | Schema: DONE (derivable query). Feature: PLANNED, no phase number assigned yet |
| Treatment visit, attendance, status | Schema: DONE, defaults tested (NO/NOT_DONE/NO — Phase 1.2) |
| Further referral + destination | Schema: DONE (CHECK-constrained) |
| Remarks | Schema: DONE |
| Pending/completed tracking | Derivable by design; feature not built |

### Reports
All 16 report types (Overall, School-wise, AWC-wise, Date-wise, Screening,
Disease-wise, Referral, Treatment/Follow-up, Monthly, Quarterly, Month
Selection, Financial Year-wise, Class-wise, Gender-wise, Missed Visit, Pending
Treatment): **architecture DONE** (docs/10), **implementation NOT STARTED**,
no phase number assigned yet.

### Export / Sharing
PDF, Excel, Android share mechanism (WhatsApp/Email/Drive/other): **architecture
DONE** (docs/10), **implementation NOT STARTED**.

### Security
| Feature | Status |
|---|---|
| Authentication | Architecture: DONE (docs/08). Implementation: PLANNED (Phase 1.4) |
| RBAC (3 roles) | Schema/matrix: DONE (docs/04 §3). Enforcement: PLANNED (Phase 1.4) |
| Encrypted local database | **DONE, tested, verified in the built APK** (Phase 1.2) |
| Secure key storage | **DONE, tested** (Android Keystore via `flutter_secure_storage`, Phase 1.2) |
| Cloud security (RLS, TLS) | Architecture: DONE. Implementation: NOT STARTED (cloud/sync phase not yet scheduled) |
| Audit log | Schema: DONE. Write-path: NOT STARTED (repository layer doesn't exist yet) |
| Soft delete/archive | Schema: DONE, tested (Phase 1.2) |
| Backup/recovery | Architecture: DONE (docs/04 §6, docs/08). Implementation: NOT STARTED |

### Sync
| Feature | Status |
|---|---|
| Offline writes | Local DB fully functional offline (Phase 1.2) |
| Sync queue/outbox | Architecture: DONE (docs/07). **Not part of the 28-table business schema** — explicitly local-only, not yet implemented, no phase number assigned |
| Pending/Synced/Error status | Architecture: DONE. Implementation: NOT STARTED |
| Conflict detection/resolution | Architecture: DONE (row-version based). Implementation: NOT STARTED |

---

## 5. Complete Phase Roadmap

| Phase | Status | Objective | Completion | Commit(s) | Doc |
|---|---|---|---|---|---|
| **Phase 0** | DONE | Architecture, requirements & foundation planning | 2026-09-22 | `2201795` | docs/00–13 |
| **Phase 0.5** | DONE | Analyze real source material (Micro Plan, Job Aid, 1 register photo) against Phase 0 | 2026-09-22 | `2201795` | docs/14–17 |
| **Phase 0.6** | DONE, approved | Architecture & schema freeze v1.0; 7 high-res register photos analyzed; 5 user decisions (AWC ID, full AWC form, School/AWC referral split, OPT=Optometrist) | 2026-09-22/23 | `2201795` | docs/18–21 |
| **Phase 1.1** | DONE, approved | Flutter project skeleton — identity, folder structure, theme, routing, placeholder screen | 2026-09-22/23 | `9e90c73`, `9d378a0` | docs/22, 23 |
| **Phase 1.2** | DONE, approved & CLOSED | Frozen v1.0 schema (28 tables) in Drift, encrypted local storage, migration infra, 52 tests | 2026-09-23 | `6dabedc`, `09e872c` | docs/24 |
| **Doc correction** | DONE, approved | Fixed 24→28 table count and sqlcipher_flutter_libs→sqlite3mc references across docs | 2026-09-23 | `1c071f6` | docs/04 §9, docs/05, 08, 21, 22, 24 |
| **Phase 1.3** | **DONE, approved & CLOSED** | Idempotent seed data (financial year, Disease Master, referral config, staff) + minimal repository/entity read layer. Independently verified (PASS, zero defects) before closure. | 2026-09-23 | `30d01ff`, `397ce88`, `8b357f8` | docs/25, docs/26 |
| **Phase 1.4** | **PLANNED — NOT YET APPROVED** | Auth + RBAC scaffolding, secure token storage, role-gated navigation shell. One open architectural question found: the frozen `users` table has no credential column — 3 options laid out, none chosen. | — | — | docs/27 |
| Phase 1.5 | PLANNED — NOT YET APPROVED | School/AWC Master CRUD + search | — | — | docs/21 §10 |
| Phase 1.6 | PLANNED — NOT YET APPROVED | Micro Plan import (staging → confirm, date-derivation rule, row-type classification) | — | — | docs/21 §10, docs/16 §7 |
| Phase 1.7 | PLANNED — NOT YET APPROVED | Visit plans, special/missed/reschedule, Holiday Calendar | — | — | docs/21 §10 |
| Phase 1.8 | PLANNED — NOT YET APPROVED | Screening sessions + School screening entry | — | — | docs/21 §10 |
| Phase 1.9 | PLANNED — NOT YET APPROVED | Register photo capture (no OCR yet) | — | — | docs/21 §10 |
| Phase 1.10 | PLANNED — NOT YET APPROVED | Disease/Referred Line List + screening counts | — | — | docs/21 §10 |
| *Beyond 1.10* | **NOT YET PLANNED** | AWC full-form UI, OCR pipeline, treatment/follow-up UI, reporting/export, cloud sync, auth backend | — | — | referenced in architecture docs; no numbered sub-phase exists yet — **not invented here** |

Phases 1.4–1.10 carry only the one-line scope statements already recorded in
[21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md) §10 — detailed plans (in the
style of docs/22 and docs/25) have not been written for them yet and should not
be assumed more fixed than that until each is planned in turn, the same way
1.1–1.3 were.

---

## 6. Source of Truth Hierarchy

1. Actual official source documents (Micro Plan Excel, RBSK Job Aid, physical
   register photographs) — in `reference_materials/`, Git-excluded.
2. Explicit user-confirmed decisions (Phase 0.6 approval conditions, this
   session's instructions).
3. Frozen architecture/schema documents (docs/04, docs/21).
4. Approved implementation (what's actually committed and tested).
5. **This Master Plan** — a project-level status/roadmap summary.

This document never overrides 1–4. Where it and a detailed phase document
disagree, the detailed document (or ultimately the source material) wins, and
the disagreement is corrected here — never silently.

---

## 7. Frozen Decisions

| Decision | Tag |
|---|---|
| `applicationId` = `com.rbsk.referredline` | **USER-DECIDED**, DONE |
| Display name = "RBSK Referred Line" | **USER-DECIDED**, DONE |
| `minSdk` = 26 | **USER-DECIDED**, DONE |
| Flutter, Android-first (no iOS/web/desktop built) | **USER-DECIDED** |
| Drift as the local database ORM | **CONFIRMED**, DONE |
| Local encryption: `sqlite3` + SQLite3MultipleCiphers (`sqlite3mc`) | **CONFIRMED**, DONE, tested, verified in built APK |
| ~~`sqlcipher_flutter_libs`~~ | **SUPERSEDED** — end-of-life before implementation; see docs/04 §9 item 13 |
| Passphrase: 256-bit, `Random.secure()`-generated | **CONFIRMED**, DONE, tested |
| Passphrase storage: Android Keystore-backed `flutter_secure_storage` | **CONFIRMED**, DONE, tested |
| Official AWC code (`official_awc_code`) nullable, never invented | **USER-DECIDED**, DONE (schema + test) |
| `source_plan_awc_code` non-authoritative, never unique-constrained | **USER-DECIDED**, DONE (schema + regression test) |
| School referral destinations: PHC/CHC, District Hospital, Higher Center | **USER-DECIDED** (schema DONE; seed data **DONE** — Phase 1.3, commit `30d01ff`) |
| AWC referral destinations: PHC, CHC, DH, DEIC, NRC, category-routed | **SOURCE-DERIVED** (Job Aid p.4) (schema DONE; seed data **DONE** — Phase 1.3, commit `30d01ff`) |
| OPT = Optometrist | **USER-DECIDED**, DONE (documented AND seeded — Phase 1.3, commit `30d01ff`) |
| AWC uses the full digital screening form (not summary-only) | **USER-DECIDED**, DONE (schema); form UI PLANNED, no phase number yet |
| All screened children are retained (not just referred ones) | **USER-DECIDED**, DONE (schema + test) |
| Normal children are valid records (zero finding rows, no sentinel value) | **USER-DECIDED**, DONE (schema + test) |
| Planned/enrolment counts kept separate from actual screened counts | **USER-DECIDED**, DONE (schema + test) |
| Original register images immutable; derivatives are separate rows | **USER-DECIDED**, DONE (schema); capture feature PLANNED (Phase 1.9) |
| OCR requires human verification before becoming a screening record | **CONFIRMED**, DONE (schema); OCR implementation NOT STARTED |
| No invented medical codes/criteria/classification thresholds | **CONFIRMED**, ongoing discipline, not a one-time task |
| `reference_materials/` excluded from Git | **USER-DECIDED**, DONE, verified every phase |
| No real child/patient/parent PII in Git | **USER-DECIDED**, DONE, verified every phase |
| Staff **names/designation/qualification** may be committed (work-role data, not health PII); staff **contact numbers** stay excluded | **USER-DECIDED** — names already committed (docs/04 §2.1 comment, docs/16 §8); numbers never committed |
| FY 2025-26 is currently source-confirmed | **SOURCE-DERIVED**, DONE |
| FY 2026-27 must not be seeded speculatively | **USER-DECIDED** (stated explicitly in the instruction that requested this document — resolves docs/25 §7/§H open question 4) |
| 28 tables in the frozen v1.0 business schema | **CONFIRMED** (corrected from an earlier "24" miscount — commit `1c071f6`) |
| Disease Master seed count: **37** (11 Defects + 8 Deficiencies + 9 Diseases + 9 Developmental Delay) | **USER-DECIDED**, DONE, seeded & tested (Phase 1.3, commit `30d01ff`). The earlier "29" figure is superseded — see docs/04 §9 item 12-style correction, recorded in §10 R7 below |
| Code 30 ("Others (Specify)") — official catch-all, seeded now, no clinical meaning invented, requires user-supplied specification when selected | **USER-DECIDED**, DONE, seeded & tested (Phase 1.3) |
| Schema changes after the freeze require an explicit, approved, numbered amendment | **USER-DECIDED** (Phase 0.6 approval condition 9) |

---

## 8. Database Status

| | |
|---|---|
| Frozen schema version | v1.0 (Phase 0.6), implemented as Drift `schemaVersion = 1` |
| Business table count | **28** (corrected from an earlier miscounted "24" — see docs/04 §9 item 12) |
| Database technology | SQLite via Drift 2.35.0 |
| Encryption technology | `sqlite3` 3.6.0 + SQLite3MultipleCiphers (`sqlite3mc`), `PRAGMA key`, SQLCipher-compatible |
| Migration status | Version 1 = the full frozen schema in one `onCreate` pass. No `onUpgrade` steps exist yet (none needed — no prior version to migrate from). Strategy structured to add numbered steps, never destructive recreation. |
| Key invariants | Client-generated TEXT UUID primary keys everywhere; no hard deletes; append-only history tables (`visit_status_history`, `staff_assignments`, `audit_log`, `ocr_results`); `created_by`/`updated_by` carry no FK constraint (matches the frozen DDL exactly, even though it looks asymmetric with columns like `changed_by` that do) |
| Currently implemented layer | Schema + encrypted connection + centralized Riverpod provider (Phase 1.2), plus idempotent seed data and a minimal repository/entity read layer for 4 reference domains (Phase 1.3, commit `30d01ff`). No UI, no auth, no business-transaction rows written yet |
| Future database work | Phase 1.3 DONE: rows into 6 existing tables, no schema change. Later: `sync_queue` (local-only, not part of the 28) when the sync-engine phase is scheduled; `awc_checklist_items` catalogue rows when the AWC form phase is scheduled |

**Not to be confused:** the local-only `sync_queue` outbox table
([07_OFFLINE_SYNC_ARCHITECTURE.md](07_OFFLINE_SYNC_ARCHITECTURE.md)) is **not**
part of the 28-table business schema and is not yet implemented.

---

## 9. Source Material Status

| Material | Available? | Analyzed? | Authoritative for | Unresolved issues | Needed later for |
|---|---|---|---|---|---|
| Micro Plan / School Plan (Excel, FY2025-26) | ✅ Yes | ✅ Yes (docs/17) | Visit planning structure, School/AWC master field list, staff roster | 7 ambiguous School-Code↔name mappings; AWC-code instability (15+ cases) | Phase 1.6 import |
| RBSK Job Aid (AWC 0–6 yrs, 4 pages) | ✅ Yes | ✅ Yes (docs/14) | AWC screening structure, Disease Master, referral routing | B6/B7 missing; D10.3.1/D10.3.2 missing; D11 numbering unclear; codes 31–38 unused/unconfirmed. Disease Master count resolved at 37 (Phase 1.3, §10 R7) | Phase 1.3 seed **(DONE)**, later AWC form phase |
| Register samples (8 photos total: 1 low-res + 7 high-res) | ✅ Yes | ✅ Yes (docs/18) | Physical register column structure | Whether these pages are a findings-only line list or the full screening register is **not conclusively resolved** (Phase 0.6 approval condition 5) | OCR pipeline phase |
| **Full/normal-child School Screening Register** | ❌ Not supplied | — | Would be authoritative for OCR mapping of the complete screening flow | N/A — material doesn't exist in the project yet | OCR pipeline phase — per Phase 0.6 approval condition 9, any such sample triggers a controlled amendment, not a silent change |
| School (6+ yrs) official Job Aid / referral card | ❌ Never supplied | — | Would confirm School screening fields and referral vocabulary officially | School referral list (PHC/CHC, District Hospital, Higher Center) remains a confirmed **working vocabulary**, not a transcribed official document | Confidence-building only; not currently blocking |
| WHO growth-chart lookup tables | ❌ Not supplied | — | Would enable auto-classification of anthropometry | App currently requires user-selected classification, by design | Only needed if auto-classification is ever wanted |
| Official report formats (PDF/Excel templates) | ❓ Unknown — not supplied | — | Would let reports match a mandated department layout exactly | — | Reporting phase (not yet scheduled) |

`reference_materials/` (containing all of the above except the two "not
supplied" rows) remains permanently Git-excluded, per policy established in
Phase 1.1 and reaffirmed at every phase since.

---

## 10. Open Questions / TBD

**Active:**

| # | Question | Blocks | Raised |
|---|---|---|---|
| 1 | Job Aid gaps: B6/B7, D10.3.1/D10.3.2, D11 numbering, codes 31–38 | AWC checklist catalogue completeness (not yet scheduled) | Phase 0.5/0.6 |
| 2 | Is the confirmed School referral list (PHC/CHC, District Hospital, Higher Center) validated against any official document? | Confidence only — not currently blocking | Phase 0.6 |
| 3 | Does a full/normal-child School Screening Register exist as a separate physical book? | OCR pipeline design (not yet scheduled) | Phase 0.6 |
| 4 | WHO growth-chart lookup tables — needed only if auto-classification is wanted | Not currently blocking (manual classification is the frozen design) | Phase 0.5 |
| 5 | Official report format, if any is mandated | Reporting phase (not yet scheduled) | Phase 0 |
| 6 | Data residency for cloud-hosted child health data | Cloud/sync phase (not yet scheduled) | Phase 0 |
| 7 | Is Aadhaar collection officially required for AWC screening? | AWC form phase (not yet scheduled) — field stays reserved/unused until answered | Phase 0.6 |
| 8 | `S.I` register abbreviation — confirmed meaning? | OCR alias table population (not yet scheduled). **Per Phase 0.6 approval condition 2, this must never be assumed or seeded without confirmation.** | Phase 0.6 |
| 9 | `Carries`/`Caries` register abbreviation — confirmed as Dental Caries? | Same as above | Phase 0.6 |
| 10 | **Credential mechanism for Phase 1.4** — the frozen `users` table has no credential column. Option A (local hash in secure storage, no schema change), Option B (add a credential column/table — a schema change requiring its own approval), or Option C (defer real login) — see docs/27 §7. | Phase 1.4 implementation | Phase 1.4 planning, 2026-09-23 |
| 11 | Bootstrap ADMIN account provisioning — how is the first credential set without ever hardcoding one in source? See docs/27 §19 Q2. | Phase 1.4 implementation | Phase 1.4 planning, 2026-09-23 |

**Resolved (moved here from "active" — resolution recorded, not deleted):**

| # | Question | Resolution | Source/Date |
|---|---|---|---|
| R1 | Table count: 24 or 28? | **28.** Frozen DDL is authoritative; three docs' "24" prose was a miscount, corrected. | commit `1c071f6`, 2026-09-23 |
| R2 | Local DB encryption package | `sqlite3` + SQLite3MultipleCiphers (`sqlite3mc`); `sqlcipher_flutter_libs` was end-of-life before implementation | Phase 1.2, verified in built APK, 2026-09-23 |
| R3 | Should FY 2026-27 be seeded speculatively alongside 2025-26? | **No.** Seed 2025-26 only (source-confirmed); do not speculatively seed 2026-27. | This document's creation instruction, 2026-09-23 |
| R4 | AWC official ID strategy | Nullable, never invented; `source_plan_awc_code` retained as non-authoritative reference only | Phase 0.6 approval condition A, verified Phase 1.2 |
| R5 | AWC screening form: summary or full? | Full digital form (Option B) | Phase 0.6 approval condition B |
| R6 | OPT designation | Optometrist | Phase 0.6 approval condition E |
| R7 | Disease Master seed count: 29 or 37? | **37.** Explicit user authorization; direct re-enumeration of docs/14 §7 is authoritative (11+8+9+9). "29" (carried in docs/04, docs/16, docs/21) was a documentation miscount, same class of error as R1. | Phase 1.3 implementation instruction, commit `30d01ff`, 2026-09-23 |
| R8 | Should Job Aid code 30 ("Others — Specify") be seeded? | **Yes**, as the official catch-all — seeded verbatim as "Others (Specify)". Not a predefined diagnosis; requires user-supplied specification when selected in a later phase's UI. No clinical meaning invented. | Phase 1.3 implementation instruction, commit `30d01ff`, 2026-09-23 |

---

## 11. Risk Register

| Risk | Impact | Mitigation | Status |
|---|---|---|---|
| Register layout uncertainty — supplied photos may be a findings-only line list, not the complete screening register | OCR pipeline built against the wrong mental model would need rework | Phase 0.6 approval condition 5 keeps this explicitly unresolved rather than assumed; OCR maps columns by header text, not fixed position, which limits the blast radius | **Active** |
| Source document ambiguity (School/AWC code mismatches, Job Aid gaps) | Import/seed logic could propagate bad data if not surfaced | Duplicate/ambiguous rows are flagged for human review, never auto-merged; TBD fields stay null rather than guessed | **Active, mitigated by design** |
| OCR handwriting quality (mixed hands, glare, gutter compression — docs/18) | OCR accuracy may be materially lower than hoped | Mandatory human verification is structural, not optional; manual entry remains fully functional without OCR | **Active** (OCR not yet built) |
| Cloud/data residency for child health data | Could force a self-hosted deployment target late in the project | Schema/RLS design already ports to self-hosted Supabase without rework; decision deferred to before the sync phase, not forced now | **Active, not currently blocking** |
| Schema drift (undocumented deviation from the frozen DDL) | Would undermine the "frozen schema" guarantee everything else depends on | Phase 0.6 approval condition 9 requires a controlled, approved amendment for any change; this Master Plan's §13 rules require re-verification against the frozen doc every phase | **Mitigated by process** |
| Source-plan data quality (visit-date transposition bug, enrolment mismatches — docs/17) | Naive import logic would silently corrupt planned visit dates | Documented derivation rule (sheet + S.No, weekday cross-check) exists and is scoped for Phase 1.6; not yet implemented | **Active, understood, not yet built** |
| Future government format changes (Job Aid revision, new referral facility types) | Could require new Disease Master rows or referral destinations | Both are versioned/configuration data, not enum values baked into code — additive by design | **Low, mitigated by design** |
| Two count discrepancies of the same class both found and resolved (24→28; Disease Master 29→37) | Suggests summary/prose sections in early docs are more error-prone than the underlying DDL/source tables | Direct re-enumeration against source, not summary prose, is now the standing practice for any count claim (this document follows it throughout) | **Resolved both instances; process fix applied going forward — watch for a third instance in any future summary figure** |

---

## 12. Git / Version History (navigational summary)

| Phase | Commit | Description | Date |
|---|---|---|---|
| Phase 0 – 0.6 (docs) | `2201795` | Full Phase 0–0.6 architecture and planning package | 2026-09-22 |
| Phase 1.1 (code) | `9e90c73` | Flutter project skeleton | 2026-09-23 |
| Phase 1.1 (report) | `9d378a0` | Phase 1.1 implementation report | 2026-09-23 |
| Phase 1.2 (code) | `6dabedc` | Frozen v1.0 schema in Drift, encrypted local storage | 2026-09-23 |
| Phase 1.2 (report) | `09e872c` | Phase 1.2 implementation report | 2026-09-23 |
| Doc correction | `1c071f6` | 24→28 table count and encryption package doc corrections | 2026-09-23 |
| Phase 1.3 (code) | `30d01ff` | Reference/configuration seed data + minimal read layer | 2026-09-23 |
| Phase 1.3 (docs) | `397ce88` | This Master Plan update + Phase 1.3 plan + report | 2026-09-23 |

Full detail: `git log`. This table is a summary only, not a replacement.

---

## 13. Implementation Rules for Future Claude Sessions

**Before starting any new phase, Claude MUST:**
1. Read this Master Plan.
2. Read the current/target phase's detailed document.
3. Check `git status` and `git log`.
4. Verify the last completed phase against §0 and §5 here.
5. Verify frozen decisions (§7) are not being contradicted.
6. Verify unresolved/TBD items (§10) that bear on the new work.
7. Confirm the proposed work does not contradict the frozen architecture
   (docs/04, docs/21).
8. Explicitly state whether a schema change is required — if yes, STOP and
   report it as **SCHEMA CHANGE REQUIRING APPROVAL**, do not implement it.
9. Stop and wait for approval wherever approval is required (§14).

**After completing any phase, Claude MUST:**
1. Update this Master Plan.
2. Update §0 Current Status.
3. Update the phase's row in §5 (status, completion date, commits, doc ref).
4. Record completed deliverables (§4 feature map).
5. Record test/build results.
6. Record the Git commit hash(es).
7. Record newly resolved decisions (move from §10 active to §10 resolved —
   never delete a historical entry).
8. Record newly discovered TBD items (§10 active).
9. Update §11 risks if the phase changed any risk's status.
10. Update §5 roadmap if scope for a future phase changed.
11. Verify this Master Plan is consistent with the actual implementation
    before considering the update done.
12. Commit the Master Plan update together with the phase's own documentation
    (matching the two-commit pattern already used: implementation, then
    docs/report) — or as directed by the user for that phase.

This is not optional, and is not deferred to "the end of the project."

---

## 14. Change Control

| Action | Who decides |
|---|---|
| Any change to the frozen schema/domain model | **Explicit user approval required**, as a numbered amendment (Phase 0.6 approval condition 9) |
| Inventing/guessing medical terminology or clinical criteria | **Never** — not Claude's decision, not the user's shortcut either; requires source material |
| Inventing/guessing a government identifier (School/AWC code) | **Never** |
| Adding a new dependency | Claude may propose with justification; user approves before it's added (established practice every phase so far) |
| Security architecture changes | Must be documented here and in docs/08 when they happen |
| Documentation-only corrections (e.g. a miscounted figure) | Claude may identify and propose; **implementation-affecting language changes** (like the 24→28 correction) still went through explicit user approval this project — treat that as the standing bar |
| Starting the next phase's implementation | **Explicit user approval required**, after a written plan (matching the docs/22, docs/25 pattern) |

---

## 15. Phase Detail — Phase 1.3 (CLOSED)

**Full plan:** [25_PHASE_1_3_PLAN.md](25_PHASE_1_3_PLAN.md). **Full report:**
[26_PHASE_1_3_REPORT.md](26_PHASE_1_3_REPORT.md). Summary only here; do not
treat this section as a substitute for either document.

- **Authorized scope:** all decisions that blocked this phase were resolved
  by explicit user instruction — Disease Master = 37 rows (§10 R7), code 30
  seeded as the catch-all (§10 R8), FY 2025-26 only (§10 R3), and no staff
  phone numbers (Phase 1.2's established privacy discipline, reconfirmed for
  this phase).
- **Implemented:** idempotent seed data for `financial_years` (2025-26 only),
  `staff` + `staff_assignments` (4 Team-B members, no phone numbers),
  `disease_master` (37 rows), `referral_destinations` +
  `referral_destination_contexts` (3 School + 5 AWC, category-routed) — plus
  a minimal repository/entity read layer, all under commit `30d01ff`.
- **Not in scope, not built:** any UI, `users`/auth, Micro Plan import,
  `awc_checklist_items` seeding — unchanged from the plan.
- **Independent verification:** a separate verification pass re-derived every
  factual claim from source rather than trusting the implementation report —
  full field-by-field Disease Master comparison, fresh re-run of
  `flutter analyze`/`flutter test`/APK build, fresh schema/dependency diff
  against Phase 1.2, fresh security/PII scan. Result: **PASS, zero defects,
  zero fixes required.**
- **Status: CLOSED / APPROVED.** Formally approved by explicit user
  instruction following the independent verification pass — the same
  two-step pattern (Claude implements + reports, user reviews + approves)
  used for every phase so far.

### Phase 1.4 — Auth + RBAC Scaffolding + Navigation Shell (PLANNING)

**Full plan:** [27_PHASE_1_4_PLAN.md](27_PHASE_1_4_PLAN.md). Summary only
here.

- **Status: PLANNED, NOT approved, NOT implemented.** No code, dependency,
  or schema change has been made for this phase.
- **Scope (per docs/21 §10, unchanged from the frozen roadmap):** Login
  screen, a local session mechanism, a role-gated 5-destination navigation
  shell (Home · Visits · Referrals · Reports · More), route guarding, and a
  minimal RBAC read model for nav visibility — plus one bootstrap ADMIN
  account, since `users` is currently empty.
- **Explicitly out of scope:** every feature from Phase 1.5 onward (School/
  AWC Master, Micro Plan import, visit planning, screening, register photo/
  OCR, cloud sync, reporting, treatment/follow-up), and a full User
  Management CRUD screen (deferred to a later Admin-tools phase, never
  scheduled yet).
- **One open architectural question found during planning:** the frozen
  `users` table has no credential column at all — authentication was
  originally designed around Supabase Auth (external, not yet integrated).
  Three options are laid out in docs/27 §7 (local hash in secure storage, no
  schema change — recommended; a schema change requiring separate approval;
  or deferring real login). **Not decided — see §10 items 10–11.**
- **Next step:** you resolve docs/27 §19's open questions and approve the
  plan before any implementation begins.

---

## 16. Definition of Done (project-level)

The project is **not** production-ready merely because the application
builds. Full production readiness requires, at minimum:

- [ ] All functional workflows implemented (planning, screening, referral,
      treatment, register/OCR, reporting, export)
- [ ] Data integrity verified under real field conditions, not just tests
- [ ] Offline operation confirmed on real devices, not just `flutter test`
- [ ] Sync reliability (outbox, conflict resolution) implemented and tested
      across multiple devices
- [ ] Security review completed (encryption, RBAC enforcement client+server,
      audit trail actually populated)
- [ ] Backup/recovery tested, not just designed
- [ ] Report correctness validated against real department expectations
- [ ] OCR verification workflow used and validated with real register photos
      (once the register-type open question is resolved)
- [ ] Permissions/RBAC enforced in the running app, not just in the schema
- [ ] Test coverage extends past the database layer into features/UI
- [ ] On-device verification performed (still outstanding since Phase 1.1 —
      no Android device/emulator has been available in this environment)
- [ ] Deployment/installability confirmed (signed release build, not just
      debug APKs)
- [ ] Documentation kept current with implementation (this Master Plan's
      whole purpose)
- [ ] User acceptance from the actual RBSK team

None of these are checked yet. The project is currently at "foundation
complete, no feature implemented."
