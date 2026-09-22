# Phase 0.6 — Architecture & Schema Freeze

> ## ✅ APPROVED — schema baseline v1.0 locked
>
> Approved by the product owner with nine binding conditions. These conditions govern
> all later phases and must not be relaxed without an explicit, recorded decision.
>
> 1. The v1.0 schema stays **frozen**.
> 2. **Do not invent or assume the meaning of `S.I.`** — it remains an unconfirmed
>    reading, not a mapped alias.
> 3. **Aadhaar stays [TBD]** and must not become a required field unless an official
>    requirement or source confirms it.
> 4. **Data residency is an explicit architecture decision** that must be made before
>    any child health data is deployed to cloud infrastructure.
> 5. The 7 register images are a **findings / referred line-list sample**, not
>    conclusively the complete School Screening Register.
> 6. **Do not change the schema** merely because the paper sample lacks Class, Refer-To,
>    or filled Serial No.
> 7. The digital School Screening model **must continue to support all screened
>    children, including normal children**.
> 8. OCR remains **source-image-driven and header-based**; fixed column positions are
>    never assumed.
> 9. If a genuine full/normal-child School Screening Register sample is supplied later,
>    it is analyzed and handled through a **controlled schema/documentation amendment**,
>    never a silent change to the frozen baseline.
>
> Amendment procedure (per condition 9): a proposed change is written up as a numbered
> amendment referencing this baseline, stating what source material justifies it, which
> tables/documents it touches, and its migration impact — then approved before any code
> or schema changes.

This is the master document for the freeze. It ties together the Phase 0 architecture,
the Phase 0.5 source analysis, and the Phase 0.6 decisions, and states exactly what is
settled, what is deferred, and what Phase 1 should build.

**Status tags used throughout the package:**

| Tag | Meaning |
|---|---|
| **[CONFIRMED]** | Verified against source material and consistent across sources |
| **[SOURCE-DERIVED]** | Taken directly from the Micro Plan, Job Aid, or physical register |
| **[USER-DECIDED]** | Decided by the product owner (Phase 0.6 instructions) |
| **[TBD]** | Unresolved — needs source material or confirmation; never guessed |
| **[NOT YET IMPLEMENTED]** | Designed, deliberately out of Phase 1 scope |

## 1. Deliverable index

| # | Deliverable | Where |
|---|---|---|
| 1 | Updated architecture document | [00_EXECUTIVE_SUMMARY.md](00_EXECUTIVE_SUMMARY.md), this document |
| 2 | Final domain model | §3 below |
| 3 | Database schema proposal | [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) — **FROZEN v1.0** |
| 4 | Entity relationship description | [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §1 + §4 below |
| 5 | School workflow specification | [03_WORKFLOWS.md](03_WORKFLOWS.md) §D + §5 below |
| 6 | AWC workflow specification | [19_AWC_SCREENING_FORM_SPEC.md](19_AWC_SCREENING_FORM_SPEC.md) |
| 7 | Treatment/follow-up workflow | [03_WORKFLOWS.md](03_WORKFLOWS.md) §F |
| 8 | Missed/rescheduled visit spec | [03_WORKFLOWS.md](03_WORKFLOWS.md) + §6 below |
| 9 | Staff/team history spec | §7 below |
| 10 | Referral configuration spec | [20_REFERRAL_CONFIGURATION.md](20_REFERRAL_CONFIGURATION.md) |
| 11 | Register/OCR architecture | [09_OCR_REGISTER_PHOTO_ARCHITECTURE.md](09_OCR_REGISTER_PHOTO_ARCHITECTURE.md), [18_REGISTER_SAMPLE_ANALYSIS.md](18_REGISTER_SAMPLE_ANALYSIS.md) |
| 12 | Reporting architecture | [10_REPORTING_EXPORT_ARCHITECTURE.md](10_REPORTING_EXPORT_ARCHITECTURE.md) |
| 13 | Security architecture | [08_SECURITY_ARCHITECTURE.md](08_SECURITY_ARCHITECTURE.md) |
| 14 | Offline sync architecture | [07_OFFLINE_SYNC_ARCHITECTURE.md](07_OFFLINE_SYNC_ARCHITECTURE.md) |
| 15 | Source-material findings | [14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md), [17_SOURCE_DATA_QUALITY_REPORT.md](17_SOURCE_DATA_QUALITY_REPORT.md) |
| 16 | Register sample analysis | [18_REGISTER_SAMPLE_ANALYSIS.md](18_REGISTER_SAMPLE_ANALYSIS.md) |
| 17 | Remaining unresolved items | §9 below |
| 18 | Phase 1 implementation plan | §10 below |

## 2. Decisions applied in this phase

| Decision | Resolution | Tag |
|---|---|---|
| **A. AWC official ID** | No genuine government AWC ID exists in any supplied source. `awcs.official_awc_code` is nullable and stays NULL. The unstable Micro Plan integer is retained separately as `source_plan_awc_code` with **no uniqueness constraint** and is never promoted to an official ID. Database identity is the internal UUID. | [USER-DECIDED] |
| **B. AWC screening form** | Full digital form (Option B), organised as 12 sections with age gating and collapse-by-exception. Stored as `awc_screenings` columns + a versioned checklist catalogue and response table — not 100 flat columns. | [USER-DECIDED] |
| **C. School referral destinations** | PHC/CHC, District Hospital, Higher Center — configured for the SCHOOL context only. | [USER-DECIDED] |
| **D. AWC referral destinations** | PHC, CHC, DH, DEIC, NRC with the Job Aid's category-dependent routing — configured for the AWC context only. Never merged with School's. | [SOURCE-DERIVED] |
| **E. OPT** | **Optometrist.** Applied to staff seed data and documentation. | [USER-DECIDED] |

## 3. Final domain model

**Planning & reference:** `financial_years`, `plan_imports`, `schools`, `awcs`,
`holidays`, `disease_master`, `disease_aliases`, `referral_destinations`,
`referral_destination_contexts`, `awc_checklist_items`.

**Operational core:** `visit_plans` (+ `visit_status_history`), `screening_sessions`,
`school_screenings` (+ `school_screening_findings`), `awc_screenings`
(+ `awc_screening_findings`, `awc_screening_checklist_responses`), `treatment_records`.

**Evidence & provenance:** `register_photos`, `register_photo_derivatives`, `ocr_jobs`,
`ocr_results`.

**Identity & governance:** `users`, `staff`, `staff_assignments`, `devices`,
`audit_log`, plus the local-only `sync_queue`.

Invariants that must survive every later change:

1. Official codes are nullable business identifiers; UUIDs are identity. **[CONFIRMED]**
2. Unreliable source values never carry uniqueness constraints. **[USER-DECIDED]**
3. Every screened child is a record; "normal" is the absence of findings, not a flag.
   **[USER-DECIDED]**
4. Planned/enrolment figures and actual screening counts are separate lineages, never
   reconciled automatically. **[USER-DECIDED]**
5. Original register images are immutable; preprocessing writes derivatives.
   **[USER-DECIDED]**
6. OCR output is never trusted data until a human confirms it. **[CONFIRMED]**
7. History is append-only (`visit_status_history`, `staff_assignments`, `audit_log`,
   `ocr_results`). **[CONFIRMED]**
8. No clinical criterion is computed by the app. **[CONFIRMED]**

## 4. Entity relationships (narrative)

A **financial year** contains many **visit plans**. Each visit plan targets exactly one
**school** or one **AWC** (enforced by CHECK), keeps `original_planned_date` immutable,
and records its whole lifecycle in append-only **visit status history** — which is what
the Missed Visits and Rescheduled Visits screens read.

A visit plan hosts one or more **screening sessions** (School: one per class; AWC: one
per visit) and many **register photos**. A session produces many **school screenings**
or the visit produces many **AWC screenings**. Each screening owns zero or more
**findings**; zero findings means a normal child. Each finding references one
**disease master** row and optionally one **referral destination**, which must be
configured for that workflow context.

Each AWC screening additionally owns many **checklist responses**, each pointing at a
versioned **checklist item**.

A screening with a finding is the entry point to **treatment records** — many per
child over time, defaults NO / NOT DONE / NO, further referral destination required only
when further referral is YES.

**Register photos** own **derivatives** (preprocessed variants) and **OCR jobs**, which
own **OCR results** — one per detected row, carrying raw extraction, human corrections,
and a verification status, and linking back to the screening row it eventually produced.

**Staff** own append-only **staff assignments** with effective dates, so any historical
date resolves to the team that was actually assigned then. **Users** optionally link to
staff and carry the RBAC role.

## 5. School workflow (final)

Select School + Date + Class **once** → a `screening_sessions` row opens → enter children
with Save & Next, each inheriting session context (also materialised onto the child row)
→ "Change Class" closes the session and opens a new one under the same visit → capture
register photos any time → complete visit. Normal children are saved with no findings; a
child with a finding gets one finding row per condition with its referral destination
from the **School** vocabulary. Counts are never entered manually. **[CONFIRMED]**

## 6. Missed / rescheduled visits (final)

`PLANNED → IN_PROGRESS → COMPLETED`, or `PLANNED → MISSED → RESCHEDULED → COMPLETED`.
`original_planned_date` never changes; `planned_date` moves only through a logged
reschedule; `actual_visit_date` records what really happened. Missed reasons: School
Closed, Holiday, Team Unavailable, Official Duty, Weather, Other — with
`related_holiday_id` linking to the Holiday Calendar when relevant. Reports read current
state; the full transition history stays available. **[CONFIRMED]**

## 7. Staff / team history (final)

`staff` holds people (with `qualification` separate from `designation` — the source plan
records BAMS/BHMS alongside the role). `staff_assignments` is append-only with
`start_date` / nullable `end_date` and an optional `team_label` (e.g. "Team - B"). A
transfer **closes** the outgoing assignment and **inserts** a new one; nothing is
overwritten. "Who was assigned on date D" is a range query. Seed data from the Micro
Plan: two Medical Officers (BAMS, BHMS), one Staff Nurse, one **Optometrist**.
**[SOURCE-DERIVED] [USER-DECIDED]**

## 8. What changed from Phase 0.5

1. **Schema unfrozen → frozen.** All three Phase 0.5 Required Changes applied, plus the
   Phase 0.6 decisions. Full change log: [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §9.
2. **AWC scope resolved** from "summary vs full checklist — user decision" to the full
   structured form, with a schema design that avoids a 100-column table.
3. **Referral model replaced** — a single global enum became context-specific
   configuration data.
4. **Register structure corrected against reality** (see §9 and
   [18_REGISTER_SAMPLE_ANALYSIS.md](18_REGISTER_SAMPLE_ANALYSIS.md)): no Class column,
   no Refer-To column, unused Serial No., an extra unlabeled remarks column, and
   **column order that changes between pages**.
5. **A Phase 0.5 reading was corrected**: the frequent Disease-column value read as
   "Cornea" from the low-resolution sample is actually **"Carries"/Caries** (dental).
   The earlier reading was wrong and is retracted.
6. **New tables** for session context, photo derivatives, checklist catalogue/responses,
   disease aliases, and planned-vs-actual separation.
7. **OPT resolved** to Optometrist.

## 9. Remaining unresolved items

### Needs source material

| # | Item | Blocks |
|---|---|---|
| 1 | **Full class-wise screening register** — every supplied register page is a findings-only line list (90+ rows, zero normal children). If a separate book records all screened children, it has not been photographed. | OCR mapping for the full screening flow; confidence in the "line list" interpretation |
| 2 | **School (6+ yrs) job aid / referral card** — never supplied | Confirming School's field list and referral vocabulary against an official document |
| 3 | **WHO growth-chart lookup tables** referenced by the Job Aid | Any auto-classification of anthropometry (currently user-selected) |
| 4 | **Clean Job Aid pages** for B6/B7, D10.3.1/D10.3.2, D11 numbering, codes 31–38 | Completing the checklist catalogue and Disease Master |
| 5 | **Other teams' micro plans** (only Team-B supplied) | Multi-team onboarding, if required |
| 6 | **Official report formats**, if the department mandates a layout | Matching submission formats exactly |

### Needs a decision

| # | Question |
|---|---|
| 7 | Is `S.I` in the register confirmed to mean **Skin Infection** (Job Aid code 15)? Internal evidence is strong (the same page spells "Skin-infection" in full) but it is still an inference. |
| 8 | Is `Carries` confirmed to mean **Dental Caries** (code 19, Dental Conditions)? |
| 9 | Should **Aadhaar** be collected at all? The Job Aid has the field; the app currently reserves the column unused. |
| 10 | Does "Higher Center" (School) map to a specific facility type? |
| 11 | Are the two `2024` dates and the out-of-sequence `05/02/2026` row in the register genuine, or mis-writes? |
| 12 | Should the app ever **suggest** findings from checklist responses (needs clinical sign-off), or always leave findings to the clinician? |
| 13 | **Data residency** for child health data — Supabase managed region vs. self-hosted. Still open from Phase 0; must be answered before cloud sync (Phase 1 step 6). |

## 10. Phase 1 implementation plan

Phase 1 is **foundation + School workflow end-to-end, offline**. Cloud sync, OCR, AWC
full form, and reporting come after, in that order.

| Step | Scope | Exit criterion |
|---|---|---|
| **1.1** | Flutter project skeleton per [06_PROJECT_STRUCTURE.md](06_PROJECT_STRUCTURE.md); Riverpod, go_router, theming | App builds and runs on a real Android device |
| **1.2** | Drift schema = frozen v1.0, **all tables**, SQLCipher-encrypted, migration v1 + migration tests | Schema round-trips; migration test passes with seeded data |
| **1.3** | Seed data: financial years, `disease_master` (29 Job Aid rows), `referral_destinations` + contexts (School 3, AWC 5 + routing), staff/team from the Micro Plan | Seeds load offline; referral picker returns the right list per context |
| **1.4** | Auth + RBAC scaffolding (3 roles), secure token storage, role-gated navigation shell | Each role sees the correct navigation |
| **1.5** | School/AWC Master CRUD + search; blank official codes preserved; duplicate review surface | Can create/search both masters offline; blank codes stay blank |
| **1.6** | Micro Plan import: staging preview → confirm, with the date-derivation rule (sheet + S.No, weekday cross-check), forward-fill, row-type classification, `PHC REFERRED CHILDREN TREATMENT` excluded, planned counts stored verbatim | FY2025-26 file imports to the documented row counts; no invented codes; flagged rows visible for review |
| **1.7** | Visit plans: list, detail, special visit (weekend/holiday allowed), missed + reschedule with append-only history; Holiday Calendar incl. manual holidays | Full lifecycle exercised; `original_planned_date` provably immutable |
| **1.8** | Screening sessions + School screening entry (sticky context, Save & Next, findings + School referral picker), normal children stored | A full multi-class school visit completes offline; counts derive correctly |
| **1.9** | Register photo capture attached to a visit/session, multiple photos, originals preserved, no OCR yet | Photos captured offline, visible later, never auto-deleted |
| **1.10** | Disease/Referred Line List (filtered view) + basic screening counts | Line list shows only children with findings; counts match source records |

**Not in Phase 1:** cloud sync, OCR, AWC full form, reports/exports, treatment
follow-up. Each is its own phase per
[13_IMPLEMENTATION_PHASES.md](13_IMPLEMENTATION_PHASES.md), re-sequenced so that Phase 1
delivers one complete, genuinely usable offline workflow rather than partial slices of
many.

## 11. Risks that could still cause rework

| Risk | Impact | Mitigation already in the design |
|---|---|---|
| The findings-only register interpretation is wrong, and a full screening register exists with a different layout | OCR column mapping would need redoing | OCR maps columns by header text per page, not fixed positions; the digital model already stores all children regardless of what the register holds |
| A real official AWC code appears later | AWC identity strategy shifts | `official_awc_code` column already exists, nullable, unconstrained until real data arrives |
| Job Aid gaps (B6/B7 etc.) turn out to be clinically significant items | Checklist catalogue grows | Catalogue is versioned; adding items is data, not a migration |
| Cloud handwriting OCR underperforms on this register's mixed hands and glare | OCR value drops; manual entry remains the norm | OCR was never on the offline critical path; manual entry is fully functional standalone |
| Data residency answer forces self-hosting | Deployment target changes | Same Postgres schema and RLS policies port to self-hosted Supabase |
| Class is genuinely needed on OCR-imported rows | Imported rows incomplete | `class_label` nullable by design; the app can prompt for class at review time |
| Two teams' plans use different column layouts | Import parser needs generalising | Import already stages and previews before commit; parser keys on header text |
