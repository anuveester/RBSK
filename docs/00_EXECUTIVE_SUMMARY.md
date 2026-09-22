# RBSK Referred Line — Phase 0 Executive Summary

## What this is

A private, offline-first Flutter mobile app for an 8–10 person RBSK (Rashtriya Bal
Swasthya Karyakram) field team, replacing manual register-and-Excel workflows for
school/AWC screening, referral, treatment follow-up, and reporting — while keeping the
Medical Officer's daily workflow as close to "maintaining a register" as possible.

## Recommended stack (see [05_TECHNOLOGY_STACK.md](05_TECHNOLOGY_STACK.md) for rationale)

| Layer | Choice |
|---|---|
| Mobile framework | Flutter (Dart), Android-first |
| Local database | SQLite via Drift, encrypted with SQLCipher |
| Cloud backend | Supabase (Postgres + Auth + Storage), region chosen per data-residency answer (open question) |
| State management | Riverpod |
| OCR | Deferred to cloud (Google Cloud Vision / Document AI) as a background job after sync — **not** on-device, and **not** on the offline critical path |
| PDF / Excel export | `pdf` + `printing`, `excel` packages, shared via `share_plus` |

## Why this order of work

The database schema (§ [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md)) is
the thing later phases cannot casually change, so it is the most heavily worked part of
this package. It is built around three non-negotiable constraints from the brief:

1. **Historical immutability** — a visit plan's original date, a screening's disease
   finding, a staff assignment's dates must never be silently rewritten by a later
   master-data edit. Everything mutable carries audit fields and soft-delete; nothing
   is hard-deleted.
2. **Offline-first with safe multi-device sync** — every syncable row uses a
   client-generated UUID (never an autoincrement int), `row_version` +
   `updated_at` for conflict detection, and an outbox-pattern sync queue. Photos sync
   independently of their row data and are never auto-deleted locally.
   See [07_OFFLINE_SYNC_ARCHITECTURE.md](07_OFFLINE_SYNC_ARCHITECTURE.md).
3. **No invented medical or administrative data** — the Disease Master, AWC
   questionnaire field set, and School Code policy all defer to source material that has
   not yet been supplied (see [../SOURCE_MATERIALS_REQUIRED.md](../SOURCE_MATERIALS_REQUIRED.md)).
   The schema is deliberately shaped so those can be filled in later without a breaking
   migration.

## Key architectural decisions worth flagging now

- **OCR is decoupled from offline capture.** Photo capture must work offline; OCR does
  not have to. This removes on-device handwriting recognition (weak for Devanagari)
  from the critical path entirely — OCR runs as a cloud job once a photo syncs, and the
  Medical Officer reviews/corrects extracted rows later, never committing unverified
  data automatically.
- **"Missed" and "Rescheduled" are views, not separate tables.** Both are represented as
  status values plus an append-only `visit_status_history` log on `visit_plans`, so the
  full lifecycle (PLANNED → MISSED → RESCHEDULED → COMPLETED) is queryable without
  duplicate status representations that could contradict each other.
- **Disease findings are a many-to-many join**, not columns on the screening row, so a
  child can have multiple findings without schema changes and the Disease/Referred Line
  List is a straightforward filtered query.
- **Geo hierarchy (district/block/panchayat) is kept as plain text columns**, not
  normalized lookup tables, because the team appears to operate within one
  district/block. Flagged as an open question — see
  [12_RISKS_OPEN_QUESTIONS.md](12_RISKS_OPEN_QUESTIONS.md).
- **Data residency for child health data is an open question**, not an assumption.
  Supabase's default cloud region may not satisfy a government health program's data
  policy. This must be confirmed before Phase 4 (cloud sync) begins.

## What's in this package

| Doc | Contents |
|---|---|
| [01_PRD.md](01_PRD.md) | Functional/non-functional requirements, roles, user journeys |
| [02_SCREEN_MAP.md](02_SCREEN_MAP.md) | Full screen inventory and navigation structure |
| [03_WORKFLOWS.md](03_WORKFLOWS.md) | School, AWC, visit planning, holiday, missed/reschedule, referral/treatment, register-photo/OCR workflows |
| [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) | ERD, full table DDL, indexes, validation rules, soft-delete/audit strategy |
| [05_TECHNOLOGY_STACK.md](05_TECHNOLOGY_STACK.md) | Stack evaluation and final recommendation with rationale |
| [06_PROJECT_STRUCTURE.md](06_PROJECT_STRUCTURE.md) | Flutter project/folder architecture |
| [07_OFFLINE_SYNC_ARCHITECTURE.md](07_OFFLINE_SYNC_ARCHITECTURE.md) | Local/cloud sync design, conflict resolution |
| [08_SECURITY_ARCHITECTURE.md](08_SECURITY_ARCHITECTURE.md) | AuthN/RBAC, encryption, audit, backup |
| [09_OCR_REGISTER_PHOTO_ARCHITECTURE.md](09_OCR_REGISTER_PHOTO_ARCHITECTURE.md) | Register photo capture → OCR → review pipeline |
| [10_REPORTING_EXPORT_ARCHITECTURE.md](10_REPORTING_EXPORT_ARCHITECTURE.md) | Report catalog, PDF/Excel export, Android sharing |
| [11_TESTING_STRATEGY.md](11_TESTING_STRATEGY.md) | Test pyramid mapped to the 20 real-world scenarios in the brief |
| [12_RISKS_OPEN_QUESTIONS.md](12_RISKS_OPEN_QUESTIONS.md) | Risks and questions that need an answer before/during implementation |
| [13_IMPLEMENTATION_PHASES.md](13_IMPLEMENTATION_PHASES.md) | Recommended build order |
| [../SOURCE_MATERIALS_REQUIRED.md](../SOURCE_MATERIALS_REQUIRED.md) | What's missing and what it blocks |

## Exact next step

Supply the three source materials listed in `SOURCE_MATERIALS_REQUIRED.md` — Micro Plan
Excel first, since Phase 1 (School/AWC Master + plan ingestion) cannot start for real
without it. While waiting, Phase 1 scaffolding (project skeleton, local DB, auth,
navigation shell) can begin, since none of it depends on the missing files.
