# Workflows

## D. School Workflow

```
Visit Plan (status=PLANNED, school_id=X, planned_date=today)
  → open School Visit Landing
  → [context] School=X, Date=today (auto)
  → Select Class (once) ──────────────┐
  → Add Child                         │  loop until class done
      → fill base fields              │
      → Normal? → save → Save & Next ─┘
      → Disease? → select Disease (searchable) + Refer To → save → Save & Next
  → Change Class → new class context → repeat Add Child loop
  → Capture Register Photo(s) (any time during or after entry)
  → Complete Visit → counts computed (screened/normal/referred, class-wise,
    gender-wise) → Visit Plan status → COMPLETED
```

Key rule: class context is sticky (PRD FR-7). Disease/Refer To fields are only
presented when the user marks the child as having a finding — never shown by default
for a normal child (PRD FR-6.4).

A child with a finding is *simultaneously* a completed screening record and a new
Referral/Treatment worklist entry — no separate manual step to "create a referral"
(PRD FR-11.1). This is a query-time join (screening has a finding with a referral
destination), not a duplicate write.

## E. AWC Workflow

```
Visit Plan (status=PLANNED, awc_id=Y, planned_date=today)
  → open AWC Visit Landing
  → [context] AWC=Y, Date=today (auto)
  → Add Child
      → Preliminary particulars (ASHA, guardian, contact, MCTS/Aadhaar where applicable)
      → Anthropometry (weight, height/length, head circumference, MUAC)
        → classification computed/selected per official criteria (TBD — Job Aid)
      → Findings by category (Defects at Birth / Deficiencies / Diseases /
        Developmental Delay & Disability / Others) — multi-select
      → Developmental screening
      → If any finding present → Referral destination
      → Doctor/MHT info, register reference
      → save → Save & Next
  → Capture Register Photo(s)
  → Complete Visit → counts computed
```

Same "finding → automatically in Referral/Treatment worklist" rule as School.
AWC has no class-session concept (PRD explicitly scopes class-session stickiness to
School).

## F. Referral / Treatment Workflow

```
Screening record has finding + referral destination
  → appears in Referral/Treatment Worklist (status=PENDING, derived from
    Attended=NO/Treatment=NOT DONE defaults, not a stored "pending" flag)
  → on treatment day, open worklist → select child
  → Treatment Entry Form:
      Child Attended:      default NO   → set YES/NO
      Treatment:           default NOT DONE → set DONE/NOT DONE
      Further Referral:    default NO   → set YES/NO
        if YES → Further Referral Destination (PHC/CHC, District Hospital,
                  Higher Center) + remarks become required
  → save (creates a new treatment_records row; does not overwrite prior visits)
  → child may recur in worklist for a future treatment date if still pending or
    further-referred
```

Defaults are never silently upgraded to positive values by the system (PRD FR-11.3) —
this is a deliberate accountability control, not an oversight to "fix" later.

## G. Register Photo / OCR Workflow

```
CAMERA / GALLERY
  → CAPTURE PHOTO(S) (attached to current visit, works fully offline)
  → SAVE ORIGINAL (local encrypted storage; queued for cloud upload)
  → [local] IMAGE QUALITY CHECK (blur/glare/crop heuristic; re-capture prompt if poor)
  ── offline boundary — everything below requires connectivity, runs later ──
  → CLOUD UPLOAD (via sync engine, independent of row-data sync — see
    07_OFFLINE_SYNC_ARCHITECTURE.md)
  → IMAGE PROCESSING (deskew, table/row detection)
  → OCR / HANDWRITING RECOGNITION (cloud engine)
  → FIELD EXTRACTION → OCR result rows with per-field confidence
  → [in-app] USER REVIEW
      → low-confidence fields visually flagged
      → duplicate-warning if extracted child resembles an existing record for this
        visit/class
      → EDIT IF REQUIRED
  → CONFIRM (per row or batch)
  → SAVE as real school_screening / awc_screening record, linked back to source photo
```

**Hard rule (PRD FR-13.2):** no extracted row becomes a real screening record without
explicit user confirmation. The OCR result table and the screening tables are distinct;
promotion is an explicit, auditable action.

## Holiday / Missed / Reschedule Workflow

```
Visit Plan (status=PLANNED)
  ├─ visit happens as planned → IN_PROGRESS → COMPLETED
  └─ visit cannot happen
       → mark MISSED (reason: School Closed / Holiday / Team Unavailable /
         Official Duty / Weather / Other)
       → [visit_status_history row appended; original_planned_date untouched]
       → later: Reschedule → new planned_date set, status → RESCHEDULED
       → visit happens on new date → IN_PROGRESS → COMPLETED
```

If reason = Holiday and the date is not already in the Holiday Calendar, the UI offers
to add it in the same flow (not required — a holiday can also be marked purely as a
missed-visit reason without a calendar entry, e.g. a one-off local closure that isn't a
recognized holiday).

## Special Visit Workflow

```
+ Special Visit
  → pick any date (Saturday/Sunday/any day outside the plan)
  → select School or AWC (search)
  → reason (free text, e.g. "Ordered visit")
  → confirm → creates a new visit_plans row, is_special_visit=true,
    original_planned_date = chosen date (there is no prior "plan" to preserve)
  → proceeds through the normal School/AWC visit workflow above
```
