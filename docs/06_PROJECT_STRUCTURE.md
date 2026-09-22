# Flutter Project Structure

Pragmatic layering, not academic Clean Architecture — three layers (presentation /
domain / data) are enough for this app's size; avoid adding a fourth layer of
indirection "for the future." Feature-first organization keeps related screens,
controllers, and repositories co-located so a solo/small dev team can hold one feature
in their head at a time.

```
lib/
  main.dart
  app.dart                       # MaterialApp, router, theme wiring

  core/
    config/                      # env/build config, Supabase keys (via --dart-define)
    theme/
    constants/                   # enum-like constants mirroring DB enums
    errors/                      # Failure types, exception mapping
    utils/                       # date/FY helpers (April–March logic lives here, once)
    extensions/

  data/
    local/
      database.dart              # Drift database definition (source of truth for schema)
      tables/                    # one file per table group, mirrors 04_DATABASE_ARCHITECTURE.md
      daos/                      # Drift DAOs — one per aggregate (VisitPlanDao, ScreeningDao, ...)
      migrations/                # versioned schema migrations
    remote/
      supabase_client.dart
      dto/                       # remote row <-> domain entity mapping
    repositories/                # implement domain interfaces; merge local+remote; own is_deleted filtering
    sync/
      sync_engine.dart           # outbox drain, pull-since-checkpoint, conflict flagging
      sync_queue_dao.dart
      connectivity_watcher.dart
    ocr/
      ocr_client.dart            # cloud OCR API wrapper
      ocr_job_repository.dart

  domain/
    entities/                    # plain Dart classes, one per DB table (no Drift/Supabase types leak here)
    repositories/                # abstract interfaces the data/ layer implements
    usecases/                    # compound flows only: CompleteVisitUseCase,
                                  # ConfirmOcrRowUseCase, RescheduleVisitUseCase, etc.
                                  # (simple CRUD goes straight from controller to repository —
                                  #  a usecase class for "list schools" would be needless indirection)

  features/
    auth/
    home/
    visit_planning/               # list, detail, special visit, missed, reschedule, holidays
    school_screening/              # visit landing, child entry, class-session controller
    awc_screening/
    disease_referred_line_list/
    school_master/
    awc_master/
    plan_import/
    disease_master/
    referral_treatment/
    register_photo/
    ocr_review/
    staff_management/
    reporting/
    admin/                        # user management, backup export, audit log viewer
    settings/
    # each feature/<name>/ contains:
    #   presentation/screens/
    #   presentation/widgets/
    #   presentation/controllers/   (Riverpod providers/notifiers)
    #   (feature-local models only if not already a domain entity)

test/
  unit/                          # domain usecases, mappers, FY/date utils
  data/                          # DAO tests (in-memory Drift), repository tests, sync engine tests
  widget/                        # key screens/widgets
  integration/                   # full flows (see 11_TESTING_STRATEGY.md)
```

## Key structural decisions

- **The "visit session" controller is shared, not duplicated.** School and AWC
  screening flows both need "sticky context + Save & Next + running count" — this lives
  as one reusable controller in `features/school_screening` and
  `features/awc_screening` respectively delegate to a common base in
  `core/` or a small shared package, rather than copy-pasting the state machine.
- **Repositories, not usecases, are the default entry point** for controllers doing
  plain CRUD (list schools, save a screening). Usecases are reserved for flows that
  touch multiple tables atomically (completing a visit computes and may need to trigger
  photo-quality prompts; confirming an OCR row writes both `ocr_results` and a new
  screening row; rescheduling writes both `visit_plans` and
  `visit_status_history`). This matches "don't design for hypothetical future
  requirements" — no usecase class for single-table operations.
  - Every domain entity that maps to a table with `is_deleted` gets that filter applied
    once, in the repository layer, never repeated per-query in feature code.
- **Sync is a background concern**, not something individual features call directly.
  Features write to local Drift tables via repositories; the `data/sync/sync_engine`
  drains the outbox independently (triggered by connectivity change, app resume, and a
  periodic WorkManager task). No feature code needs to know whether it's online.
- **OCR pipeline is isolated in `data/ocr/`** behind an interface, so the concrete cloud
  engine (Vision API vs. Document AI vs. something else, per
  [05_TECHNOLOGY_STACK.md](05_TECHNOLOGY_STACK.md)) can change without touching
  `features/ocr_review`.

## Environment/config

- Supabase URL/anon key injected via `--dart-define` at build time (never hardcoded),
  separate values for a dev/staging project and the production project — even for an
  8–10 user app, testing sync logic against a throwaway Supabase project avoids
  corrupting real child health data during development.
- No secrets committed to the repo; `local.properties`-equivalent pattern already
  established in the sibling project's `.gitignore` should be mirrored here.
