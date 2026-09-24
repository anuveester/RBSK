# Micro Plan workbook — file format (verified)

Verified on 2026-09-24 against the real file `PLAN_25-26-B__Repaired__1.xlsx`
(Team-B, block jakhura, FY 2025-2026) by running every rule over all 12 sheets.
This replaces the earlier draft of this document, which was written without
opening the real file and was wrong about the header rows, the columns and dates.

## Sheets
12 sheets, one per month: `APRIL25 … DEC25`, `JAN 26`, `FEB26`, `MARCH 26`.
Some names contain a space. The parser reads the month and year from the name.

## Top of each sheet (rows 1–11)
| Row | Content |
|-----|---------|
| 3 | `MICRO PLAN/ACTION PLAN OF  YEAR 2025-2026` → financial year label |
| 4 | `District :` → `laliptur` (source spelling, kept as written), `Block :` → `jakhura`, `Panchayat/Village :` → `jakhaura` |
| 5 | `Dedicated Team UID :` → `Team - B` |
| 7–11 | BEO, CDPO and team staff names and mobile numbers (not parsed in this step) |

Each value is the next non-blank cell to the right of its label.

## Table
Header on row 12 (column A starts with `S.No.`) plus a second header row 13.
Data starts on row 14.

| Col | Content |
|-----|---------|
| A | S.No. (one number per visit day) |
| B | Institution name, or SUNDAY / holiday / event text |
| C | `SCHOOL` or `AWC` (blank for non-institution rows) |
| D | Anganwadi code (small integer; non-authoritative, see docs/04 §2.2) |
| E | School code (10 digits) |
| F | Category of school (PS / UPS / COM; some AWC sheets put an age band here) |
| G | Category of standard (6yTO10y, 6Y-to-10Y, 6MTO6Y, … many spellings) |
| H, I, J | Male, Female, Total — stored as given, never reconciled |
| K, L | Contact person, contact number |
| M | Visit date |
| N | Day name |

If the header labels are not in these positions the sheet is refused
(`columnLayoutUnexpected`) rather than guessed.

## Row kinds (docs/01_PRD.md FR-2.1)
Real file: 149 SCHOOL, 196 AWC, 49 SUNDAY, 49 treatment-day
(`PHC REFERRED CHILDREN TREATMENT`), 25 holidays, 1 stray cell.

## Merged cells
Several institutions visited on the same day are separate rows; S.No. (A),
date (M) and day (N) are vertically merged across them, and sometimes the
name (B) too (e.g. `JAKHAURA-1+2` over AWC codes 1 and 2). Single-column
vertical merges in A, B, M, N are carried down. A carried name is flagged
(`nameSharedWithRowAbove`) — the parser never splits or invents names.

## Visit dates
Excel mangled the dates in two ways:
- Days 1–12 were stored as real dates with **day and month swapped**
  (1 April → 4 January).
- Days 13–31 stayed as text `D/M/YYYY`.

Rule: of the possible readings, take the one that falls in the sheet's month;
flag `dateDayMonthSwapped` when a swap was needed. Then compare with the Day
column; 3 rows in the real file disagree (`dayNameMismatch`, kept for review —
neither the date nor the day is "corrected").

## Data-quality flags on the real file
| Flag | Rows |
|------|------|
| dateDayMonthSwapped | 166 |
| nameSharedWithRowAbove | 26 |
| awcCodeMissing | 18 |
| countTotalMismatch | 15 |
| contactNumberNot10Digits | 5 |
| countMissing | 4 |
| dayNameMismatch | 3 |
| schoolCodeMissing | 2 |
| schoolCodeUnusual (11 digits) | 1 |
| unrecognisedRow | 1 |

## Code
- `lib/domain/services/micro_plan/` — pure-Dart parser (no DB, no Excel package).
- `tool/micro_plan/micro_plan_ref.py` — Python reference of the same rules.
- `tool/micro_plan/gen_fixture.py` — regenerates the anonymised test fixture
  and the expected per-row results from the real file:
  `python gen_fixture.py <xlsx> ../../test/fixtures/micro_plan/real_plan_2025_26.dart ../../test/fixtures/micro_plan/real_plan_2025_26_expected.dart`
  (staff rows removed; contact names/numbers replaced).
