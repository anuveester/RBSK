# Product Requirements Document

## 1. Purpose & Product Principle

Digitize RBSK field operations (school/AWC screening, referral, treatment follow-up,
reporting) for an 8–10 person team, without making the daily workflow feel like
enterprise software. The benchmark is: *does this feel at least as simple as maintaining
a paper register?* Every screen design decision should be checked against that.

Concretely: minimize typing, maximize dropdowns/search/buttons/checkboxes, remember
context (school, date, class) across consecutive entries, auto-compute serial numbers,
dates, and counts.

## 2. User Roles

| Role | Description | Key permissions |
|---|---|---|
| **ADMIN** | Typically the Medical Officer-in-charge or a designated lead | Full access: user management, master data (School/AWC/Disease), staff assignment history, holiday calendar, all reports, backup export |
| **MEDICAL OFFICER** | Conducts/oversees screenings | Create/edit visits, screenings, referrals, treatment records, register photos; view all reports; cannot manage users or edit Disease Master |
| **TEAM MEMBER / DATA ENTRY** | Support staff entering data in the field | Create/edit visits, screenings, register photos under an assigned visit; cannot edit master data, cannot manage referrals' final disposition beyond entry, view own-team reports |

Exact permission boundaries per screen are enumerated in
[04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §RBAC Matrix. This is a
foundation, not a complex ACL system — three roles is intentional (brief §25: "do not
overcomplicate permissions").

## 3. Functional Requirements

### FR-1 Master Data
- FR-1.1 School Master: unique per school regardless of how many plan dates reference it.
- FR-1.2 AWC Master: separate from School Master, unique per AWC.
- FR-1.3 Official School/AWC codes preserved verbatim from source; blank stays blank,
  never fabricated. Internal UUID always present regardless.
- FR-1.4 Master records support Active/Inactive, never hard delete.

### FR-2 Annual Plan Ingestion
- FR-2.1 Import the annual Micro Plan (Excel) for a Financial Year, classifying each row
  by type (SCHOOL, AWC, SUNDAY, HOLIDAY, EVENT, other) — never treat non-school/AWC rows
  as schools.
- FR-2.2 Deduplicate schools/AWCs appearing on multiple plan dates into one master
  record; each date becomes its own Visit Plan row referencing that master record.
- FR-2.3 Import is reviewable before commit (import staging + confirm), consistent with
  "never commit unverified data automatically" (same principle as OCR, FR-9).

### FR-3 Visit Planning
- FR-3.1 Visit Plan carries Financial Year, planned date, location type (SCHOOL/AWC),
  target, status, and **original planned date**, which is never overwritten.
- FR-3.2 Status lifecycle: `PLANNED → IN_PROGRESS → COMPLETED`, or
  `PLANNED → MISSED → RESCHEDULED → COMPLETED`. Every transition is logged
  (who/when/why), not just the current status.
- FR-3.3 Special Visits: any authorized user can create an ad-hoc visit on a
  Saturday/Sunday/any date outside the plan, explicitly flagged as a Special Visit, with
  a reason.

### FR-4 Holiday Management
- FR-4.1 Holidays imported from the annual plan populate the Holiday Calendar.
- FR-4.2 Any authorized user can add an unplanned holiday (date, name, reason) at any
  time; it remains in history permanently.
- FR-4.3 A visit affected by a holiday can be traced to that holiday record internally
  (for missed-visit explanation), without necessarily surfacing this plumbing in
  standard reports.

### FR-5 Missed / Rescheduled Visits
- FR-5.1 A visit that cannot happen on its planned date is marked MISSED with a reason
  (School Closed, Holiday, Team Unavailable, Official Duty, Weather, Other) without
  blocking any other visit's workflow.
- FR-5.2 A missed visit can later be rescheduled; the system retains original planned
  date, missed reason, rescheduled date(s), and actual completion date — full history,
  not just the latest state.

### FR-6 School Screening
- FR-6.1 Applies to Class 1–12. One screening record per child per visit.
- FR-6.2 Required base fields regardless of finding: Serial No. (auto), Date (auto from
  visit), Class (from session context), Child Name, Age, Gender, Mother Name, Father
  Name.
- FR-6.3 If a disease/condition is found: Disease (searchable select) and Refer To
  (PHC/CHC, District Hospital, Higher Center) are additionally required. A child can
  have more than one finding.
  **Phase 0.5 update:** no official School screening/referral document has been
  supplied — this referral vocabulary is unverified brief text, unlike AWC's (now
  confirmed as PHC/CHC/DH/DEIC/NRC, category-dependent, per
  [14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md) §8). Whether School should
  adopt the same expanded vocabulary is an open decision — see
  [16_PHASE0_DATABASE_REVIEW.md](16_PHASE0_DATABASE_REVIEW.md) §3.
- FR-6.4 A normal child (no finding) never requires the Disease/Referral fields to be
  touched.

### FR-7 Class Session Context
- FR-7.1 Within a School Visit, the user selects School, Date (auto), and Class **once**.
  Every subsequent child entry defaults to that context until the user explicitly
  changes class via a "Change Class" action.
- FR-7.2 "Save & Next" returns the user directly to a blank child-entry form with
  context preserved, auto-incrementing the serial number.

### FR-8 AWC Screening
- FR-8.1 Separate screening engine from School Screening, covering the 0–6 years RBSK
  workflow.
- FR-8.2 Field set follows the official RBSK Job Aid structure (preliminary particulars,
  child info, ASHA/AWC details, guardian/contact, MCTS/Aadhaar where applicable,
  anthropometry — weight/height/head circumference/MUAC — and classification, the four
  finding categories, developmental screening, referral outcome, doctor/MHT info, visit
  date, register reference).
  **Phase 0.5 update:** the Job Aid photographs have since been supplied and fully
  transcribed in [14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md) — the
  official anthropometry classification option lists and the codified 29-item Disease
  Master are now confirmed. What's still open is a scope question, not a data
  question: the Job Aid's full clinical checklist (Sections A–D, 100+ discrete items)
  is far more granular than a flat finding-selection form — see
  [16_PHASE0_DATABASE_REVIEW.md](16_PHASE0_DATABASE_REVIEW.md) §6 for the summary-vs-
  full-checklist decision this PRD's FR-8.2 currently assumes is answered "summary."

### FR-9 Disease / Referred Line List
- FR-9.1 A dedicated filterable view showing only children with at least one finding
  (not the full screened population), filterable by disease, date, school, class,
  referral destination, financial year, month.
- FR-9.2 All screened children (normal and referred) remain in the underlying screening
  tables; this view is a query, not a separate copy of data.

### FR-10 Disease Master
- FR-10.1 Sourced from the official RBSK Job Aid categories (Defects at Birth,
  Deficiencies, Diseases, Developmental Delay & Disability, Others). Official codes
  preserved where present. **Pending Job Aid photographs** for the authoritative item
  list — do not invent entries beyond what the brief already names as categories.
- FR-10.2 Searchable selection UI; no free-text disease entry in normal flow (a
  controlled "Other — specify" escape hatch may exist but is flagged for review, not
  assumed).

### FR-11 Referral / Treatment Follow-up
- FR-11.1 A child with any finding + referral destination automatically appears in the
  Referral/Treatment worklist — no duplicate manual entry.
- FR-11.2 Treatment record fields: child/school/AWC reference, original screening date
  and disease, original referral destination, treatment visit date, Child Attended,
  Treatment status, Further Referral, Further Referral Destination, remarks.
- FR-11.3 **Defaults are intentional and must not be pre-filled positive:**
  `Child Attended = NO`, `Treatment = NOT DONE`, `Further Referral = NO`. The user must
  explicitly change these.
- FR-11.4 If Further Referral = YES, Further Referral Destination (PHC/CHC, District
  Hospital, Higher Center) and remarks become visible/required.
- FR-11.5 A child may have multiple treatment follow-up records over time (repeat
  visits); all are retained.
- FR-11.6 Treatment worklist filterable: pending, completed, did-not-attend, needs
  further referral, disease-wise, destination-wise, date/school/month/FY-wise.

### FR-12 Register Photo Archive
- FR-12.1 Every physical register page photographed on a visit is permanently
  preserved, associated with School/AWC, visit, date, class (where applicable), user,
  timestamp.
- FR-12.2 A visit may have multiple photos; all are viewable later from the visit detail
  screen.
- FR-12.3 Photos are never deleted automatically, including after OCR extraction is
  reviewed and confirmed.

### FR-13 OCR / AI-Assisted Extraction
- FR-13.1 Pipeline: capture → save original → quality check → image processing → row/
  table detection → OCR → field extraction → **user review** → edit if required →
  confirm → save.
- FR-13.2 OCR output never auto-commits a child record. A human must confirm (per row,
  or per batch with per-field override) before it becomes a real screening record.
- FR-13.3 Low-confidence fields are visually flagged for the reviewer.
- FR-13.4 Extracted records link back to their source photo for traceability.
- FR-13.5 Duplicate detection: warn if an extracted child appears to already exist for
  that visit/class (name + approximate match), without silently blocking entry.

### FR-14 Staff / Team History
- FR-14.1 Staff assignments (who was on the team, in what capacity, for which dates) are
  additive history, never overwritten. A transfer creates a new assignment row with a
  start date; it does not edit the outgoing staff member's row.
- FR-14.2 Historical reports/records reflect the staff configuration in effect on the
  date the activity occurred, not the current configuration.

### FR-15 Reporting
- FR-15.1 Report catalog per brief §21 (Overall, School-wise, AWC-wise, Date-wise,
  Screening, Disease-wise, Referral, Treatment/Follow-up, Monthly, Quarterly, Month
  Selection, Financial-Year-wise, Class-wise, Gender-wise, Missed Visit, Pending
  Treatment).
- FR-15.2 Date-range reports support explicit From/To; monthly reports support
  Month+Year selection; Financial Year reports use April→March.
- FR-15.3 Every report is exportable as PDF and Excel and shareable via the Android
  system share sheet (WhatsApp, Email, Drive, etc. — no direct API integration
  assumed).

### FR-16 Offline & Sync
- FR-16.1 All field data entry (visits, screenings, photos, treatment records) works
  fully offline.
- FR-16.2 Sync status is visible per record and globally: Synced, Pending Sync, Sync
  Error.
- FR-16.3 No data loss on connectivity interruption at any point.

### FR-17 Security & Access
- FR-17.1 Authenticated access only, no self-registration; ~8–10 named accounts managed
  by ADMIN.
- FR-17.2 Role-based access enforced both client-side (UX) and server-side (RLS —
  defense in depth).
- FR-17.3 Every important record tracks Created By/At, Updated By/At; soft-delete only.

## 4. Non-Functional Requirements

| ID | Requirement |
|---|---|
| NFR-1 | App must be usable by a non-technical Medical Officer with minimal training — see Product Principle. |
| NFR-2 | Full offline capability for all data-entry workflows; sync is best-effort background, never blocking. |
| NFR-3 | No data loss under connectivity loss, app crash, or device restart mid-entry (autosave / draft persistence per form). |
| NFR-4 | Historical data (visits, screenings, staff assignments, disease findings) must remain accurate as of the date recorded, immune to later master-data edits. |
| NFR-5 | Child health data protected at rest (encrypted local DB) and in transit (TLS); access limited to authenticated, authorized users. |
| NFR-6 | Must support multiple financial years of historical data without performance degradation (target: 5+ years, thousands of screening records). |
| NFR-7 | Designed for 8–10 concurrent named users; not architected for public/mass-user scale. |
| NFR-8 | Report generation (PDF/Excel) for a financial year's data completes in a few seconds on a mid-range Android device. |
| NFR-9 | App maintainable by a small (possibly solo) developer going forward — avoid unnecessary architectural complexity. |
| NFR-10 | Android-first; iOS not required unless stated otherwise (open question — see [12_RISKS_OPEN_QUESTIONS.md](12_RISKS_OPEN_QUESTIONS.md)). |

## 5. User Journeys

### UJ-1: Daily School Visit (happy path)
Open app → **Today's Visit** (auto-surfaced from Visit Plan) → confirm School →
select Class once → repeatedly: enter child (Save & Next) → mark Normal, or mark
Disease + Refer To → at end of class, optionally **Change Class** and continue → capture
register photo(s) for the visit → close visit (auto status → COMPLETED, counts
computed).

### UJ-2: Unplanned Holiday Disrupts a Visit
Field team arrives to find the school closed for an unannounced local holiday →
open Visit Plan for today → mark **Missed**, reason = Holiday → add the holiday to the
Holiday Calendar (if not already present) → visit remains in Missed Visits list →
later, create a **Reschedule** to a new date → complete as normal.

### UJ-3: Sunday Special Visit Ordered by Superior
Team is instructed to visit School X on Sunday → **+ Special Visit** → select date
(Sunday, outside normal plan) → select School X → confirm reason → visit proceeds
exactly like a normal school visit screen-wise.

### UJ-4: Child Found with a Condition → Referral → Treatment Follow-up
During screening, child is marked with a Disease and Refer To = PHC/CHC → child
automatically appears in Referral/Treatment worklist as Pending (defaults: Attended=NO,
Treatment=NOT DONE, Further Referral=NO) → on a later Saturday treatment day, open the
worklist → select child → mark Attended=YES, Treatment=DONE (or update accordingly) →
if further referral needed, set Further Referral=YES and select destination → save.

### UJ-5: Register Photo → OCR-Assisted Entry
At the end of a visit, Medical Officer photographs the physical register page(s) →
photos saved and queued → when connectivity is available, OCR job runs in background →
Medical Officer opens **OCR Review** → sees extracted rows with low-confidence fields
highlighted → corrects fields → confirms → confirmed rows become real screening records
linked to the source photo.

### UJ-6: Monthly Report to Submit Upward
ADMIN or Medical Officer opens **Reports** → selects "Monthly Report" → Month + Year →
preview → **Export PDF** (or Excel) → **Share** via Android share sheet to WhatsApp/
Email/Drive.

### UJ-7: Staff Transfer Mid-Year
A team member is transferred out and replaced → ADMIN opens **Staff Management** →
closes the outgoing member's current assignment (sets end date) → adds a new assignment
for the incoming member (start date = today) → all historical visits/reports involving
the outgoing member remain unchanged and correctly attributed.

## 6. Explicitly Out of Scope (Phase 0)

- Public/patient-facing access.
- Direct WhatsApp/SMS API integration (system share sheet only).
- iOS support (unless confirmed needed — open question).
- Real-time multi-user collaborative editing of the same record.
- Automated medical decision support (the app records findings; it does not diagnose).
