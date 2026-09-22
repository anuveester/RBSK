# Register Photo — OCR Field Mapping (Phase 0.5) — SUPERSEDED

> **⚠ Superseded by [18_REGISTER_SAMPLE_ANALYSIS.md](18_REGISTER_SAMPLE_ANALYSIS.md)
> (Phase 0.6).** Seven high-resolution photographs of the real register have since been
> supplied and are authoritative. This document is retained for traceability only.
>
> **Known error in this document:** the frequent Disease-column value read here as
> "Cornea"/"corneal" from the low-resolution image is actually **"Carries"/Caries**
> (dental) — confirmed at higher resolution. Other conclusions below (no Class column,
> no Refer-To column, hand-ruled notebook, Latin script, abbreviated disease shorthand)
> were confirmed correct.

Source: `reference_materials/register_samples.jpeg` — **one** photograph of a physical
ruled-notebook register page, handwritten. This is a single sample; conclusions below
are based on this one page and should be treated as a working hypothesis, not a
confirmed generalization across every register the team keeps — see §5.

## 1. Physical characteristics

- Ruled exercise-book/notebook page (vertical rule lines forming columns, horizontal
  rule lines forming rows), not a pre-printed government form. **This is an
  unstructured register, not a structured form** — there are no printed column
  headers or boxes on the page itself; the columns are simply where the writer chose
  to write, separated by hand-drawn or the notebook's own ruling.
- The photo was taken with the phone rotated ~90° relative to reading orientation (the
  page needs to be rotated to read normally). **Perspective correction and rotation are
  both needed** before any OCR step — not just rotation, since the page also shows
  slight keystone distortion typical of a handheld phone photo of a book page.
- Handwriting is in **Latin script (English) only** in this sample — no Devanagari
  observed. This is a useful data point against the earlier assumption (carried over
  from the sibling MedStore Validation project) that Devanagari OCR would be needed;
  **do not generalize from one sample** — confirm with more register photos, especially
  from different team members, since handwriting language/script can vary person to
  person.
- Handwriting quality: mixed cursive/print, moderately legible but with genuine
  ambiguity in places (e.g. some names are hard to disambiguate with full confidence
  even for a human reader). This confirms the Phase 0 decision to require mandatory
  human review of OCR output (see
  [09_OCR_REGISTER_PHOTO_ARCHITECTURE.md](09_OCR_REGISTER_PHOTO_ARCHITECTURE.md)) — no
  change needed there.

## 2. Observed column structure

Reading the page in its intended orientation, the columns are:

| # | Header (as legible) | Sample values |
|---|---|---|
| 1 | Date | 09/07/2026, 10/07/2026, 13/07/2026, 15/07/2026 |
| 2 | School/Anganwadi | P.S. Chhipai, P.S. Pathla, Com. Kalyanpura, P.S. Banoli, UPS Banoli, P.S. Sirsontkala (spelling approximate) |
| 3 | Child's Name | ~19 names visible across the page |
| 4 | Age Sex | combined single column, e.g. "6y M", "7y F", "8y M", "10y F" |
| 5 | Father's Name | |
| 6 | Mother's Name | |
| 7 | Disease | short values: "Vit A", "Cornea"/"corneal", "S.I", and similar abbreviations |

**Important discrepancy from the brief's assumed School Screening register
structure** (PRD FR-6.2, which lists Serial No., Date, Class, Child Name, Age, Gender,
Mother Name, Father Name, Disease, Refer To): this sample has **no visible Class
column, no visible Serial No. column, and no visible separate Refer-To/destination
column** — Age and Sex are combined into one column rather than separate fields, and
there is no distinct referral-destination field alongside Disease.

**Working hypothesis, flagged for confirmation, not assumed as fact:** every row on
this photographed page has a Disease/finding value — there is no row that reads
"Normal". This suggests the photographed page is **not** the full class screening
register (which would include every child, normal and affected) but rather a
**Referred/Disease Line List or a follow-up (e.g. Vitamin A distribution) register** —
i.e. a page that only logs children who already have a finding. This would explain the
missing Class and Refer-To columns (not needed on a page that's already scoped to
"children with a finding") and is consistent with the brief's own description of a
"Referred Child Line List" as a distinct entity.

**Action needed:** confirm with the Medical Officer (a) what this specific register
book is used for, (b) whether a separate full class-screening register exists (with
Serial No./Class/Normal-or-Disease/Refer-To columns) and can be photographed too, and
(c) whether "Disease" column abbreviations like "S.I" have a fixed meaning to preserve
in OCR post-processing. Do not assume the answer — this materially affects which
register type the OCR pipeline should be tuned for first.

## 3. Row structure

- One child per row, consistently, across the whole visible page (no multi-child rows
  observed).
- Serial numbers: **not clearly present** as their own column in this sample (a narrow
  sliver at the image edge may be a serial/index column but is not clearly legible —
  REVIEW REQUIRED, request a photo with that edge fully in frame).
- Date format: `DD/MM/YYYY` (e.g. "09/07/2026"), and appears to be written **once at
  the top of a same-day cluster of rows**, not repeated per row within that cluster —
  mirroring the same "date applies to the following consecutive rows" convention seen
  in the Excel Micro Plan (see
  [17_SOURCE_DATA_QUALITY_REPORT.md](17_SOURCE_DATA_QUALITY_REPORT.md)). The OCR field
  extraction logic should carry a date forward to blank-date rows within a visible
  same-page cluster, the same way the plan-import parser needs to.
- Disease shorthand: entries appear to be **hand-abbreviated versions of official
  Disease Master terms** (e.g. "Vit A" for Vitamin A Deficiency, code 11 in
  [14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md)), not the full official
  wording. **The OCR review UI cannot rely on exact string match against
  `disease_master.name`** — it needs fuzzy/abbreviation matching with the extracted
  text shown alongside the matched candidate for the reviewer to confirm or correct
  (this refines, but does not change, the duplicate/fuzzy-matching design already in
  [09_OCR_REGISTER_PHOTO_ARCHITECTURE.md](09_OCR_REGISTER_PHOTO_ARCHITECTURE.md)).

## 4. OCR design implications

| Question (from Phase 0.5 objective) | Answer based on this sample |
|---|---|
| Row-based, table-based, cell-based, or hybrid? | **Hybrid, leaning row-based.** The page has clear horizontal ruling (reliable row boundaries) but weak/no vertical column structure (hand-ruled or notebook-default columns, not a fixed grid) — recommend row-level detection first, then within-row field segmentation trained/tuned on the actual column order the team uses (which itself may not be perfectly consistent row to row — see risk below). |
| Preprocessing needed | Perspective correction (document-boundary detection + deskew), rotation correction, contrast normalization. Blur was not a problem in this sample but should still be checked per-photo (per the existing pipeline's quality-check stage). |
| Confidence tuning | Cannot be meaningfully tuned from a single sample — defer until more samples are available (see §5). |
| Script/language | Latin/English only in this sample; do not assume this generalizes to every team member's handwriting. |

**No claim of high OCR accuracy is made here or should be made later** — this is an
unstructured, hand-ruled register with genuine handwriting ambiguity, which is exactly
why [09_OCR_REGISTER_PHOTO_ARCHITECTURE.md](09_OCR_REGISTER_PHOTO_ARCHITECTURE.md)'s
mandatory-human-review design is the right call, not a fallback for a rare edge case.

## 5. What's still needed before OCR tuning is meaningful

One sample is not enough to design a production OCR pipeline against. Before Phase 5
(OCR), request:

1. Several more photos of the **same** register type from different team members (to
   see how much handwriting/column-order variance exists across the team).
2. If a separate full class-screening register exists (see §2 hypothesis above), photos
   of that too — it may have a meaningfully different structure (Class, Refer-To
   columns) requiring its own field mapping.
3. Confirmation of whether registers are always this hand-ruled notebook style, or
   whether some teams/books use a pre-printed structured form (which would be a much
   easier OCR target).

This is tracked in [../SOURCE_MATERIALS_REQUIRED.md](../SOURCE_MATERIALS_REQUIRED.md).
