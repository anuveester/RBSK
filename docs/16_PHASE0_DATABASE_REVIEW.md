# Phase 0 Database Review Against Source Materials

Purpose: check every load-bearing decision in
[04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) against the real Micro Plan
Excel, Job Aid, and register sample now available, and classify what needs to change
before the schema is frozen for Phase 1. **No schema file has been modified as part of
this review** — per Phase 0.5 rules, changes are proposed here for confirmation, not
applied silently. Classification: **No Change Required / Recommended Change /
Required Change / Requires User Decision.**

## 1. `schools` table and School Master identity strategy

**No Change Required.**

Evidence supports the original design: School Codes are 10-digit UDISE-style numbers
(e.g. `9370301901`), present on 147/149 school rows (98.7%), and the partial-unique
index (unique only where non-blank) is the right constraint — confirmed by finding
exactly the kind of legitimate same-name-different-code pairs the brief warned about
(e.g. two schools both named "ANDHIYARI" in SEP25 with distinct codes `9370305101` /
`9370305102`, almost certainly separate Primary/Upper-Primary sections at the same
locality). Code-first identity, name-as-tiebreaker-only, is correct as designed.

**Recommended Change:** add a nullable `data_quality_notes text` column to `schools`
(and `awcs`) so the plan-import parser can carry forward flags it raises during
ingestion (spelling variants, category-field inconsistencies — see §7) for later human
review, instead of either silently normalizing them or discarding the flag. This is
additive and non-breaking.

## 2. `awcs` table and AWC Master identity strategy

**Required Change — the "Anganwadi Code" column cannot be treated as a stable, unique
official identifier.**

Evidence: the same small integer code (range 1–170, no district/state prefix — visibly
a different *kind* of value than the 10-digit School Code) maps to clearly different,
unrelated AWC names across different monthly sheets in at least 15 cases. Examples:

| Code | Names it maps to across sheets |
|---|---|
| 57 | HEERAPUR, BARODASWAMI 1+2, BARODA SWAMI |
| 83 | GENDORA, DAILWARA-5, DAILWARA 5+6 |
| 76 | BANOLI, KACHRONDAGHAT |
| 87 | RANIPURA, RAJGHAT-1 |
| 29 | JAIRWARA, TORIYA |

(Full list in [17_SOURCE_DATA_QUALITY_REPORT.md](17_SOURCE_DATA_QUALITY_REPORT.md).)

This is inconsistent with treating it as a government-issued AWC ID the way School Code
is treated. The most likely explanation is that this column is a **local/positional
serial number within this specific micro-plan** (possibly reused or reassigned month to
month), not a durable master-data key. 18/196 AWC rows (9.2%) also have it blank.

**Recommendation (pending your decision):**
- Drop the partial-unique index on `awc_code` — do **not** enforce uniqueness on it.
- Add a `plan_local_serial` (or similarly named) nullable text field distinct from
  `awc_code`, if it turns out this number is meaningful only *within* a given plan
  import, not across plans/years.
- Treat AWC Master identity primarily by **name + block/village context**, with the
  ambiguous-duplicate review workflow (already planned generically in the brief) doing
  real work here rather than being a rare edge case.

**Requires User Decision:** is there a *separate*, genuinely official Anganwadi Center
ID (e.g. a state ICDS AWC code, distinct from this small sequential number) that should
be collected instead or in addition? This cannot be answered from the Excel alone —
confirm with the ICDS/Women & Child Department side of the data.

## 3. `referral_destination` enum

**Required Change**, confirmed directly by the Job Aid (page 4, "Preliminary Findings
and Referral"). The Phase 0 enum (`PHC_CHC`, `DISTRICT_HOSPITAL`, `HIGHER_CENTER`) is a
simplification the brief itself proposed without an official source; the actual
document shows category-dependent, more granular routing:

| Finding category | Official destination(s) |
|---|---|
| Defects at Birth | DH, DEIC |
| Deficiency | PHC, CHC (SAM specifically → NRC) |
| Disease | PHC, CHC, DH (Dental specifically → DEIC, DH) |
| Developmental Delay & Disability | DEIC |
| Others | PHC, CHC, DH |

Recommend replacing the 3-value enum with distinct facility values — at minimum `PHC`,
`CHC`, `DH`, `DEIC`, `NRC` — and making the UI's offered options depend on the finding's
category rather than presenting all facilities for every finding. The form also
supports **per-category** referral Yes/No (a child can have a non-referred Defects
finding and a referred Deficiency finding on the same visit) — the current
`school_screening_findings`/`awc_screening_findings` design (one row per finding, each
carrying its own `referral_destination`) already supports this correctly; only the enum
values need to change.

**Requires User Decision:** School screening's referral options (`PHC/CHC, District
Hospital, Higher Center` per the original brief) have no official source document at
all — no School job aid/referral card was supplied. Confirm whether School should adopt
the same `PHC/CHC/DH/DEIC/NRC` vocabulary as AWC, or genuinely has a simpler, different
set. Do not assume they're the same without a source.

## 4. `disease_master` seed data

**Recommended Change (data, not schema).** The category enum already in
[04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md)
(`DEFECTS_AT_BIRTH`/`DEFICIENCIES`/`DISEASES`/`DEVELOPMENTAL_DELAY_DISABILITY`/`OTHERS`)
matches the Job Aid's own category structure exactly — no enum change needed. What's
new is that the table can now be **seeded with the real, codified list** from
[14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md) §7 (29 confirmed
code/name/category rows) instead of remaining empty/placeholder. Recommend doing this
seed as a Phase 1 migration data file, not hand-entered later.

Two items need resolution before the seed is finalized (see
[14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md) §9): codes 31–38 are unused
in the source and should stay unused rather than invented; B6/B7 are missing from the
Deficiency section and should be confirmed rather than guessed at.

## 5. AWC screening: classification fields

**Recommended Change.** The Phase 0 schema left `weight_classification` and
`height_classification` as free `text` columns marked `TBD — Job Aid`. The Job Aid now
gives exact, closed option lists (see
[14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md) §2):

- Weight-for-age: `Normal / <-2SD / <-3SD`
- Weight-for-length/height: `Normal / <-2SD / <-3SD`
- Height-for-age: `Normal / <-2SD / <-3SD`
- Head circumference: `Normal / <-2SD (Micro) / <-3SD / >+2SD (Macro)`
- MUAC: `Red / Yellow / Green`

Recommend converting these from free text to proper enum types in the `awc_screenings`
table once Phase 1 begins. Also add a `head_circumference_classification` column
(currently absent from the Phase 0 table — the original design only had
`weight_classification`/`height_classification`) since the Job Aid clearly treats it as
its own classified field, not merely a raw measurement.

**Requires User Decision:** the form references WHO growth-chart lookup tables ("refer
chart in Job Aids") that were not part of the photographs supplied. If the app should
auto-compute these classifications from raw weight/height/age rather than have the user
select them manually, those charts are needed. Otherwise the fields stay
user-selected, which is what the current design assumes.

## 6. AWC screening: granularity of the clinical checklist

**Requires User Decision — this is the most consequential open item in this review.**

The Job Aid's actual screening tool is a large conditional checklist: Section A (11
items + 5 sub-items), Section B (7 items), Section C (5 items + C7's 4 sub-items with
their own sub-answers + C8's ~25 sub-items across 5 groups), Section D (roughly 50
age-banded developmental items across 8 age bands, plus a 6-item autism questionnaire,
plus 11 items for ages 2.5–6y) — on the order of **100+ discrete data points per
child**, several with their own conditional sub-answers (e.g. C7.1.1 lesion count,
C8.1.3's 4-cell table).

The Phase 0 `awc_screenings` table (§04, §2.6) was designed around capturing the
**summary outcome** — which findings are present (via `awc_screening_findings`,
referencing `disease_master`) and the anthropometry/classification fields — not the
full underlying checklist that leads a clinician to that conclusion.

Two paths, with materially different Phase 1 scope:

- **(A) Capture summary findings only** (current design): the doctor/MHT works through
  the paper Job Aid checklist as they already do, and enters only the resulting
  findings (which of the ~29 codes apply) plus anthropometry into the app. Phase 1 stays
  roughly as scoped. The full checklist stays a paper/clinical-judgment tool, not a
  digitized data-entry surface.
- **(B) Digitize the full checklist**: every item in Sections A–D becomes its own
  field, with the conditional logic (including the D-section's YES/NO polarity flip)
  implemented in the UI. This is a substantially larger AWC screening form and a
  materially bigger Phase 3 (and possibly Phase 1 schema addition — a
  `awc_screening_checklist_responses` table or similar) than Phase 0 assumed.

**Recommendation:** proceed with (A) for Phase 1–3 unless you tell us otherwise — it
matches the brief's original "as simple as a register" product principle (§30/§33 of
the original brief) far better than a 100-field digital form would, and the summary
findings are what actually drive the Disease/Referred Line List, referral, treatment,
and reporting workflows. But this is explicitly your call to make, not a default we're
quietly locking in — please confirm.

## 7. Plan import parser (not a schema change, but load-bearing for Phase 2)

None of the following require changing `visit_plans`, `holidays`, `schools`, or `awcs`
column definitions — they are **parser logic** the Phase 2 plan-import feature must
implement. Documenting them here because getting them wrong would corrupt real data on
first import.

### 7.1 Visit date column cannot be trusted at face value — Required Change to parser logic

The raw "Visit date" cell is unreliable due to a data-entry bug, evidenced across all 12
sheets:

- For day-of-month ≤ 12, the cell is stored as a real Excel date but with **day and
  month transposed** relative to the true intended date (e.g. April25 sheet, S.No=6
  "RAMNAVMI" stored as `2025-06-04`, i.e. June 4 — but the "Day" column says `SUNDAY`,
  and the true April 6, 2025 was indeed a Sunday; June 4, 2025 was a Wednesday. The
  weekday-text column proves the stored date is wrong, not the interpretation.)
- For day-of-month 13–31, month>12 is impossible, so Excel instead stored the cell as
  **literal text** in `D/M/YYYY` order (e.g. `'13/4/2025'`), which *is* correctly
  ordered when parsed as day-first.
- The swap is **not consistent per-sheet or per-row** — some day≤12 rows in the same
  sheet are swapped, some aren't (e.g. AUG25 row14 "RASOI" stored correctly as
  `2025-08-01`, but AUG25 row15 "PHC..." stored swapped as `2025-02-08`). Any parser
  that tries a single blanket transformation rule will get some rows wrong.

**The reliable derivation, confirmed across every sheet with 100% consistency:**
`true_visit_date = (sheet's known month/year) + (S.No column, taken as day-of-month)`.
The `S.No` column runs 1→28/30/31 exactly matching the real number of days in that
sheet's month, in strict order, for all 12 sheets with no exceptions found. The "Day"
(weekday name) column, wherever present, matches this derived date in every case
checked — it should be used as a cross-validation check (flag, don't hard-fail, any row
where they disagree) rather than as the source of truth itself.

**Recommendation:** the Phase 2 import parser should derive `planned_date` from
sheet name + `S.No`, not from the raw Visit Date cell, and should treat a blank `S.No`
row as belonging to the same day as the nearest preceding non-blank `S.No` (see §7.2).

### 7.2 Same-day multiple visits — forward-fill pattern

Rows with a blank `S.No.` (and often blank institution name) immediately follow a
numbered row and represent an additional School/AWC visited on the **same** day as the
preceding numbered row (e.g. MAY25 row14 `S.No=1, JAKHAURA-1+2` then row15
`S.No=blank, code=2, name=blank`). The parser should forward-fill both the day number
and (where the row itself is otherwise blank of a name) flag it for review rather than
silently dropping it — it still represents a real visit with real child-count data in
most cases.

### 7.3 Row-type classification — confirmed, no change to the brief's approach

Confirmed row types found in column C ("School/Anganwadi"): `SCHOOL` (149 rows), `AWC`
(196 rows), and blank (129 rows). Blank-type rows' institution-name values fall into
exactly two patterns:
- `SUNDAY` (49 occurrences — one per week of the FY) and named public holidays (~24
  distinct, each once) → map to `holidays`.
- `PHC REFERRED CHILDREN TREATMENT` (49 occurrences — **every single Saturday of the
  FY**) → this is a recurring **working activity**, not a holiday, and doesn't
  reference a specific School/AWC. **Recommend excluding these rows from both
  `visit_plans` and `holidays` import** — they don't fit either table, and forcing them
  in would misrepresent every Saturday as either a "visit" with no target or a
  "holiday" that isn't one. This is informational confirmation that Saturdays are
  institutionally reserved for the existing Referral/Treatment workflow (see
  [03_WORKFLOWS.md](03_WORKFLOWS.md) Workflow F) — no schema change needed, the
  existing Referral/Treatment design already covers Saturday follow-up visits.

### 7.4 Category fields need normalization, not schema change

`category_school` and `category_standard` source values are inconsistently cased
(`PS`/`ps`) and in a handful of rows appear to have the wrong kind of value in the wrong
column (e.g. an age-range string like `6Y-to-14Y` appearing in the `category_school`
slot where an institution-type code like `PS`/`UPS`/`COM` was expected). Recommend the
import parser normalize case and flag (not silently correct) rows where
`category_school` doesn't match the expected `{PS, UPS, COM}` vocabulary, writing the
flag to the new `data_quality_notes` column proposed in §1.

### 7.5 Male/Female/Total enrollment counts — Requires User Decision

The source plan carries per-institution enrollment counts (Male/Female/Total children)
that have no home in the current schema (`schools`/`awcs` don't carry enrollment
figures — deliberately, since Phase 0 treats counts as computed from screening data,
not stored). 15/341 rows (4.4%) show `Male + Female ≠ Total` in the source, so if this
is stored, it must be stored exactly as given (including the mismatches), never
"corrected."

**Requires User Decision:** does the app need to retain this enrollment snapshot at
all (as reference/planning context), or is it disposable once the plan is imported?
If needed, recommend an additive, nullable set of columns on `visit_plans` (since
enrollment is a plan-time snapshot tied to a specific visit, not an immutable property
of the school/AWC itself) rather than on `schools`/`awcs`.

## 8. `staff` / `staff_assignments` seed data

**No Change Required to schema.** The source plan's "Details of Dedicated Team" block
maps cleanly onto the existing design: one team (`Team - B`), 4 members, one continuous
assignment spanning the whole FY (no transfer evidence in this single file/year):

| Name | Designation | Mobile |
|---|---|---|
| Rajni Pratap | MO (BAMS) | *(in source plan)* |
| Deepak Yadav | MO (BHMS) | *(in source plan)* |
| Shabnam Khan | SN | *(in source plan)* |
| Mangal Kumar | Optometrist (OPT) | *(in source plan)* |

Contact numbers are not reproduced in version-controlled documentation; they are read
from the source Micro Plan at seed time.

**RESOLVED (Phase 0.6):** "OPT" = **Optometrist**, confirmed by the product owner. Seed
data and all documentation now use the full designation. **[USER-DECIDED]**

B.E.O. (Jameel Ahmad) and C.D.P.O. (Neeraj Singh) are external contacts referenced by
the plan, not RBSK team members — they don't need `staff` rows unless you want them
as a lightweight external-contacts reference (not currently modeled; low priority,
additive if wanted later).

## 9. Summary table

| Area | Classification |
|---|---|
| `schools` identity strategy (code-first) | No Change Required |
| `data_quality_notes` column (schools/awcs) | Recommended Change (additive) |
| `awcs.awc_code` as unique identifier | **Required Change** — drop uniqueness assumption |
| Separate official AWC ID | Requires User Decision |
| `referral_destination` enum | **Required Change** — expand to PHC/CHC/DH/DEIC/NRC |
| School referral vocabulary (same as AWC?) | Requires User Decision |
| `disease_master` seed data | Recommended Change (data, using confirmed source) |
| Disease Master codes 31–38, B6/B7 | Requires User Decision (confirm with issuer) |
| AWC anthropometry classification enums | Recommended Change |
| Head circumference classification column | Recommended Change (additive) |
| WHO growth chart auto-classification | Requires User Decision |
| AWC full clinical checklist vs. summary-only | **Requires User Decision** (biggest scope question) |
| Plan-import date derivation logic | Required Change to parser (not schema) |
| Same-day multi-visit forward-fill | Required Change to parser (not schema) |
| PHC Referred Children Treatment rows | Recommended Change to parser (exclude from import) |
| Category field normalization | Recommended Change to parser |
| Enrollment Male/Female/Total counts | Requires User Decision |
| `staff`/`staff_assignments` seed data | No Change Required to schema; ready to seed |

## 10. Is the schema frozen?

**Resolved in Phase 0.6 — yes, the schema is now frozen at v1.0.** Every Required
Change and Requires-User-Decision item in this review has been answered and applied:

| This review's item | Phase 0.6 outcome |
|---|---|
| §2 AWC code uniqueness / identity | Applied — `official_awc_code` (nullable, no data) split from `source_plan_awc_code` (non-authoritative, no uniqueness) |
| §3 `referral_destination` enum | Replaced with context-specific configuration tables ([20_REFERRAL_CONFIGURATION.md](20_REFERRAL_CONFIGURATION.md)) |
| §3 School referral vocabulary | Confirmed as PHC/CHC, District Hospital, Higher Center — kept separate from AWC |
| §4 `disease_master` seed | Confirmed; 29 Job Aid rows seeded in Phase 1 step 1.3 |
| §5 Anthropometry classification enums | Applied, incl. the previously missing head-circumference classification |
| §6 AWC checklist granularity | **Option B — full digital form** ([19_AWC_SCREENING_FORM_SPEC.md](19_AWC_SCREENING_FORM_SPEC.md)) |
| §7.5 Enrolment counts | Retained on `visit_plans`, verbatim, strictly separate from actual screening counts |
| §8 "OPT" | Optometrist |

See [21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md) and
[04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §9 for the full change log.
