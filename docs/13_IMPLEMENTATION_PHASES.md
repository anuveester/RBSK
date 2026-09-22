# Recommended Implementation Phases

Each phase produces a working, demonstrable slice — never a half-finished module carried
into the next phase. The database schema in
[04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) is built once, in Phase 1,
and extended additively afterward (see that doc's §7) rather than redesigned.

## Phase 1 — Foundation

- Flutter project scaffold per [06_PROJECT_STRUCTURE.md](06_PROJECT_STRUCTURE.md).
- Local Drift database: full schema from §04 (all tables, even ones not yet exercised by
  UI — this is cheap now and expensive to retrofit).
- Auth (Supabase) + basic navigation shell + RBAC scaffolding (role-gated navigation).
- School Master + AWC Master screens (manual CRUD first; import can follow once the
  Excel is available).
- Financial Year + Holiday Calendar (manual entry).
- **Gate to exit this phase:** can log in as each of the three roles and see
  role-appropriate navigation; can manually create a school, an AWC, and a financial
  year, entirely offline.

## Phase 2 — Plan Ingestion, Visit Planning & Core Screening

- Annual Plan Excel import (staging preview → commit), once the Excel is supplied —
  **this phase cannot fully start without it** (see
  [../SOURCE_MATERIALS_REQUIRED.md](../SOURCE_MATERIALS_REQUIRED.md)); scaffolding
  (visit plan CRUD, special visits, missed/reschedule) can proceed against manually
  created visit plans in the meantime.
- Visit Plan list/detail, Special Visit creation, Missed/Reschedule workflow.
- School Screening flow (class-session stickiness, Save & Next, Disease/Referral
  conditional fields) — the single highest-value daily-use screen.
- Disease Master (seeded provisionally; refined once Job Aid is supplied).
- Disease/Referred Line List view.
- **Gate:** a full school visit (multiple classes, mixed normal/disease children) can be
  completed end-to-end offline, and the Referred Line List correctly shows only the
  flagged children.

## Phase 3 — AWC Screening, Referral/Treatment, Register Photos

- AWC Screening flow (field set as finalized once Job Aid is available; provisional
  field set otherwise per PRD FR-8.2).
- Referral/Treatment worklist and entry form, including the intentional NO/NOT
  DONE/NO defaults.
- Register Photo capture + gallery (no OCR yet — capture/storage/offline-safety first).
- **Gate:** a full AWC visit and a full referral→treatment follow-up cycle work
  end-to-end offline; register photos are captured and permanently retained.

## Phase 4 — Cloud Sync

- Supabase schema mirroring §04, RLS policies per the RBAC matrix.
- Sync engine (outbox drain, pull-since-checkpoint, conflict detection) per
  [07_OFFLINE_SYNC_ARCHITECTURE.md](07_OFFLINE_SYNC_ARCHITECTURE.md).
- Photo upload to Storage, independent of row sync.
- Sync status UI (per-record chips, global status, manual Sync Now).
- **Data residency question (§12) must be answered before this phase**, since it
  determines Supabase Cloud vs. self-hosted deployment target.
- **Gate:** two devices, both entering data offline, converge correctly on reconnect,
  including a deliberately-forced conflict scenario resolved via the Sync Conflicts
  screen.

## Phase 5 — OCR Pipeline

- Cloud OCR job dispatch, image processing, extraction, review UI.
- Duplicate detection, confidence flagging.
- Requires real sample register photos to tune (see
  [../SOURCE_MATERIALS_REQUIRED.md](../SOURCE_MATERIALS_REQUIRED.md)) — can be
  scaffolded against synthetic/test photos earlier, but genuinely tuned only once real
  samples exist.
- **Gate:** a captured register photo produces reviewable extracted rows; confirming a
  row creates a correctly-linked screening record; nothing commits without confirmation.

## Phase 6 — Reporting & Export

- Report catalog (all 16 report types), filter panels, shared PDF/Excel template layer.
- Android share sheet integration.
- **Gate:** every report type in [10_REPORTING_EXPORT_ARCHITECTURE.md](10_REPORTING_EXPORT_ARCHITECTURE.md)
  produces a correct PDF and Excel export from real Phase 1–3 data, shareable via the
  system share sheet.

## Phase 7 — Staff/Team History, Admin Tools, Hardening

- Staff Management (assignment history).
- User Management, Backup Export, Audit Log Viewer.
- Security hardening pass (§08 checklist), performance pass on report queries at
  realistic multi-year data volume.
- Full test-suite build-out per [11_TESTING_STRATEGY.md](11_TESTING_STRATEGY.md),
  including the 20 real-world scenarios.
- **Gate:** app is ready for full field rollout to all 8–10 users.

## Cross-cutting, present from Phase 1 onward (not a separate phase)

- Audit fields, soft-delete, RBAC scaffolding — built into the schema and repository
  layer from day one (§04, §06), not bolted on later.
- Tests written alongside each phase's features, not deferred to a single end-of-project
  testing phase.
