# Source Materials Required

Phase 0 rule: nothing in this architecture package invents data that should come from
official source material. All three materials originally listed here have now been
**partially supplied** under `reference_materials/` (as of Phase 0.5). This file
records what was received, what it resolved, and what's still outstanding. Full
analysis: [docs/14_JOB_AID_FIELD_MAPPING.md](docs/14_JOB_AID_FIELD_MAPPING.md),
[docs/15_REGISTER_OCR_FIELD_MAPPING.md](docs/15_REGISTER_OCR_FIELD_MAPPING.md),
[docs/16_PHASE0_DATABASE_REVIEW.md](docs/16_PHASE0_DATABASE_REVIEW.md),
[docs/17_SOURCE_DATA_QUALITY_REPORT.md](docs/17_SOURCE_DATA_QUALITY_REPORT.md).

## 1. Annual School/AWC Micro Plan (Excel)

**Status: RECEIVED** — `reference_materials/school_plan.xlsx`, FY 2025-26 (April 2025 –
March 2026), Team-B, Lalitpur district / Jakhaura block, 12 monthly sheets. Fully
analyzed; column mapping, row-type classification, and date-derivation logic are all
documented.

**Still needed:**
- Confirmation on 7 ambiguous School-Code-to-name mappings, and on the AWC Code
  instability finding (a small integer code that maps to different AWC names across
  months in 15+ cases — see database review §2) — cannot be resolved from the file
  alone.
- Whether a *separate*, genuinely official Anganwadi Center ID exists (distinct from
  the unstable code in the file).
- If RBSK teams besides Team-B exist and should also be onboarded, their micro-plan
  files (not supplied).

## 2. Official RBSK Job Aid (photographs)

**Status: RECEIVED (AWC 0–6 years tool only)** — 4 photographs under
`reference_materials/rbsk_job_aid/`, covering all 4 pages of the official "Screening
and Referral Tool for Children (0-6 years)": preliminary particulars, anthropometry
classification, Sections A (Defects at Birth), B (Deficiency), C (Disease, including
Leprosy and TB sub-protocols), D (Developmental Delays + Autism questionnaire), and the
codified Disease Master with referral routing. Fully transcribed in
[docs/14_JOB_AID_FIELD_MAPPING.md](docs/14_JOB_AID_FIELD_MAPPING.md).

**Still needed:**
- **A School (6+ years) job aid or referral card — not supplied at all.** School
  screening's field list and referral-destination options remain as stated in the
  original brief, with no official source to confirm them against.
- Clarification on gaps found in the supplied pages: missing items B6/B7
  (Deficiency section), missing D10.3.1/D10.3.2 (Autism questionnaire), unclear
  numbering at the start of Section D11, and unused Disease Master codes 31–38 (may
  simply not exist — needs confirmation, not a guess).
- The WHO growth-chart lookup tables referenced on the form ("refer chart in Job
  Aids") — only needed if the app should auto-classify anthropometry rather than have
  the user select the classification manually.
- Expansion of the "OPT" staff designation abbreviation (Optometrist? Pharmacist?) used
  in the Micro Plan's team roster.

## 3. Sample Register Photographs

**Status: RECEIVED (8 total; 7 high-resolution)** — `reference_materials/Registered
Sample/` (7 photos, April & May 2026 pages) plus the original low-resolution
`register_samples.jpeg`. Fully analyzed in
[docs/18_REGISTER_SAMPLE_ANALYSIS.md](docs/18_REGISTER_SAMPLE_ANALYSIS.md), which is
**authoritative** for register structure and supersedes
[docs/15_REGISTER_OCR_FIELD_MAPPING.md](docs/15_REGISTER_OCR_FIELD_MAPPING.md).

Confirmed: 9 hand-ruled columns (S.No — never filled, Date, School/Anganwadi Name,
Child's Name, Sex, Age, Father's Name, Mother's Name, Disease) plus an unlabeled
remarks column. **No Class column and no Refer-To column exist.** Column order between
Sex and Age varies page to page. Latin script only; no Devanagari. School and AWC
entries share one book.

**Still needed:**
- **Confirmation of whether a separate full class-wise screening register exists.** All
  90+ observed rows carry a finding — not one normal child — strongly indicating these
  pages are a findings-only line list rather than the complete screening register. If a
  full register exists, its photos have not been supplied and the OCR mapping has not
  been designed against it.
- Confirmation of the shorthand readings `S.I` (→ Skin Infection?) and `Carries`
  (→ Dental Caries?).
- Confirmation on two rows dated `2024` and one out-of-sequence row dated `05/02/2026`.

## 4. Any Existing Report Formats (official PDF/Excel templates, if any)

**Status: UNKNOWN — not supplied.**

If the department already has a mandated report layout (e.g., a specific PDF header,
signature block, or Excel column order used for submission upward), supplying a sample
will let Phase 3 (Reporting) match it exactly instead of a generic layout.

---

## What this means for the rest of this package

Phase 0.5 resolved most of what was flagged as provisional in Phase 0 — the School/AWC
Master field list, the Disease Master, the AWC screening classification fields, and the
plan-import row-classification logic are now grounded in real source material (see
[docs/16_PHASE0_DATABASE_REVIEW.md](docs/16_PHASE0_DATABASE_REVIEW.md) for exactly what
changed). What remains open is narrower and listed above, plus the items in
[docs/12_RISKS_OPEN_QUESTIONS.md](docs/12_RISKS_OPEN_QUESTIONS.md).

**Action needed from you:** the Requires-User-Decision items in
[docs/16_PHASE0_DATABASE_REVIEW.md](docs/16_PHASE0_DATABASE_REVIEW.md) §9 — especially
AWC identity strategy and whether to digitize the full Job Aid clinical checklist or
summary findings only — should be resolved before the schema is frozen for Phase 1.
