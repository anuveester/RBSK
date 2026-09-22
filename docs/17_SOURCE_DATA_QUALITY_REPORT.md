# Source Data Quality Report (Phase 0.5)

Scope: `reference_materials/school_plan.xlsx` (Micro Plan, FY 2025-26, Team-B,
Lalitpur district / Jakhaura block), the 4 Job Aid photographs, and the 1 register
sample photograph. **No source file was modified to produce this report.**

## 1. Workbook structure (factual, no issues)

- 12 sheets, one per month: `APRIL25, MAY25, JUNE25, JULY25, AUG25, SEP25, OCT25,
  NOV25, DEC25, JAN 26, FEB26, MARCH 26` — all visible, no hidden sheets.
- No hidden rows or columns found in any sheet.
- Consistent 14-column data schema (`S.No.` through `Day`) across all 12 sheets; extra
  trailing columns seen in some sheets (up to column X in SEP25) are blank
  formatting-only artifacts, not real data.
- Header block (rows 1–13) is byte-for-byte identical across all 12 sheets: district,
  block, village, team UID, BEO/CDPO contacts, 4 team-member details, column headers.
- Only 3 live formula cells in the entire workbook (JULY25 `N14`, `N21`, `N25`, all
  `=UPPER(TEXT(WEEKDAY(M_),"dddd"))`) — everywhere else, values are hardcoded, including
  the "Day" column on every other row/sheet. Low risk for Phase 2 (no formula-recalc
  dependency), but confirms the workbook was manually built up over time rather than
  templated with live formulas throughout.
- 102 merged-cell ranges in a typical sheet, all confined to the header block
  (rows 1–13) — no merged cells in the data rows themselves.
- A handful of trailing blank-formatted rows exist past the real data in some sheets
  (e.g. JULY25 rows 46–51) — harmless, likely leftover formatting from copying a
  template sheet.

## 2. Row-type distribution

474 total data rows across all 12 sheets:

| Type | Count |
|---|---|
| AWC | 196 |
| SCHOOL | 149 |
| Blank type — SUNDAY | 49 |
| Blank type — PHC REFERRED CHILDREN TREATMENT | 49 |
| Blank type — named public holiday | ~24 (each once) |
| Blank type — no institution name at all | 6 |

Every calendar day of the FY (April 2025 – March 2026) has exactly one row (S.No. =
day-of-month), confirmed across all 12 sheets with no gaps.

## 3. Visit date column — unreliable, high-severity finding

**Full technical explanation and recommended parser fix are in
[16_PHASE0_DATABASE_REVIEW.md](16_PHASE0_DATABASE_REVIEW.md) §7.1 — summarized here as
a data quality fact.**

The raw "Visit date" cell cannot be used as-is for ~all rows with day-of-month ≤ 12
(stored with day/month transposed, inconsistently — some rows in the same sheet are
affected, some aren't) and is stored as unparsed text for day-of-month 13–31. The
"Day" (weekday name) column is reliable and corroborates that the true date is always
`(sheet month/year) + (S.No as day-of-month)`. This is a data entry artifact in the
original file, not something to silently patch in the source — the import parser
should derive dates from sheet+S.No rather than trust the raw date cell.

## 4. School Master — duplicates and code issues

- 149 SCHOOL rows; only **2 have a blank School Code** (98.7% coverage).
- **7 School Codes map to more than one institution name** across the dataset —
  candidate spelling-variant or genuine-discrepancy cases for human review, not
  auto-merged:

| Code | Names found |
|---|---|
| 9370300114 | DHAIYAN DHIMARYANA / DHIM. JAKHORA |
| 9370300601 | NAGVAS / BHADRA |
| 9370300602 | BHADRA / CHAK |
| 9370301901 | LAGAUN / LAGON |
| 9370302301 | VINEKAMAFI / VINAYKAMAFI |
| 9370304403 | (blank name) / BHARATPURA |
| 9370314101 | BANOLI / DURJANPURA |

Of these, `LAGAUN`/`LAGON` and `VINEKAMAFI`/`VINAYKAMAFI` read as plausible spelling
variants of the same name. `NAGVAS`/`BHADRA`/`CHAK` and `BANOLI`/`DURJANPURA` are
genuinely different-looking names sharing a code — these need direct confirmation with
the data owner; **do not auto-resolve either way**.

- Several instances of the *opposite* pattern (same/similar name, different codes)
  were also found, e.g. two schools both named `ANDHIYARI` in SEP25 with codes
  `9370305101`/`9370305102` — these are very likely genuinely distinct schools (e.g.
  separate Primary/Upper Primary sections at the same locality) and should **not** be
  merged; the differing codes are exactly the kind of evidence the brief said to trust.

## 5. AWC Master — code instability (see database review §2 for the full analysis)

- 196 AWC rows; 18 have a blank Anganwadi Code (9.2%).
- The Anganwadi Code column is **not usable as a stable unique identifier** — at least
  15 distinct code values map to clearly different AWC names across sheets (full list
  in [16_PHASE0_DATABASE_REVIEW.md](16_PHASE0_DATABASE_REVIEW.md) §2). This is the
  single most important AWC-side finding and is classified as a **Required Change** to
  the database design, not merely a data quality note — see that document.
- Separately, a recurring **naming convention** was observed and should not be confused
  with the code-instability problem above: AWCs are sometimes listed individually
  (`JAKHAURA-1`, `JAKHAURA-2`, ...) and sometimes as a combined same-day visit entry
  (`JAKHAURA-1+2`) referencing the first AWC's code. This looks like a deliberate
  shorthand for "visited together," not an error, but the import parser needs an
  explicit rule for it (documented in the database review, §7.2).

## 6. Enrollment count (Male/Female/Total) inconsistency

15 of 341 checked rows (4.4%) have `Male + Female ≠ Total`:

| Sheet | Row | Male | Female | Total | M+F |
|---|---|---|---|---|---|
| APRIL25 | 14 | 83 | 130 | 255 | 213 |
| APRIL25 | 34 | 27 | 33 | 63 | 60 |
| MAY25 | 17 | 59 | 58 | 119 | 117 |
| MAY25 | 25 | 59 | 58 | 119 | 117 |
| MAY25 | 47 | 74 | 70 | 134 | 144 |
| MAY25 | 52 | 67 | 59 | 136 | 126 |
| MAY25 | 56 | 74 | 70 | 134 | 144 |
| JUNE25 | 34 | 59 | 58 | 119 | 117 |
| JUNE25 | 43 | 59 | 58 | 119 | 117 |
| JULY25 | 17 | 59 | 58 | 119 | 117 |
| JULY25 | 21 | 59 | 58 | 119 | 117 |
| JULY25 | 35 | 59 | 58 | 119 | 117 |
| JULY25 | 44 | 59 | 58 | 119 | 117 |
| AUG25 | 27 | 86 | 76 | 126 | 162 |
| SEP25 | 32 | 44 | 49 | 84 | 93 |

If this data is retained at all (open question — see database review §7.5), it must be
stored exactly as given, mismatches included, never silently corrected to `Male+Female`.

## 7. Category field inconsistency

- `Category of School` values found: `PS`, `ps` (case-inconsistent), `UPS`, `COM`, and
  — in some rows — an age-range string like `6Y-to-14Y` that looks like it belongs in
  the *Category of Standard* column instead, suggesting occasional column-content
  drift during manual entry.
- `Category of Standard` values found: `10Y-to-13Y`, `10yTO13y`, `6Y-to-10Y`,
  `6Y-to-13Y`, `6Y-to-14Y`, `6YTO14`, `6yTO10y`, `6yTO13y`, `UPS` — same age range
  written with inconsistent capitalization/spacing across rows, plus one instance of
  `UPS` (an institution-type value) appearing in the age-range column.
- `Category of Standard` for AWC rows is a single consistent value, `6MTO6Y`, with no
  inconsistency.
- One `S.No.` value in SEP25 (row 43) was stored as the string `'2 7'` (with an
  embedded space) instead of the integer `27` — a minor typo, flagged for completeness,
  negligible impact since S.No. is used positionally, not as a lookup key, once
  forward-fill logic is applied.

**These are normalization/validation flags for the import parser, not database schema
changes** — see [16_PHASE0_DATABASE_REVIEW.md](16_PHASE0_DATABASE_REVIEW.md) §7.4.

## 8. Spelling/casing inconsistencies (administrative fields)

- District recorded as `laliptur` (lowercase; almost certainly "Lalitpur," a real
  Uttar Pradesh district — likely a typo, not corrected here per the no-invent rule).
- Block recorded as `jakhura` in the District/Block header line, but `jakhaura` in the
  Panchayat/Village line — same place, two spellings, within the same header block.

Not corrected in this report; flagged for the data owner's confirmation, since "do not
invent" extends to not silently picking a canonical spelling on their behalf.

## 9. Team/staff data

No inconsistency found — the 4-person team-B roster (2 Medical Officers, 1 Staff
Nurse, 1 "OPT") is identical across all 12 monthly sheets, indicating no staff turnover
within this FY as captured in this file. One abbreviation ("OPT") is not expanded
anywhere in the source — see [16_PHASE0_DATABASE_REVIEW.md](16_PHASE0_DATABASE_REVIEW.md)
§8.

**Single-team scope:** this file represents only **Team-B**'s plan. If other RBSK teams
(A, C, etc.) exist and should also be onboarded, their micro-plan files have not been
supplied — flagged in
[../SOURCE_MATERIALS_REQUIRED.md](../SOURCE_MATERIALS_REQUIRED.md).

## 10. Job Aid gaps

See [14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md) §9 for the full list:
missing B6/B7 (Deficiency section), missing D10.3.1/D10.3.2 (Autism questionnaire),
unclear D11 numbering at the start/end of that section, unused Disease Master codes
31–38, and the WHO growth-chart lookup tables referenced but not photographed. No
School (6+ years) job aid was supplied at all.

## 11. Register sample — OCR-readiness concerns

See [15_REGISTER_OCR_FIELD_MAPPING.md](15_REGISTER_OCR_FIELD_MAPPING.md) for full
detail. Headline concerns: only one sample supplied (insufficient to tune a real OCR
pipeline); the register's actual column set (Date, School/AWC, Child's Name, combined
Age/Sex, Father's Name, Mother's Name, Disease) does not match the brief's assumed
School Screening register structure (no Class, no Serial No., no separate Refer-To
column) — working hypothesis is that this specific page is a Referred/Disease Line List
or follow-up register rather than the full class screening register, pending
confirmation; the photo requires rotation and perspective correction before OCR; and
handwritten Disease-column values are abbreviated shorthand, not official Disease
Master wording, requiring fuzzy matching in the OCR review step.

## 12. Potential import problems — consolidated punch list

For Phase 2 (plan import) to not corrupt data on first run, the parser must handle, in
order of how much damage getting them wrong would cause:

1. Derive `planned_date` from sheet+S.No, never from the raw Visit Date cell (§3).
2. Forward-fill S.No./date/institution context for blank-S.No. continuation rows (§5,
   database review §7.2).
3. Exclude `PHC REFERRED CHILDREN TREATMENT` and `SUNDAY`/holiday rows from
   `visit_plans`; route holiday-named rows to `holidays`; drop the recurring Saturday
   treatment-activity rows entirely rather than forcing them into either table
   (database review §7.3).
4. Do not enforce or assume uniqueness on `awc_code` (§5).
5. Never fabricate a blank School Code or Anganwadi Code.
6. Do not auto-merge same-code/different-name or same-name/different-code
   institutions — queue for human review (§4, §5).
7. Normalize but don't silently "fix" category field casing/content drift; flag instead
   (§7).
8. Store Male/Female/Total exactly as given if stored at all, mismatches included (§6).
