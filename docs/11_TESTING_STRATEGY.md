# Testing Strategy

## Test pyramid

| Layer | Tool | Scope |
|---|---|---|
| Unit | `flutter_test` | Domain usecases, FY/date utilities, DTO mappers, validation rules |
| Database | Drift's in-memory test DB (`NativeDatabase.memory()`) | Schema constraints, migrations, DAO queries, aggregation correctness (counts) |
| Repository | `flutter_test` + fakes/`mocktail` | Local+remote merge logic, soft-delete filtering, sync-queue writes on every mutation |
| Sync engine | Drift in-memory DB + fake Supabase client | Outbox drain, pull-since-checkpoint, conflict detection/flagging |
| OCR pipeline | Fakes for the cloud OCR client | Confidence flagging, duplicate detection, commit-only-on-confirm invariant |
| Widget | `flutter_test` | Key screens: child entry form (Save & Next context stickiness), treatment defaults, OCR review row |
| Integration | `integration_test` | End-to-end flows: full school visit, full AWC visit, referral→treatment, register photo→OCR→commit, report export |
| Export | Golden/snapshot-style checks | PDF/Excel structure for at least one report of each shape (summary, detail-list) |
| Migration | Drift schema migration tests | Every schema version bump has a forward-migration test with seeded old-version data |

## Real-world scenarios from the brief, mapped to test layers

| # | Scenario | Primary test layer |
|---|---|---|
| 1 | No internet | Integration — full visit workflow with connectivity mocked off |
| 2 | Internet comes back | Sync engine — queued writes drain correctly on reconnect |
| 3 | Duplicate photo | Integration/OCR — same photo captured twice, both preserved (no auto-delete) |
| 4 | Duplicate child | OCR pipeline — duplicate-warning triggers, does not block |
| 5 | School code blank | Database — partial unique index allows multiple blanks |
| 6 | School appears in multiple months | Plan import — dedup logic produces one school, multiple visit_plans |
| 7 | Missed visit | Workflow — status transition + visit_status_history row, doesn't block other visits |
| 8 | Rescheduled visit | Workflow — original_planned_date preserved, new planned_date set, history intact |
| 9 | Sunday special visit | Workflow — visit_plans row created outside normal plan, is_special_visit=true |
| 10 | Unexpected holiday | Holiday — manual add mid-year, linked to a missed-visit reason |
| 11 | Staff transfer | Staff — old assignment closed (end_date), new one opened, historical reports unaffected |
| 12 | Treatment pending | Referral/Treatment — worklist correctly derives "pending" from defaults |
| 13 | Child did not attend treatment | Treatment — Attended=NO persists correctly, doesn't block further follow-up entries |
| 14 | Further referral | Treatment — CHECK constraint (further_referral ⇒ destination required) |
| 15 | OCR misread | OCR — low-confidence field flagged, editable before commit |
| 16 | User correction after OCR | OCR — edited value persists, audit_log records the correction |
| 17 | App crash during data entry | Widget/Integration — draft/autosave recovery on next launch (form state persistence) |
| 18 | Database migration | Migration — versioned schema upgrade test with realistic pre-upgrade data |
| 19 | Cloud sync failure | Sync engine — retry/backoff, sync_queue stays PENDING/ERROR, never silently drops |
| 20 | Multiple users editing records | Sync engine — conflict detection path, Sync Conflicts screen surfaces both versions |

## Security tests

- RLS policy tests (Postgres): each role can/cannot perform each action per the RBAC
  matrix in [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §3 — run as
  actual authenticated requests against a test Supabase project, not just unit-tested
  policy SQL in isolation.
- Local DB encryption: verify the SQLite file is unreadable without the SQLCipher key
  (basic smoke test, not a cryptographic audit).
- Auth: session expiry/refresh behavior, no credential leakage in logs.

## What Phase 0 does not require

A full CI pipeline, code coverage targets, or a dedicated QA team are not assumed for an
8–10 user internal app — recommend GitHub Actions running unit+widget+DB tests on every
push as a lightweight baseline once Phase 1 code exists, expanding to integration tests
once the core flows stabilize. This is a suggestion for Phase 1, not a Phase 0 build
item.
