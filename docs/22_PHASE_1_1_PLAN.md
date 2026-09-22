# Phase 1.1 — Project Skeleton (Implementation Plan)

**Status: awaiting approval. No code written yet.**

Scope reference: [21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md) §10, step 1.1.
Structure reference: [06_PROJECT_STRUCTURE.md](06_PROJECT_STRUCTURE.md).
Stack reference: [05_TECHNOLOGY_STACK.md](05_TECHNOLOGY_STACK.md).

## 1. Objective

Create a buildable, runnable Flutter application skeleton for the RBSK Referred Line app
— correct package identity, Android build configuration, folder architecture, theme,
routing infrastructure, and lint/test gates — so that every later phase has a stable,
conventional place to put its code.

**This step deliberately produces no user-facing features and no data layer.** Its only
functional output is an app that launches on an Android device and shows a single
placeholder screen confirming the shell, theme, and router work.

Success is measured by *foundation quality*, not visible progress.

## 2. Verified environment (checked on this machine)

| Component | Status |
|---|---|
| Flutter | 3.47.2, stable channel ✅ |
| Dart | 3.13.2 ✅ |
| Android toolchain | Android SDK 37.0.0 ✅ |
| Connected devices | 3 available ✅ |
| Visual Studio / Windows SDK | Incomplete ⚠ — irrelevant, this is an Android-only build |
| Git repository | **Not initialized** — see §8 |

No toolchain installation is required for Phase 1.1.

## 3. Files and modules to be created

### 3.1 Project root

| Path | Purpose |
|---|---|
| `pubspec.yaml` | Package identity, SDK constraints, Phase 1.1 dependencies only |
| `analysis_options.yaml` | Lint rules (`flutter_lints`), strict analyzer settings |
| `.gitignore` | Flutter/Android/IDE ignores; excludes `local.properties`, build output, secrets |
| `android/app/build.gradle.kts` | `applicationId`, `minSdk`, `targetSdk`, JDK target |
| `android/app/src/main/AndroidManifest.xml` | App label; **no runtime permissions added in this step** |

Proposed identifiers (confirm or correct before I start):
- Package / applicationId: **`com.rbsk.referredline`**
- App display name: **RBSK Referred Line**
- `minSdk` **26** (Android 8.0), `targetSdk` **36**, JDK target **17** — matching the
  proven configuration of the sibling Android project on this machine.

### 3.2 `lib/` skeleton

```
lib/
  main.dart                     # ProviderScope + runApp
  app.dart                      # MaterialApp.router, theme wiring

  core/
    config/app_config.dart      # --dart-define reader; no secrets committed
    theme/app_theme.dart        # Material 3 light/dark themes
    theme/app_colors.dart       # colour tokens
    constants/app_constants.dart
    errors/failure.dart         # sealed Failure type used by later layers
    router/app_router.dart      # go_router instance + route names
    router/routes.dart          # route path constants

  features/
    home/presentation/screens/home_placeholder_screen.dart

  data/          (directory scaffold only — .gitkeep, no code)
  domain/        (directory scaffold only — .gitkeep, no code)
```

Directories for `data/` and `domain/` are created empty so later phases land in the
agreed structure rather than inventing their own.

### 3.3 Dependencies added in this step (and only these)

| Package | Why, in this step |
|---|---|
| `flutter_riverpod` | State management foundation; `ProviderScope` at root |
| `go_router` | Routing infrastructure |
| `flutter_lints` (dev) | Lint gate |

**Deliberately not added yet:** `drift`, `sqlcipher_flutter_libs`, `supabase_flutter`,
`flutter_secure_storage`, `camera`, `image_picker`, `pdf`, `printing`, `excel`,
`share_plus`, `connectivity_plus`, `workmanager`, `uuid`. Each arrives with the phase
that actually uses it, so an unused dependency never silently affects build size,
permissions, or the Gradle configuration.

## 4. Database work

**None.**

Phase 1.1 performs **zero** database work: no Drift dependency, no schema code, no
migrations, no SQLCipher wiring, no seed data. The frozen v1.0 schema
([04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md)) is implemented in
**Phase 1.2**, unchanged, exactly as frozen.

The only database-adjacent action here is structural: creating the empty
`lib/data/local/` directory tree so Phase 1.2 has its destination.

## 5. Tests

Modest by design — there is very little logic to test at this stage, and inflating the
test count with assertions about a placeholder screen would be noise.

| Test | Type | What it proves |
|---|---|---|
| `test/app_smoke_test.dart` | Widget | App boots inside `ProviderScope`, renders the placeholder route without exceptions |
| `test/core/theme/app_theme_test.dart` | Unit | Light and dark themes build, use Material 3, and expose the defined colour tokens |
| `test/core/router/app_router_test.dart` | Unit | Router constructs; the initial route resolves to the expected screen |
| `flutter analyze` | Static | Zero analyzer warnings/errors under the configured lints |

CI is **not** set up in this step (deferred; noted in
[11_TESTING_STRATEGY.md](11_TESTING_STRATEGY.md)).

## 6. Acceptance criteria

Phase 1.1 is complete when **all** of the following are objectively true:

1. `flutter pub get` completes with no errors.
2. `flutter analyze` reports **zero** issues.
3. `flutter test` passes — all tests in §5 green.
4. `flutter build apk --debug` succeeds.
5. The app **launches on a real connected Android device** and displays the placeholder
   screen (I will run it and report the result; I can capture a screenshot if useful).
6. The `lib/` tree matches §3.2 exactly, and matches
   [06_PROJECT_STRUCTURE.md](06_PROJECT_STRUCTURE.md).
7. `pubspec.yaml` contains **only** the three dependencies in §3.3.
8. No secrets, keys, or `local.properties` are committed; `.gitignore` covers them.
9. No database, auth, network, or permission code exists anywhere in the tree.
10. App identity matches the confirmed values in §3.1.

## 7. What will NOT be implemented in Phase 1.1

| Not in scope | Arrives in |
|---|---|
| Drift schema, SQLCipher, migrations | Phase 1.2 |
| Seed data (disease master, referral destinations, staff) | Phase 1.3 |
| Authentication, RBAC, secure storage | Phase 1.4 |
| The 5-destination navigation shell (role-gated) | Phase 1.4 |
| School/AWC Master screens | Phase 1.5 |
| Micro Plan import | Phase 1.6 |
| Visit plans, holidays, missed/reschedule | Phase 1.7 |
| Screening sessions and School screening entry | Phase 1.8 |
| Register photo capture | Phase 1.9 |
| Disease/Referred Line List | Phase 1.10 |
| Cloud sync, Supabase, OCR, AWC form, reports, treatment follow-up | Later phases |
| Any Android runtime permission | The phase that needs it |
| App icon, splash, branding polish | Deferred (cosmetic) |
| CI pipeline | Deferred |

Nothing in this step touches the frozen schema or any approval condition from
[21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md).

## 8. Decisions needed before I start

| # | Question | My recommendation |
|---|---|---|
| 1 | Package / applicationId | `com.rbsk.referredline` |
| 2 | App display name | "RBSK Referred Line" |
| 3 | `minSdk` | 26 — matches the sibling project; covers Android 8.0+. Raise to 29+ only if the team's devices are all newer |
| 4 | **Initialize a git repository?** The project folder is not under version control. | **Strongly recommend yes**, before any code — it makes every later phase reviewable and reversible. I'd commit the Phase 0–0.6 docs as the first commit |
| 5 | Where should the Flutter project live? | Directly in the project root (`pubspec.yaml` beside `docs/` and `reference_materials/`), so the docs travel with the code |

## 9. Estimated shape of the work

One focused session: project generation, folder scaffolding, theme/router/config files,
three small test files, then the build-and-run verification. No source-material analysis
and no design decisions are pending inside this step — everything it needs is already
settled by the freeze.
