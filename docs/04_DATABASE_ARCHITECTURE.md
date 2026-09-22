# Database Architecture — FROZEN v1.0 (Phase 0.6)

Design principles, in priority order: **historical immutability > offline-sync safety >
normalization purity > convenience**.

> **Status: FROZEN for Phase 1 implementation (Phase 0.6).**
> All Phase 0.5 Required Changes have been applied, plus the user decisions confirmed
> at the start of Phase 0.6 (AWC code strategy, full AWC screening form, context-specific
> referral destinations, OPT = Optometrist). Remaining `TBD` items are explicitly
> **nullable and unused** rather than guessed at — they do not block Phase 1. Any change
> to this schema after this point should be a deliberate, versioned migration, not an
> ad-hoc edit. Change log at §9.

Tagging used throughout this document:
**[CONFIRMED]** verified against source material · **[SOURCE-DERIVED]** taken directly
from the Micro Plan / Job Aid / register · **[USER-DECIDED]** decided by the product
owner in Phase 0.6 · **[TBD]** unresolved, needs source or confirmation ·
**[NOT YET IMPLEMENTED]** designed but deliberately out of Phase 1 scope.

## 0. Cross-cutting conventions

- **Primary keys are client-generated UUIDv4**, never autoincrement integers — required
  for offline-first multi-device inserts. The same UUID identifies the same row in both
  local SQLite (Drift) and cloud Postgres; sync is an upsert by primary key.
  **[CONFIRMED]**
- **Official government codes are nullable business identifiers, never the database
  identity.** A blank official code in the source stays blank — never invented, never
  back-filled. **[USER-DECIDED]**
- **Unreliable source-plan values are stored separately from official identifiers** and
  never carry uniqueness constraints (see `awcs`, §2.2). **[USER-DECIDED]**
- **Every mutable business table** has: `created_by`, `created_at`, `updated_by`,
  `updated_at`, `row_version integer not null default 1`, `is_deleted boolean not null
  default false`, `deleted_by`, `deleted_at`.
- **Append-only history tables** (`visit_status_history`, `staff_assignments`,
  `audit_log`, `ocr_results`) are insert-only — no soft-delete/version machinery.
- **No hard deletes** anywhere in the business schema.
- **Financial Year is a first-class lookup** (April→March), never a derived string.
- **Planned/enrollment figures are never mixed with actual screening counts** — see
  `visit_plans.planned_*` (§2.3) vs. computed screening aggregates (§7).
  **[USER-DECIDED]**

## 1. ERD (readable form)

```
financial_years ──┬──< visit_plans >──┬── schools
                  │                   ├── awcs
                  │                   └──< visit_status_history

visit_plans ──┬──< screening_sessions ──< school_screenings
              │                             └──< school_screening_findings
              ├──< awc_screenings ──┬──< awc_screening_findings
              │                     └──< awc_screening_checklist_responses
              └──< register_photos ──┬──< register_photo_derivatives
                                     └──< ocr_jobs ──< ocr_results

disease_master ──< school_screening_findings
               ──< awc_screening_findings

referral_destinations ──< referral_destination_contexts   (configures School vs AWC)
                      ──< school_screening_findings.referral_destination_id
                      ──< awc_screening_findings.referral_destination_id
                      ──< treatment_records.further_referral_destination_id

school_screenings ──< treatment_records
awc_screenings    ──< treatment_records

staff ──< staff_assignments
users ──(optional FK)── staff
devices ──< users

holidays          (independent; referenced contextually by visit_status_history)
audit_log         (generic: table_name + record_id)
```

Legend: `A ──< B` = one A has many B (B holds the FK).

## 2. Table Definitions

Postgres-flavored DDL. SQLite/Drift mirrors this with `TEXT` UUIDs, `INTEGER` booleans,
`TEXT` timestamps, and enums as `TEXT` + `CHECK`.

### 2.1 Reference / Identity

```sql
CREATE TABLE financial_years (
  id            uuid PRIMARY KEY,
  label         text NOT NULL UNIQUE,         -- e.g. '2025-26'
  start_date    date NOT NULL,                -- 01 Apr
  end_date      date NOT NULL,                -- 31 Mar
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TYPE app_role AS ENUM ('ADMIN', 'MEDICAL_OFFICER', 'TEAM_MEMBER');

CREATE TABLE staff (
  id            uuid PRIMARY KEY,
  full_name     text NOT NULL,
  designation   text,      -- e.g. 'Medical Officer (BAMS)', 'Staff Nurse', 'Optometrist'
  qualification text,      -- e.g. 'BAMS', 'BHMS' — separate from role, per source plan
  phone         text,
  is_deleted    boolean NOT NULL DEFAULT false,
  created_by    uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by    uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version   integer NOT NULL DEFAULT 1
);
-- Seed (from Micro Plan header block, Team-B FY2025-26) [SOURCE-DERIVED]:
--   Rajni Pratap    — Medical Officer, BAMS
--   Deepak Yadav    — Medical Officer, BHMS
--   Shabnam Khan    — Staff Nurse (SN)
--   Mangal Kumar    — Optometrist (OPT)        [USER-DECIDED: OPT = Optometrist]
-- Contact numbers are in the source Micro Plan (rows 7-11) and are loaded at seed
-- time from that file. They are deliberately not reproduced in version-controlled
-- documentation.

-- Append-only: team membership history. Never edit a past row; close it (end_date)
-- and insert a new one for a transfer/replacement.
CREATE TABLE staff_assignments (
  id                 uuid PRIMARY KEY,
  staff_id           uuid NOT NULL REFERENCES staff(id),
  team_label         text,                    -- e.g. 'Team - B' [SOURCE-DERIVED]
  role_in_team       text NOT NULL,
  start_date         date NOT NULL,
  end_date           date,                     -- null = currently assigned
  financial_year_id  uuid REFERENCES financial_years(id),
  remarks            text,
  created_by         uuid, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_staff_assignments_staff ON staff_assignments(staff_id, start_date);
CREATE INDEX idx_staff_assignments_dates ON staff_assignments(start_date, end_date);
-- "Which staff were assigned on date D" =
--   WHERE start_date <= D AND (end_date IS NULL OR end_date >= D)

CREATE TABLE users (
  id             uuid PRIMARY KEY,
  staff_id       uuid REFERENCES staff(id),    -- nullable: an account need not map to staff
  email          text UNIQUE,
  phone          text,
  display_name   text NOT NULL,
  role           app_role NOT NULL,
  is_active      boolean NOT NULL DEFAULT true,
  last_login_at  timestamptz,
  created_by     uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by     uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version    integer NOT NULL DEFAULT 1
);

CREATE TABLE devices (
  id                uuid PRIMARY KEY,
  user_id           uuid NOT NULL REFERENCES users(id),
  device_label      text,
  platform          text,
  app_version       text,
  last_sync_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now()
);
```

### 2.2 School / AWC Master

```sql
CREATE TABLE schools (
  id                   uuid PRIMARY KEY,
  official_school_code text,      -- UDISE-style 10-digit code; BLANK STAYS BLANK, never invented
  name                 text NOT NULL,
  institution_type     text,      -- source values seen: PS, UPS, COM (case-normalized on import)
  district             text,
  block                text,
  panchayat_village    text,
  address              text,
  data_quality_notes   text,      -- parser-raised flags preserved for human review
  is_active            boolean NOT NULL DEFAULT true,
  is_deleted           boolean NOT NULL DEFAULT false,
  created_by           uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by           uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version          integer NOT NULL DEFAULT 1
);
-- Uniqueness enforced ONLY among non-blank codes; multiple blanks are valid. [CONFIRMED]
CREATE UNIQUE INDEX uq_schools_code ON schools(official_school_code)
  WHERE official_school_code IS NOT NULL AND official_school_code <> '';
CREATE INDEX idx_schools_geo ON schools(district, block);
CREATE INDEX idx_schools_name_trgm ON schools USING gin (name gin_trgm_ops);

CREATE TABLE awcs (
  id                   uuid PRIMARY KEY,
  official_awc_code    text,      -- genuine government AWC ID ONLY. Currently unknown for all
                                  -- records => stays NULL. NOT unique-constrained, never
                                  -- populated from source_plan_awc_code. [USER-DECIDED]
  source_plan_awc_code text,      -- the small integer from the Micro Plan. NON-AUTHORITATIVE
                                  -- reference value only: the same value maps to different
                                  -- AWCs across months (15+ cases). NEVER used as identity,
                                  -- NEVER unique. [SOURCE-DERIVED]
  name                 text NOT NULL,
  subcentre_no         integer,   -- e.g. 1,2,3 in "AWC Jakhaura No.2" / "JAKHAURA-2".
                                  -- Village-scoped ordinal seen in BOTH the Micro Plan and the
                                  -- physical register. Informational; not a uniqueness key
                                  -- until confirmed stable. [SOURCE-DERIVED]
  panchayat_village    text,
  block                text,
  district             text,
  data_quality_notes   text,
  is_active            boolean NOT NULL DEFAULT true,
  is_deleted           boolean NOT NULL DEFAULT false,
  created_by           uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by           uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version          integer NOT NULL DEFAULT 1
);
-- NO unique index on source_plan_awc_code — deliberately. [USER-DECIDED]
-- Uniqueness on official_awc_code applies only if/when real official codes exist:
CREATE UNIQUE INDEX uq_awcs_official_code ON awcs(official_awc_code)
  WHERE official_awc_code IS NOT NULL AND official_awc_code <> '';
CREATE INDEX idx_awcs_geo ON awcs(district, block);
CREATE INDEX idx_awcs_name_trgm ON awcs USING gin (name gin_trgm_ops);

CREATE TABLE plan_imports (
  id                 uuid PRIMARY KEY,
  financial_year_id  uuid NOT NULL REFERENCES financial_years(id),
  source_filename    text NOT NULL,
  imported_by        uuid NOT NULL REFERENCES users(id),
  imported_at        timestamptz NOT NULL DEFAULT now(),
  row_count          integer,
  notes              text
);
```

**AWC identity strategy [USER-DECIDED]:** database identity is the internal UUID.
`official_awc_code` is a nullable business identifier that stays NULL until a genuine
government code is supplied. `source_plan_awc_code` and `subcentre_no` are retained as
non-authoritative reference values for traceability and human matching only. Duplicate
detection for AWCs is name + village + subcentre ordinal, surfaced for human review —
never auto-merged.

### 2.3 Visit Planning

```sql
CREATE TYPE location_type AS ENUM ('SCHOOL', 'AWC');
CREATE TYPE visit_status AS ENUM
  ('PLANNED', 'IN_PROGRESS', 'COMPLETED', 'MISSED', 'RESCHEDULED');
CREATE TYPE missed_reason AS ENUM
  ('SCHOOL_CLOSED', 'HOLIDAY', 'TEAM_UNAVAILABLE', 'OFFICIAL_DUTY', 'WEATHER', 'OTHER');

CREATE TABLE visit_plans (
  id                     uuid PRIMARY KEY,
  financial_year_id      uuid NOT NULL REFERENCES financial_years(id),
  location_type          location_type NOT NULL,
  school_id              uuid REFERENCES schools(id),
  awc_id                 uuid REFERENCES awcs(id),
  plan_import_id         uuid REFERENCES plan_imports(id),  -- null for manual/special visits
  original_planned_date  date NOT NULL,       -- IMMUTABLE after insert
  planned_date           date NOT NULL,       -- current target; changes only via logged reschedule
  actual_visit_date      date,                -- set on completion; may differ from planned_date
  status                 visit_status NOT NULL DEFAULT 'PLANNED',
  is_special_visit       boolean NOT NULL DEFAULT false,
  -- PLANNED / ENROLMENT snapshot from the Micro Plan. Stored EXACTLY as in source,
  -- including rows where male+female <> total (15/341 in FY2025-26). NEVER recomputed,
  -- NEVER mixed with actual screening counts. [USER-DECIDED] [SOURCE-DERIVED]
  planned_male_count     integer,
  planned_female_count   integer,
  planned_total_count    integer,
  contact_person         text,                -- from plan
  contact_number         text,                -- from plan
  source_sheet           text,                -- e.g. 'APRIL25' — import traceability
  source_row             integer,
  data_quality_notes     text,
  remarks                text,
  is_deleted             boolean NOT NULL DEFAULT false,
  created_by             uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by             uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version            integer NOT NULL DEFAULT 1,
  CONSTRAINT chk_visit_target CHECK (
    (location_type = 'SCHOOL' AND school_id IS NOT NULL AND awc_id IS NULL) OR
    (location_type = 'AWC'    AND awc_id IS NOT NULL AND school_id IS NULL)
  )
);
CREATE INDEX idx_visit_plans_fy_date ON visit_plans(financial_year_id, planned_date);
CREATE INDEX idx_visit_plans_school ON visit_plans(school_id);
CREATE INDEX idx_visit_plans_awc ON visit_plans(awc_id);
CREATE INDEX idx_visit_plans_status ON visit_plans(status);

-- Append-only lifecycle log. MISSED and RESCHEDULED screens are filtered views over
-- visit_plans + this table, never separate tables. [CONFIRMED]
CREATE TABLE visit_status_history (
  id              uuid PRIMARY KEY,
  visit_plan_id   uuid NOT NULL REFERENCES visit_plans(id),
  from_status     visit_status,
  to_status       visit_status NOT NULL,
  from_date       date,
  to_date         date,
  missed_reason   missed_reason,
  reason_remarks  text,
  related_holiday_id uuid REFERENCES holidays(id),   -- when missed_reason = 'HOLIDAY'
  changed_by      uuid NOT NULL REFERENCES users(id),
  changed_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_visit_status_history_plan ON visit_status_history(visit_plan_id, changed_at);

CREATE TABLE holidays (
  id                 uuid PRIMARY KEY,
  financial_year_id  uuid REFERENCES financial_years(id),
  holiday_date       date NOT NULL,
  name               text NOT NULL,
  reason             text,
  remarks            text,
  is_manual_addition boolean NOT NULL DEFAULT false,  -- false = imported from Micro Plan
  plan_import_id     uuid REFERENCES plan_imports(id),
  is_deleted         boolean NOT NULL DEFAULT false,
  created_by         uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by         uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version        integer NOT NULL DEFAULT 1
);
CREATE INDEX idx_holidays_date ON holidays(holiday_date);
```

**Special visits [CONFIRMED]:** a Saturday/Sunday/holiday visit is an ordinary
`visit_plans` row with `is_special_visit = true`. No date-based restriction is enforced
at the database or UI level — weekends and holidays are permitted, by design.

**`PHC REFERRED CHILDREN TREATMENT` rows [SOURCE-DERIVED]:** these appear on every
Saturday of the Micro Plan and reference no school/AWC. They are **not imported** as
`visit_plans` rows and **not** as `holidays`. They are informational confirmation that
Saturdays are reserved for the treatment/follow-up workflow (§2.7).

### 2.4 Disease Master

```sql
CREATE TYPE disease_category AS ENUM
  ('DEFECTS_AT_BIRTH', 'DEFICIENCIES', 'DISEASES',
   'DEVELOPMENTAL_DELAY_DISABILITY', 'OTHERS');
CREATE TYPE applicable_to AS ENUM ('SCHOOL', 'AWC', 'BOTH');

CREATE TABLE disease_master (
  id               uuid PRIMARY KEY,
  official_code    text,          -- Job Aid code, e.g. '1', '40.1'. Preserved verbatim.
  name             text NOT NULL, -- official Job Aid wording, NOT normalized/reworded
  category         disease_category NOT NULL,
  applicable_to    applicable_to NOT NULL DEFAULT 'BOTH',
  description      text,
  source_reference text,          -- e.g. 'RBSK Job Aid 0-6 yrs, p.4'
  is_active        boolean NOT NULL DEFAULT true,
  is_deleted       boolean NOT NULL DEFAULT false,
  created_by       uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by       uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version      integer NOT NULL DEFAULT 1
);
CREATE INDEX idx_disease_master_category ON disease_master(category);
CREATE INDEX idx_disease_master_name_trgm ON disease_master USING gin (name gin_trgm_ops);

-- Optional alias table: maps handwritten register shorthand to official findings so OCR
-- review can suggest a match. Aliases are SUGGESTIONS for a human reviewer, never an
-- automatic mapping. Seeded only with abbreviations actually observed in the register.
CREATE TABLE disease_aliases (
  id            uuid PRIMARY KEY,
  disease_id    uuid NOT NULL REFERENCES disease_master(id),
  alias_text    text NOT NULL,     -- e.g. 'Vit A', 'S.I', 'Carries'
  source_note   text,              -- where the alias was observed
  is_confirmed  boolean NOT NULL DEFAULT false,  -- false until the MO confirms the mapping
  created_by    uuid, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_disease_aliases_text ON disease_aliases(lower(alias_text));
```

**Seed data [SOURCE-DERIVED]:** the 29 codified findings transcribed in
[14_JOB_AID_FIELD_MAPPING.md](14_JOB_AID_FIELD_MAPPING.md) §7 (codes 1–44 with the
source's own gaps). Codes 31–38 and items B6/B7 are **[TBD]** — absent from the supplied
pages; they are not invented and simply have no rows.

### 2.5 Screening Session Context

```sql
CREATE TYPE session_status AS ENUM ('ACTIVE', 'CLOSED');

-- Supports "select School + Date + Class once, then enter many children".
-- The context is ALSO materialized onto each child row (§2.6) so historical records stay
-- correct even if a session is later edited. [USER-DECIDED]
CREATE TABLE screening_sessions (
  id              uuid PRIMARY KEY,
  visit_plan_id   uuid NOT NULL REFERENCES visit_plans(id),
  location_type   location_type NOT NULL,
  class_label     text,             -- School only; NULL for AWC sessions
  session_date    date NOT NULL,
  status          session_status NOT NULL DEFAULT 'ACTIVE',
  started_by      uuid NOT NULL REFERENCES users(id),
  started_at      timestamptz NOT NULL DEFAULT now(),
  closed_at       timestamptz,
  is_deleted      boolean NOT NULL DEFAULT false,
  created_by      uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by      uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version     integer NOT NULL DEFAULT 1
);
CREATE INDEX idx_screening_sessions_visit ON screening_sessions(visit_plan_id, status);
```

Changing class mid-visit closes the current session and opens a new one for the new
class, under the same `visit_plan_id`. A crash mid-entry leaves the session `ACTIVE`, so
the app can offer to resume it.

### 2.6 School Screening

```sql
CREATE TYPE gender AS ENUM ('MALE', 'FEMALE', 'OTHER');

CREATE TABLE school_screenings (
  id                    uuid PRIMARY KEY,
  visit_plan_id         uuid NOT NULL REFERENCES visit_plans(id),
  screening_session_id  uuid REFERENCES screening_sessions(id),  -- null for OCR-imported rows
  serial_no             integer NOT NULL,   -- app-assigned, scoped per visit_plan
  class_label           text,               -- NULLABLE: the physical register has no Class
                                            -- column, so OCR-imported rows may lack it.
                                            -- App-entered rows always carry session context.
                                            -- [SOURCE-DERIVED]
  screening_date        date NOT NULL,
  child_name            text NOT NULL,
  age_years             integer CHECK (age_years BETWEEN 0 AND 20),
  age_months            integer CHECK (age_months BETWEEN 0 AND 240),
                                            -- register records some ages in months ('6m')
  gender                gender NOT NULL,
  mother_name           text,
  father_name           text,
  remarks               text,               -- the register's unlabeled trailing column
                                            -- (contact no. / 'Admit' notes) [SOURCE-DERIVED]
  source_photo_id       uuid REFERENCES register_photos(id),
  ocr_result_id         uuid REFERENCES ocr_results(id),
  is_deleted            boolean NOT NULL DEFAULT false,
  created_by            uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by            uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version           integer NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX uq_school_screening_serial ON school_screenings(visit_plan_id, serial_no);
CREATE INDEX idx_school_screenings_visit ON school_screenings(visit_plan_id);
CREATE INDEX idx_school_screenings_class ON school_screenings(visit_plan_id, class_label);
CREATE INDEX idx_school_screenings_date ON school_screenings(screening_date);

CREATE TABLE school_screening_findings (
  id                        uuid PRIMARY KEY,
  school_screening_id       uuid NOT NULL REFERENCES school_screenings(id),
  disease_id                uuid NOT NULL REFERENCES disease_master(id),
  disease_category_snapshot disease_category NOT NULL,  -- immune to later re-categorization
  referral_destination_id   uuid REFERENCES referral_destinations(id),  -- see §2.8
  referral_remarks          text,
  created_by                uuid, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_ssf_screening ON school_screening_findings(school_screening_id);
CREATE INDEX idx_ssf_disease ON school_screening_findings(disease_id);
```

**Normal children are first-class records [USER-DECIDED]:** every screened child gets a
`school_screenings` row. A normal child simply has **zero** `school_screening_findings`
rows — there is no "normal" flag to keep in sync, and no separate universe of referred
children. The Disease/Referred Line List is a query over children having ≥1 finding.

`referral_destination_id` is nullable because a finding may be recorded before the
referral decision is made; the UI requires it for School findings, matching the register
practice of always pairing a disease with a destination.

### 2.7 AWC Screening (full structured form — Option B)

Core record + findings + the complete Job Aid checklist. The checklist is stored in a
**normalized response table**, not ~100 columns, so the form can grow with the source
document without schema churn. **[USER-DECIDED: full digital form]**

```sql
CREATE TYPE anthro_classification AS ENUM ('NORMAL', 'LT_MINUS_2SD', 'LT_MINUS_3SD', 'GT_PLUS_2SD');
CREATE TYPE muac_classification  AS ENUM ('RED', 'YELLOW', 'GREEN');

CREATE TABLE awc_screenings (
  id                    uuid PRIMARY KEY,
  visit_plan_id         uuid NOT NULL REFERENCES visit_plans(id),
  screening_session_id  uuid REFERENCES screening_sessions(id),
  serial_no             integer NOT NULL,
  screening_date        date NOT NULL,

  -- Preliminary Particulars (Job Aid p.1) [SOURCE-DERIVED]
  child_name            text NOT NULL,
  dob                   date,
  age_months            integer CHECK (age_months BETWEEN 0 AND 83),
  gender                gender NOT NULL,
  father_guardian_name  text,
  mother_name           text,
  contact_number        text,
  mcts_no               text,          -- 16-digit on form
  unique_id_no          text,          -- 16-digit on form
  aadhaar_number        text,          -- [TBD] collect only if officially required; see §8
  asha_name             text,
  asha_contact_no       text,
  asha_id               text,
  mobile_health_team_id text,
  awc_name_snapshot     text,          -- as written on the form that day
  district_block_snapshot text,

  -- Anthropometry + official classifications (Job Aid p.1) [SOURCE-DERIVED]
  weight_kg                       numeric(5,2),
  height_length_cm                numeric(5,2),
  head_circumference_cm           numeric(5,2),
  muac_cm                         numeric(5,2),   -- conditional: 6–60 months AND weight <-2SD
  weight_for_age_classification         anthro_classification,
  weight_for_length_classification      anthro_classification,
  height_for_age_classification         anthro_classification,
  head_circumference_classification     anthro_classification,  -- Micro-/Macrocephaly
  muac_classification                   muac_classification,
  -- Classifications are USER-SELECTED from the Job Aid's own reference charts.
  -- The app does NOT auto-compute SD bands — those charts were not supplied. [TBD]

  -- Sign-off block (Job Aid p.4) [SOURCE-DERIVED]
  doctor_mht_name        text,
  visit_date             date,
  data_entered_in_register boolean,
  register_entered_by      text,
  register_page_ref        text,

  remarks               text,
  source_photo_id       uuid REFERENCES register_photos(id),
  ocr_result_id         uuid REFERENCES ocr_results(id),
  is_deleted            boolean NOT NULL DEFAULT false,
  created_by            uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by            uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version           integer NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX uq_awc_screening_serial ON awc_screenings(visit_plan_id, serial_no);
CREATE INDEX idx_awc_screenings_visit ON awc_screenings(visit_plan_id);
CREATE INDEX idx_awc_screenings_date ON awc_screenings(screening_date);

CREATE TABLE awc_screening_findings (
  id                        uuid PRIMARY KEY,
  awc_screening_id          uuid NOT NULL REFERENCES awc_screenings(id),
  disease_id                uuid NOT NULL REFERENCES disease_master(id),
  disease_category_snapshot disease_category NOT NULL,
  referral_destination_id   uuid REFERENCES referral_destinations(id),
  referral_remarks          text,
  created_by                uuid, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_asf_screening ON awc_screening_findings(awc_screening_id);
CREATE INDEX idx_asf_disease ON awc_screening_findings(disease_id);
```

#### Checklist item catalogue + responses

```sql
CREATE TYPE checklist_section AS ENUM
  ('A_DEFECTS_AT_BIRTH', 'B_DEFICIENCY', 'C_DISEASE',
   'D_DEVELOPMENTAL_DELAY', 'D_AUTISM', 'D_SCREENING_2_5_TO_6Y');
CREATE TYPE checklist_response_type AS ENUM
  ('BOOLEAN', 'YES_NO', 'SINGLE_SELECT', 'MULTI_SELECT', 'NUMERIC', 'TEXT');
CREATE TYPE refer_polarity AS ENUM ('REFER_IF_YES', 'REFER_IF_NO', 'INFORMATIONAL');

-- Versioned catalogue of Job Aid items. Adding/correcting items later = new rows with a
-- new version, never edits to historical ones, so past responses keep their meaning.
CREATE TABLE awc_checklist_items (
  id                uuid PRIMARY KEY,
  version           text NOT NULL,           -- e.g. 'JOBAID-0-6Y-2026-09'
  section           checklist_section NOT NULL,
  item_code         text NOT NULL,           -- 'A1', 'A10(b)', 'C7.1.1', 'D5.3' — verbatim
  parent_item_code  text,                    -- for conditional sub-items
  label             text NOT NULL,           -- official wording, verbatim
  response_type     checklist_response_type NOT NULL,
  option_list       jsonb,                   -- e.g. ["1 to 5 lesions", ">5 lesions"]
  polarity          refer_polarity NOT NULL, -- Section D milestones are REFER_IF_NO
  domain_tag        text,                    -- GM/FM/V/C/H/Sp/S where the form tags one
  age_band_min_months integer,               -- applicability window for Section D
  age_band_max_months integer,
  display_order     integer NOT NULL,
  is_active         boolean NOT NULL DEFAULT true,
  source_reference  text,                    -- 'Job Aid p.3'
  is_uncertain      boolean NOT NULL DEFAULT false,  -- transcription not fully legible
  uncertainty_note  text,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_awc_checklist_item ON awc_checklist_items(version, item_code);
CREATE INDEX idx_awc_checklist_section ON awc_checklist_items(version, section, display_order);

CREATE TABLE awc_screening_checklist_responses (
  id                      uuid PRIMARY KEY,
  awc_screening_id        uuid NOT NULL REFERENCES awc_screenings(id),
  checklist_item_id       uuid NOT NULL REFERENCES awc_checklist_items(id),
  item_code_snapshot      text NOT NULL,     -- survives catalogue versioning
  response_boolean        boolean,
  response_text           text,
  response_numeric        numeric(10,2),
  response_options        jsonb,             -- for multi-select
  not_applicable          boolean NOT NULL DEFAULT false,  -- outside the child's age band
  created_by              uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by              uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version             integer NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX uq_awc_response ON awc_screening_checklist_responses(awc_screening_id, checklist_item_id);
CREATE INDEX idx_awc_response_screening ON awc_screening_checklist_responses(awc_screening_id);
```

The checklist **records what the clinician observed**; it does not compute a diagnosis.
Findings in `awc_screening_findings` remain a deliberate clinician selection. No
automatic checklist→finding inference is implemented, because the Job Aid's decision
rules (e.g. "refer if more than one sign" for A10, the C8 TB positivity logic) are
clinical criteria that must not be re-implemented from a photograph. **[TBD — needs
clinical sign-off before any auto-suggestion is added]** **[NOT YET IMPLEMENTED]**

Form section design and conditional logic: see
[19_AWC_SCREENING_FORM_SPEC.md](19_AWC_SCREENING_FORM_SPEC.md).

### 2.8 Referral Configuration (context-specific)

Replaces the Phase 0 `referral_destination` enum. School and AWC vocabularies are
configured separately and never merged. **[USER-DECIDED]**

```sql
CREATE TABLE referral_destinations (
  id            uuid PRIMARY KEY,
  code          text NOT NULL UNIQUE,   -- 'PHC_CHC','DISTRICT_HOSPITAL','HIGHER_CENTER',
                                        -- 'PHC','CHC','DH','DEIC','NRC'
  label         text NOT NULL,
  description   text,
  source_reference text,
  is_active     boolean NOT NULL DEFAULT true,
  display_order integer NOT NULL DEFAULT 0,
  created_by    uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by    uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version   integer NOT NULL DEFAULT 1
);

-- Which destinations are offered in which workflow, optionally narrowed by finding
-- category. A NULL finding_category means "all categories in this context".
CREATE TABLE referral_destination_contexts (
  id                      uuid PRIMARY KEY,
  referral_destination_id uuid NOT NULL REFERENCES referral_destinations(id),
  context                 location_type NOT NULL,      -- 'SCHOOL' | 'AWC'
  finding_category        disease_category,            -- NULL = applies to all
  is_default              boolean NOT NULL DEFAULT false,
  notes                   text,
  source_reference        text,
  created_by              uuid, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_ref_dest_context
  ON referral_destination_contexts(referral_destination_id, context, coalesce(finding_category::text, '*'));
CREATE INDEX idx_ref_dest_context_lookup ON referral_destination_contexts(context, finding_category);
```

Seed data and routing rules: see
[20_REFERRAL_CONFIGURATION.md](20_REFERRAL_CONFIGURATION.md).

### 2.9 Referral / Treatment Follow-up

```sql
CREATE TYPE attended_status  AS ENUM ('YES', 'NO');
CREATE TYPE treatment_status AS ENUM ('DONE', 'NOT_DONE');

CREATE TABLE treatment_records (
  id                             uuid PRIMARY KEY,
  school_screening_id            uuid REFERENCES school_screenings(id),
  awc_screening_id               uuid REFERENCES awc_screenings(id),
  treatment_visit_date           date NOT NULL,
  child_attended                 attended_status NOT NULL DEFAULT 'NO',       -- default NO
  treatment                      treatment_status NOT NULL DEFAULT 'NOT_DONE',-- default NOT DONE
  further_referral               boolean NOT NULL DEFAULT false,              -- default NO
  further_referral_destination_id uuid REFERENCES referral_destinations(id),
  remarks                        text,
  is_deleted                     boolean NOT NULL DEFAULT false,
  created_by                     uuid, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by                     uuid, updated_at timestamptz NOT NULL DEFAULT now(),
  row_version                    integer NOT NULL DEFAULT 1,
  CONSTRAINT chk_treatment_source CHECK (
    (school_screening_id IS NOT NULL AND awc_screening_id IS NULL) OR
    (awc_screening_id IS NOT NULL AND school_screening_id IS NULL)
  ),
  CONSTRAINT chk_further_referral_dest CHECK (
    (further_referral = false AND further_referral_destination_id IS NULL) OR
    (further_referral = true  AND further_referral_destination_id IS NOT NULL)
  )
);
CREATE INDEX idx_treatment_school_screening ON treatment_records(school_screening_id);
CREATE INDEX idx_treatment_awc_screening ON treatment_records(awc_screening_id);
CREATE INDEX idx_treatment_date ON treatment_records(treatment_visit_date);
CREATE INDEX idx_treatment_pending ON treatment_records(child_attended, treatment);
```

Defaults are deliberate and never auto-upgraded by the system. Multiple follow-up rows
per child are expected and all are retained. **[CONFIRMED]**

### 2.10 Register Photos & OCR

Originals are preserved untouched; processed images are separate rows; OCR output and
human corrections are stored separately with an explicit verification status.
**[USER-DECIDED]**

```sql
CREATE TYPE upload_status   AS ENUM ('LOCAL_ONLY', 'UPLOADING', 'UPLOADED', 'UPLOAD_ERROR');
CREATE TYPE ocr_job_status  AS ENUM ('QUEUED', 'PROCESSING', 'COMPLETED', 'FAILED');
CREATE TYPE derivative_kind AS ENUM ('DESKEWED', 'ROTATED', 'CONTRAST_NORMALIZED',
                                     'CROPPED', 'THUMBNAIL', 'OTHER');
CREATE TYPE verification_status AS ENUM ('UNREVIEWED', 'IN_REVIEW', 'CONFIRMED', 'REJECTED');

CREATE TABLE register_photos (
  id              uuid PRIMARY KEY,
  visit_plan_id   uuid NOT NULL REFERENCES visit_plans(id),
  screening_session_id uuid REFERENCES screening_sessions(id),
  class_label     text,
  page_label      text,             -- e.g. 'April 2026' page heading, if written
  sequence_no     integer,          -- ordering when one visit has several photos
  local_file_path text,
  storage_path    text,
  checksum        text,
  captured_by     uuid NOT NULL REFERENCES users(id),
  captured_at     timestamptz NOT NULL DEFAULT now(),
  device_id       uuid REFERENCES devices(id),
  upload_status   upload_status NOT NULL DEFAULT 'LOCAL_ONLY',
  quality_flags   jsonb,            -- blur/glare/skew heuristics from capture-time check
  is_deleted      boolean NOT NULL DEFAULT false,   -- soft-delete only; original never purged
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_register_photos_visit ON register_photos(visit_plan_id, sequence_no);

-- Preprocessing output NEVER overwrites the original.
CREATE TABLE register_photo_derivatives (
  id                uuid PRIMARY KEY,
  register_photo_id uuid NOT NULL REFERENCES register_photos(id),
  kind              derivative_kind NOT NULL,
  storage_path      text,
  local_file_path   text,
  parameters        jsonb,          -- rotation angle, crop box, etc. — reproducible
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_photo_derivatives ON register_photo_derivatives(register_photo_id);

CREATE TABLE ocr_jobs (
  id                uuid PRIMARY KEY,
  register_photo_id uuid NOT NULL REFERENCES register_photos(id),
  status            ocr_job_status NOT NULL DEFAULT 'QUEUED',
  engine_name       text,
  engine_version    text,
  started_at        timestamptz,
  completed_at      timestamptz,
  error_message     text,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_ocr_jobs_photo ON ocr_jobs(register_photo_id);
CREATE INDEX idx_ocr_jobs_status ON ocr_jobs(status);

-- Append-only: one row per detected register row.
CREATE TABLE ocr_results (
  id                     uuid PRIMARY KEY,
  ocr_job_id             uuid NOT NULL REFERENCES ocr_jobs(id),
  row_index              integer NOT NULL,
  source_region          jsonb,     -- bounding box on the source image for this row
  extracted_fields       jsonb NOT NULL,   -- raw engine output, never edited
  confidence_scores      jsonb,
  corrected_fields       jsonb,     -- human-edited values, stored SEPARATELY from raw
  verification_status    verification_status NOT NULL DEFAULT 'UNREVIEWED',
  duplicate_candidate_of uuid,      -- possible existing screening row, flagged not enforced
  reviewed_by            uuid REFERENCES users(id),
  reviewed_at            timestamptz,
  linked_school_screening_id uuid REFERENCES school_screenings(id),
  linked_awc_screening_id    uuid REFERENCES awc_screenings(id),
  created_at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_ocr_results_job ON ocr_results(ocr_job_id);
CREATE INDEX idx_ocr_results_status ON ocr_results(verification_status);
```

**Hard rule [CONFIRMED]:** a screening record is created from an OCR result only when
`verification_status = 'CONFIRMED'` by a human. Raw `extracted_fields` are never
overwritten by corrections.

### 2.11 Audit & Sync Support

```sql
CREATE TYPE audit_action AS ENUM ('INSERT', 'UPDATE', 'SOFT_DELETE', 'RESTORE');

CREATE TABLE audit_log (
  id              uuid PRIMARY KEY,
  table_name      text NOT NULL,
  record_id       uuid NOT NULL,
  action          audit_action NOT NULL,
  changed_fields  jsonb,
  old_values      jsonb,
  new_values      jsonb,
  actor_user_id   uuid REFERENCES users(id),
  actor_device_id uuid REFERENCES devices(id),
  occurred_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_log_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_time ON audit_log(occurred_at);
```

`sync_queue` (outbox) is **local-only** (SQLite/Drift) — see
[07_OFFLINE_SYNC_ARCHITECTURE.md](07_OFFLINE_SYNC_ARCHITECTURE.md).

## 3. RBAC Matrix

| Table / action | ADMIN | MEDICAL_OFFICER | TEAM_MEMBER |
|---|---|---|---|
| users (manage) | ✅ | ❌ | ❌ |
| staff / staff_assignments (manage) | ✅ | view | view |
| schools / awcs (create/edit) | ✅ | ✅ | view/search |
| plan_imports (run import) | ✅ | ❌ | ❌ |
| disease_master / referral config (edit) | ✅ | view/search | view/search |
| visit_plans, special visits (create/edit) | ✅ | ✅ | ✅ |
| screening sessions + screenings (create/edit) | ✅ | ✅ | ✅ |
| AWC clinical checklist (complete/edit) | ✅ | ✅ | ✅ (entry); clinical sign-off fields MO-only |
| treatment_records (create/edit) | ✅ | ✅ | entry only |
| register_photos (capture) | ✅ | ✅ | ✅ |
| OCR review/confirm | ✅ | ✅ | ✅ (own captures) |
| holidays (add manual) | ✅ | ✅ | ❌ |
| reports (view) | all | all | all |
| backup export / audit log | ✅ | ❌ | ❌ |

Enforced client-side for UX **and** server-side via Postgres RLS. Roles are coarse by
design; `app_role` is a single column so permissions can evolve without schema change.

## 4. Validation Rules

- `visit_plans.original_planned_date` is set once at insert and never updated.
  `planned_date` changes only through a logged reschedule that writes
  `visit_status_history`.
- A finding row requires `disease_id`; `referral_destination_id` is required by the UI
  at the point the referral decision is recorded, and must resolve to a destination
  configured for that context (`referral_destination_contexts`).
- `treatment_records.further_referral_destination_id` required iff
  `further_referral = true` (DB CHECK).
- Exactly one of `school_id`/`awc_id` on `visit_plans`; exactly one of
  `school_screening_id`/`awc_screening_id` on `treatment_records` (DB CHECK).
- Official codes: uniqueness only among non-blank values. `source_plan_awc_code` carries
  **no** uniqueness constraint.
- `awc_screenings.muac_cm` is only collected when the Job Aid's condition applies
  (6–60 months and weight <-2SD) — enforced in the UI, not as a DB constraint, because
  the source states it as guidance rather than a hard rule.
- Age: School accepts years or months; AWC is bounded to 0–83 months. The register
  shows AWC-age children (e.g. `3m`, `6m`) recorded in the same book as school
  children — the app keeps them in the correct workflow by location type, not by age.

## 5. Soft-Delete & Audit

Unchanged from Phase 0: `is_deleted`/`deleted_by`/`deleted_at` on business tables,
repository-level default filtering, one `audit_log` row per INSERT/UPDATE/SOFT_DELETE,
`created_by`/`updated_by` always a real user (OCR-confirmed rows attributed to the
confirming user, never to a pseudo-user).

## 6. Backup

Cloud provider-managed backups plus an ADMIN-triggered encrypted local export — see
[08_SECURITY_ARCHITECTURE.md](08_SECURITY_ARCHITECTURE.md).

## 7. Counts: planned vs. actual

Two strictly separate lineages, never summed together or reconciled automatically:

| | Source | Where it lives |
|---|---|---|
| **Planned / enrolment** | Micro Plan Excel | `visit_plans.planned_male_count` / `planned_female_count` / `planned_total_count` (verbatim, mismatches preserved) |
| **Actual screened** | Field data entry / confirmed OCR | computed by aggregating `school_screenings` / `awc_screenings` and their findings |

No stored counters, no manually maintained totals. All report figures are derived at
query time — see [10_REPORTING_EXPORT_ARCHITECTURE.md](10_REPORTING_EXPORT_ARCHITECTURE.md).

## 8. Remaining [TBD] items carried into Phase 1 (nullable, unused, not guessed)

| Field / area | Status |
|---|---|
| `awcs.official_awc_code` | No genuine government AWC ID found in any source — stays NULL |
| `awc_screenings.aadhaar_number` | Column exists per the Job Aid; collection deferred pending a decision on whether it is officially required |
| Job Aid items B6, B7; D10.3.1, D10.3.2; D11 numbering; codes 31–38 | Absent/illegible in supplied pages — no catalogue rows created |
| WHO growth-chart lookup tables | Not supplied; classifications stay user-selected, never auto-computed |
| Checklist → finding auto-suggestion | Requires clinical sign-off; not implemented |
| School (6+ yrs) official job aid | Never supplied; School screening fields remain brief-derived |

## 9. Change log

**v1.0 — Phase 0.6 freeze** (from the Phase 0 draft):
1. `awcs`: split `awc_code` into `official_awc_code` (nullable, no data yet) and
   `source_plan_awc_code` (non-authoritative); uniqueness constraint removed; added
   `subcentre_no`.
2. `referral_destination` enum replaced by `referral_destinations` +
   `referral_destination_contexts` — context-specific, configuration-driven.
3. AWC screening expanded to the full Job Aid structure: anthropometry classification
   enums (incl. head circumference), preliminary particulars, sign-off block, plus
   `awc_checklist_items` + `awc_screening_checklist_responses`.
4. Added `screening_sessions` for the active School/AWC entry context.
5. `school_screenings`: `class_label` made nullable (register has no Class column),
   age split into years/months, `remarks` added for the register's trailing column.
6. Added planned/enrolment snapshot columns on `visit_plans`, kept strictly separate
   from actual screening counts; added source sheet/row traceability.
7. Register/OCR: added `register_photo_derivatives`, `verification_status`,
   `corrected_fields`, `source_region`, `duplicate_candidate_of`, photo `sequence_no`.
8. Added `disease_aliases` (suggestion-only shorthand mapping for OCR review).
9. Added `data_quality_notes` to `schools`, `awcs`, `visit_plans`.
10. `staff.qualification` added; OPT resolved to **Optometrist**.
11. `holidays` gained remarks + soft-delete/audit columns;
    `visit_status_history.related_holiday_id` added.
