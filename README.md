# RBSK Referred Line

Private offline-first mobile app for an 8–10 person RBSK field team: school/AWC
screening, referral & treatment follow-up, visit planning, register photo archive with
OCR-assisted entry, and reporting.

**Current phase: Phase 0.6 — Architecture & Schema Freeze (complete, awaiting approval).**
No application code has been written yet, by design. The database schema is now frozen
at v1.0 and Phase 1 is planned but not started.

## Start here

- [docs/21_PHASE_0_6_FREEZE.md](docs/21_PHASE_0_6_FREEZE.md) — the freeze package:
  decisions applied, final domain model, unresolved items, Phase 1 plan. Read this first.
- [docs/04_DATABASE_ARCHITECTURE.md](docs/04_DATABASE_ARCHITECTURE.md) — **FROZEN v1.0**
  schema.
- [docs/18_REGISTER_SAMPLE_ANALYSIS.md](docs/18_REGISTER_SAMPLE_ANALYSIS.md) — what the
  real physical register actually looks like (and how it differs from earlier
  assumptions).
- [SOURCE_MATERIALS_REQUIRED.md](SOURCE_MATERIALS_REQUIRED.md) — what's been supplied,
  what's still missing, and what each gap blocks.

## Full package

| Doc | Contents |
|---|---|
| [docs/01_PRD.md](docs/01_PRD.md) | Functional/non-functional requirements, roles, user journeys |
| [docs/02_SCREEN_MAP.md](docs/02_SCREEN_MAP.md) | Full screen inventory |
| [docs/03_WORKFLOWS.md](docs/03_WORKFLOWS.md) | School, AWC, visit planning, holiday, missed/reschedule, referral/treatment, OCR workflows |
| [docs/04_DATABASE_ARCHITECTURE.md](docs/04_DATABASE_ARCHITECTURE.md) | ERD, full table DDL, indexes, validation, RBAC matrix, audit/backup strategy — **not yet frozen, see Phase 0.5 callouts inline** |
| [docs/05_TECHNOLOGY_STACK.md](docs/05_TECHNOLOGY_STACK.md) | Stack evaluation and recommendation |
| [docs/06_PROJECT_STRUCTURE.md](docs/06_PROJECT_STRUCTURE.md) | Flutter project architecture |
| [docs/07_OFFLINE_SYNC_ARCHITECTURE.md](docs/07_OFFLINE_SYNC_ARCHITECTURE.md) | Sync engine, conflict resolution |
| [docs/08_SECURITY_ARCHITECTURE.md](docs/08_SECURITY_ARCHITECTURE.md) | AuthN/RBAC, encryption, audit, backup |
| [docs/09_OCR_REGISTER_PHOTO_ARCHITECTURE.md](docs/09_OCR_REGISTER_PHOTO_ARCHITECTURE.md) | Register photo → OCR → review pipeline |
| [docs/10_REPORTING_EXPORT_ARCHITECTURE.md](docs/10_REPORTING_EXPORT_ARCHITECTURE.md) | Report catalog, PDF/Excel export |
| [docs/11_TESTING_STRATEGY.md](docs/11_TESTING_STRATEGY.md) | Test pyramid mapped to real-world scenarios |
| [docs/12_RISKS_OPEN_QUESTIONS.md](docs/12_RISKS_OPEN_QUESTIONS.md) | Open questions and risks |
| [docs/13_IMPLEMENTATION_PHASES.md](docs/13_IMPLEMENTATION_PHASES.md) | Recommended build order (Phases 1–7) |
| [docs/14_JOB_AID_FIELD_MAPPING.md](docs/14_JOB_AID_FIELD_MAPPING.md) | **Phase 0.5** — full transcription of the official RBSK 0–6yr Job Aid: preliminary particulars, anthropometry classification, Defects/Deficiency/Disease/Developmental Delay sections, codified Disease Master, referral routing |
| [docs/15_REGISTER_OCR_FIELD_MAPPING.md](docs/15_REGISTER_OCR_FIELD_MAPPING.md) | **Phase 0.5** — real register sample structure, OCR design implications |
| [docs/16_PHASE0_DATABASE_REVIEW.md](docs/16_PHASE0_DATABASE_REVIEW.md) | **Phase 0.5** — schema reviewed against source material; No Change/Recommended/Required/Requires-User-Decision per item |
| [docs/17_SOURCE_DATA_QUALITY_REPORT.md](docs/17_SOURCE_DATA_QUALITY_REPORT.md) | **Phase 0.5** — duplicates, blank codes, the visit-date data-entry bug, enrollment count mismatches, and other source data quality findings |
| [docs/18_REGISTER_SAMPLE_ANALYSIS.md](docs/18_REGISTER_SAMPLE_ANALYSIS.md) | **Phase 0.6** — authoritative analysis of the real physical register (7 high-res photos) |
| [docs/19_AWC_SCREENING_FORM_SPEC.md](docs/19_AWC_SCREENING_FORM_SPEC.md) | **Phase 0.6** — full sectioned AWC screening form spec and its schema mapping |
| [docs/20_REFERRAL_CONFIGURATION.md](docs/20_REFERRAL_CONFIGURATION.md) | **Phase 0.6** — context-specific referral destinations (School vs AWC) and routing |
| [docs/21_PHASE_0_6_FREEZE.md](docs/21_PHASE_0_6_FREEZE.md) | **Phase 0.6** — freeze package: decisions, domain model, unresolved items, Phase 1 plan |

## Exact next step

Review and approve [docs/21_PHASE_0_6_FREEZE.md](docs/21_PHASE_0_6_FREEZE.md). Phase 1
(step 1.1 onward in §10 of that document) starts only on approval. The unresolved items
in §9 — chiefly whether a separate full class-wise screening register exists, and the
data-residency decision — do not block Phase 1 steps 1.1–1.10, but the first two should
be answered before OCR work begins.
