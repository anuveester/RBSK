# Reporting & Export Architecture

> **Phase 0.5 reporting impact review:** checked the 16-report catalog below against the
> real Micro Plan and Job Aid. No additional report type is clearly demanded by the
> source data — the existing "Referral Report" and "Disease-wise Report" already cover
> the newly-confirmed DEIC/NRC/DH-specific routing (it's a filter value change, not a
> new report), and the weekly "PHC Referred Children Treatment" Saturday pattern found
> in the plan reinforces the existing "Pending Treatment Report" rather than requiring
> a new one. One filter refinement is now possible and recommended: the Referral and
> Disease-wise reports' "referral destination" filter should offer the confirmed
> PHC/CHC/DH/DEIC/NRC values (§ [16_PHASE0_DATABASE_REVIEW.md](16_PHASE0_DATABASE_REVIEW.md)
> §3) once that enum change is applied, instead of the original 3-value placeholder.

## Report catalog (per PRD FR-15.1 / brief §21)

| # | Report | Primary filters |
|---|---|---|
| 1 | Overall Report | FY, date range |
| 2 | School-wise Report | School, FY/date range |
| 3 | AWC-wise Report | AWC, FY/date range |
| 4 | Date-wise Report | From/To date |
| 5 | Screening Report | FY, date range, school/AWC |
| 6 | Disease-wise Report | Disease, FY/date range |
| 7 | Referral Report | Destination, FY/date range |
| 8 | Treatment/Follow-up Report | Status (pending/done/attended), FY/date range |
| 9 | Monthly Report | Month + Year |
| 10 | Quarterly Report | Quarter + FY |
| 11 | Month Selection Report | Month + Year (generic month picker variant of #9) |
| 12 | Financial-Year-wise Report | FY |
| 13 | Class-wise Report | Class, FY/date range |
| 14 | Gender-wise Report | Gender, FY/date range |
| 15 | Missed Visit Report | FY/date range, reason |
| 16 | Pending Treatment Report | FY/date range |

All date-range reports support explicit From/To; monthly reports select Month+Year;
Financial Year reports use April→March (`financial_years` table, never a recomputed
calendar-year range).

## Data source for a report: local vs. cloud

Two modes, both backed by the **same query layer** (report queries are written once
against the domain/repository layer, not duplicated per data source):

- **"My Device Data" (default, always available offline):** queries the local SQLite
  copy. Instant, works anywhere, but reflects only what has synced *to* this device
  (may be missing another team member's not-yet-synced entries).
- **"All Team Data" (requires connectivity):** queries Supabase directly (or a local
  copy freshly pulled), for reports that need to be complete across the whole team
  (e.g. a monthly submission report). The UI makes this distinction explicit — a report
  screen shows "as of last sync: <timestamp>" so nobody submits an incomplete report
  believing it's complete.

## Counts: computed, not stored

Per brief §12 ("avoid contradictory totals"), all counts (total screened, normal,
referred, class-wise, gender-wise, disease-wise) are computed via aggregation queries
over `school_screenings`/`awc_screenings` + their findings join tables at report-
generation time — never maintained as separately-stored running totals that could drift
out of sync with the underlying rows. If report-generation performance ever becomes an
issue at scale (unlikely at 8–10 users / a few thousand records/year), a materialized
view or cached summary table can be added later purely as a performance optimization,
without changing what the source of truth is.

## PDF export

- `pdf` (layout) + `printing` (render/share) — Flutter packages, fully offline capable.
- A shared report-template layer (header with FY/date range/filters applied, a summary
  block, a detail table, generated-by/generated-at footer) is used by every report type,
  so reports look consistent without 16 bespoke layouts.

## Excel export

- `excel` package — one worksheet per report (or one row-per-record sheet for detail
  reports like the Referred Line List), offline capable.

## Sharing

- `share_plus` invokes the Android system share sheet — user picks WhatsApp, Email,
  Drive, or any installed app. No direct API integration with any of these (brief §22).

## Report generation log (optional, low priority)

A `report_generation_log` table (report_type, filters snapshot, generated_by,
generated_at, output format) could track "who generated what, when" for audit purposes.
Not included in the Phase 0 core schema (§04) since it's a nice-to-have, not a
correctness requirement — can be added additively in a later phase without touching any
existing table.
