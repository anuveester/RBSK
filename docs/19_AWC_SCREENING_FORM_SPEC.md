# AWC Screening — Full Digital Form Specification (Phase 0.6)

**[USER-DECIDED — Option B]:** the app implements the **complete** official RBSK 0–6
years screening workflow, not a summary of findings. This document specifies how that
is organised so it remains fast for a Medical Officer to complete, and how it maps onto
the frozen schema (`awc_screenings`, `awc_checklist_items`,
`awc_screening_checklist_responses`, `awc_screening_findings` — see
[04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §2.7).

Source of truth for every item: the four Job Aid photographs, transcribed in
[14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md). **No clinical criterion,
threshold, code, or decision rule in this document is invented.** Where the source is
unclear it is carried through as `[TBD]` and the corresponding catalogue row is simply
not created.

## 1. Design rule: sections, not a 100-field wall

The form is a **sectioned stepper** — one section visible at a time, with a progress
strip showing all sections and allowing free jumping between them. Each section is
independently savable; the screening record is a draft until the user marks it
complete, so an interrupted visit never loses work.

Two principles keep it fast:

1. **Age gating.** Section D (developmental) has eight age bands plus an autism
   questionnaire plus a 2.5–6y battery. **Only the band matching the child's age is
   shown.** A 7-month-old sees ~7 milestone questions, not ~70. Items outside the band
   are stored as `not_applicable = true`, never as "No".
2. **Collapse-by-exception.** Sections A, B and C render as compact tick-lists where the
   default state is "nothing ticked". Sub-items (A10's Down's-syndrome signs, C7's
   leprosy sub-questions, C8's TB protocol) stay **collapsed until the parent item is
   ticked**. A child with no findings is a few taps per section.

Realistic interaction cost for a normal child: **Preliminary + Anthropometry +
four sections with nothing ticked + one age-banded milestone set.**

## 2. Section map

| # | Section | Schema target | Notes |
|---|---|---|---|
| 1 | Preliminary Particulars | `awc_screenings` columns | child, guardian, ASHA, AWC, IDs |
| 2 | Anthropometry & Classification | `awc_screenings` columns | measurements + 5 classification selects |
| 3 | A — Defects at Birth | checklist responses | A1–A11 incl. A10(a)–(e), A1a/A1b |
| 4 | B — Deficiency | checklist responses | B1–B5, B8, B9 (B6/B7 `[TBD]`, absent) |
| 5 | C — Disease | checklist responses | C1–C5 |
| 6 | C7 — Leprosy protocol | checklist responses | conditional sub-tree |
| 7 | C8 — Tuberculosis protocol | checklist responses | conditional sub-tree |
| 8 | D — Developmental (age-banded) | checklist responses | only the applicable band renders |
| 9 | D10 — Autism questionnaire | checklist responses | 15–18mo and 18–24mo bands only |
| 10 | D11 — Screening 2.5–6 years | checklist responses | renders only for age ≥ 30 months |
| 11 | Findings & Referral | `awc_screening_findings` | clinician selects findings + destinations |
| 12 | Doctor / MHT & Visit sign-off | `awc_screenings` columns | name, date, register-entry confirmation |

## 3. Field types and controls

| Job Aid construct | Control | `response_type` |
|---|---|---|
| Tick box ("if YES refer") | Toggle / checkbox, default off | `BOOLEAN` |
| Milestone question ("Does the child…?") | Yes / No segmented control, **no default** | `YES_NO` |
| Autism Y/N ("Answer Y/N discretely") | Yes / No segmented control, no default | `YES_NO` |
| C7.1.1 lesion count (1–5 / >5) | Single-select chips | `SINGLE_SELECT` |
| C7.1.2 lesion type (Linear/Non-linear/Raised/Flat) | Single-select chips | `SINGLE_SELECT` |
| C8.1.3 respiratory table (4 cells) | Multi-select chips | `MULTI_SELECT` |
| C8.1.4 lymph node table (4 cells) | Multi-select chips | `MULTI_SELECT` |
| Weight / height / HC / MUAC | Decimal numeric with unit label | column on `awc_screenings` |
| Classifications | Single-select (`Normal / <-2SD / <-3SD`, plus `>+2SD` for HC; `Red/Yellow/Green` for MUAC) | enum column |
| Dates | Date picker, default = visit date | column |
| Names, IDs, remarks | Text | column |

**Referral polarity is not uniform and must not be normalised** — the catalogue's
`polarity` column carries it per item:
- Sections A, B, C, C7, C8, D9.1, D11 → **refer if YES**.
- Section D milestones (D1–D8) → **refer if NO** (the source header reads *"if NO
  Refer"*).
- D10 autism → **mixed per item**: D10.1.1, D10.1.2, D10.2.1, D10.3.3 refer if **N**;
  D10.1.3 and D10.2.2 refer if **Y**.

The UI surfaces this by colouring/annotating the answer that constitutes a red flag,
driven by `polarity`, rather than assuming "ticked = bad".

## 4. Conditional logic

```
A10 (Down's syndrome)        ticked → reveal A10(a)–(e)
A1  (Head size/shape)        ticked → reveal A1a (<-2SD Micro) / A1b (>+2SD Macro)
C7.1 (leprosy patch)         ticked → reveal C7.1.1 lesion count, C7.1.2 lesion type
C8.1 (any TB symptom a–i)    any ticked → reveal C8.1.1 … C8.1.5 sub-groups
MUAC                         enabled only when age 6–60 months AND
                             weight-for-age is <-2SD or <-3SD   (Job Aid condition)
Section D band               determined by age_months; other bands hidden, stored N/A
D10 autism                   shown only for age 15–24 months
D11 battery                  shown only for age ≥ 30 months
Findings & Referral          destination picker filtered by finding category (§20 doc)
```

All conditions above are **transcribed from the form**, not inferred. The one condition
stated as guidance rather than a rule (MUAC) is enforced in the UI only, not as a DB
constraint.

## 5. What the app deliberately does NOT do

- **No auto-diagnosis.** The checklist records observations. Converting observations
  into a finding (e.g. the Job Aid's *"refer if more than one sign"* for A10, or the C8
  positivity logic that distinguishes CNS / pulmonary / lymph-node / disseminated TB)
  is a clinical judgement. The app stores both the observations and the clinician's
  selected findings, and never derives one from the other.
  **[NOT YET IMPLEMENTED — requires clinical sign-off before any auto-suggestion]**
- **No SD-band computation.** Classifications are selected by the user from the Job
  Aid's own reference charts. Those charts were not supplied, so the app cannot compute
  them. **[TBD — WHO growth-chart tables needed]**
- **No invented items.** B6, B7, D10.3.1, D10.3.2 and Disease Master codes 31–38 are
  absent or illegible in the supplied photographs. **No catalogue rows exist for them.**
  If a clean copy of the form is supplied later, they are added as a new catalogue
  `version` — existing responses keep their meaning because
  `awc_screening_checklist_responses` snapshots `item_code`.

## 6. Catalogue versioning

`awc_checklist_items.version` (e.g. `JOBAID-0-6Y-2026-09`) pins the exact item set used
for a given screening. Corrections or additions create a **new version**; historical
rows continue to reference the version they were captured under. Items transcribed from
a partly illegible region carry `is_uncertain = true` plus an `uncertainty_note`, so the
UI can show a "verify against the printed form" hint rather than silently presenting a
possibly-wrong label as official.

## 7. Offline behaviour

The form is fully offline. Each section save writes locally and enqueues to the outbox
(see [07_OFFLINE_SYNC_ARCHITECTURE.md](07_OFFLINE_SYNC_ARCHITECTURE.md)). A partially
completed screening syncs as a draft; completeness is a UI state derived from required
fields, not a lock that blocks syncing.

## 8. Open items for this form

| Item | Needed from |
|---|---|
| B6, B7 content | clean Job Aid page 1 |
| D10.3.1, D10.3.2 content; D11 first/last item numbering | clean Job Aid pages 3–4 |
| WHO growth-chart lookup tables | Job Aid annexure (referenced, not photographed) |
| Whether Aadhaar is to be collected at all | Medical Officer / district health authority |
| Whether checklist→finding suggestions are wanted | clinical sign-off |
