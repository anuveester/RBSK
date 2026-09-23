# Technology Stack Evaluation & Recommendation

## Evaluation criteria (from brief §26)

Offline capability, security, OCR integration, image storage, PDF generation, Excel
generation, Android deployment, maintenance burden, cost, fit for 8–10 users, future
scalability, sync complexity.

## Mobile Framework

**Candidates:** Flutter, native Android (Kotlin), React Native.

| | Flutter | Native Kotlin | React Native |
|---|---|---|---|
| Offline DB tooling | Excellent (Drift/SQLite) | Excellent (Room) | Weaker (needs bridging) |
| Single codebase, future iOS option | Yes | No | Yes |
| PDF/Excel packages | Mature (`pdf`, `printing`, `excel`) | Mature but more manual | Mature |
| Camera/OCR integration | Good plugin ecosystem | Best (direct platform APIs) | Good |
| Maintainability by small/solo team | High (declarative UI, hot reload) | High but Android-only | Medium (JS/native bridge issues) |
| Team's existing precedent | — | The sibling `Medical` project (MedStore Validation) is native Kotlin/Compose, but that's a *different, unrelated* app | — |

**Recommendation: Flutter (Dart), Android-first.** Rationale: the requirement list
(offline SQLite, PDF export, Excel export, camera capture, Android share sheet, RBAC UI,
long-lived maintainability by a small team) is squarely Flutter's strength profile, and
a single codebase preserves an iOS option later at near-zero extra architecture cost if
that's ever needed (open question, see [12_RISKS_OPEN_QUESTIONS.md](12_RISKS_OPEN_QUESTIONS.md)).
Native Kotlin was considered given the sibling project's precedent, but that project is
unrelated in scope and doesn't obligate this one to match its stack — Flutter's offline
+ export + camera package maturity outweighs any consistency benefit here.

## Local Database

**Candidates:** raw `sqflite`, Drift (formerly Moor), Isar, ObjectBox, Hive.

Given ~20 interrelated tables with foreign keys, constraints, and complex reporting
queries (joins across visit/screening/finding/treatment), a relational engine with
real SQL and compile-time-checked queries is a much better fit than a NoSQL
object/document store (Isar/ObjectBox/Hive) — those shine for simple flat data, not this
schema's join-heavy reporting needs.

**Recommendation: SQLite via [Drift](https://drift.simonbinder.eu/).** Drift generates
type-safe Dart query code from schema definitions, has first-class migration tooling
(critical — brief explicitly warns against repeated DB changes; Drift makes controlled,
versioned migrations tractable), supports reactive streams (a screen can watch a query
and auto-update, useful for "today's visit" / sync-status UI), and is well-suited to
pairing with SQLCipher for at-rest encryption (see
[08_SECURITY_ARCHITECTURE.md](08_SECURITY_ARCHITECTURE.md)).

## Cloud Backend

**Candidates:** Supabase (Postgres), Firebase (Firestore), custom Node/Express + Postgres,
AWS Amplify.

| | Supabase | Firebase | Custom backend |
|---|---|---|---|
| Data model fit | Postgres — same relational model as local SQLite, easy 1:1 mirroring | Firestore (NoSQL) — significant remodeling from the relational schema in §04 | Postgres possible, but full backend to build/maintain |
| RBAC | Row Level Security (server-enforced, matches §04 RBAC matrix) | Security rules (different mental model) | Full control, full effort |
| File storage | Built-in Storage buckets, private + signed URLs | Cloud Storage, similar | Needs separate service (S3-compatible) |
| Auth | Built-in, email/password, sufficient for 8–10 named users | Built-in | Needs building |
| Ops burden for a small team | Low — managed | Low — managed | High — someone maintains servers |
| Self-hosting option (data residency) | Yes — Supabase is open-source and self-hostable | No (Firebase is not self-hostable) | Yes, but that's the whole point of "custom" |
| Cost at this scale | Free/low tier likely sufficient for 8–10 users | Similar | Server costs even at low usage |

**Recommendation: Supabase (Postgres + Auth + Storage).** The decisive factor is schema
fit: §04's relational design (foreign keys, CHECK constraints, joins for reporting) maps
directly onto Postgres and barely needs translation from the local SQLite schema —
Firestore would force a redesign away from the relational model this document just
justified. Supabase's self-hosting option is also the answer to the data-residency open
question (§12) if a fully managed Supabase Cloud region doesn't satisfy the program's
data policy for child health data — the same schema and RLS policies port to a
self-hosted instance without rework.

**Flag:** confirm data-residency requirements before Phase 4 (cloud sync) — see
[12_RISKS_OPEN_QUESTIONS.md](12_RISKS_OPEN_QUESTIONS.md). This is treated as an open
policy question, not assumed away.

## OCR / Handwriting Recognition

**Candidates:** On-device ML Kit (Latin + Devanagari, as used in the sibling
MedStore Validation app), Google Cloud Vision API / Document AI, Tesseract, AWS
Textract.

The sibling project's precedent (ML Kit, on-device, offline) works well for **printed**
shop-board text. Register entries are **handwritten**, by multiple different people,
often in a mix of English and Devanagari — on-device handwriting OCR (especially
Devanagari) is materially weaker than cloud-based engines trained on handwriting at
scale.

**Key architectural decision: OCR does not need to be on-device or offline**, because
photo *capture* (the offline-critical part) and OCR *processing* (which only needs to
happen before the office review step) are separable in time — see workflow G in
[03_WORKFLOWS.md](03_WORKFLOWS.md). This removes the hardest constraint (accurate
offline handwriting OCR) from the problem entirely.

**Recommendation: Google Cloud Vision API (Document Text Detection) or Document AI,
invoked as a cloud job once a photo uploads**, with the extraction always subject to
mandatory human review before it becomes a screening record (PRD FR-13.2). Revisit the
specific engine/pricing once real sample register photos are available (see
[../SOURCE_MATERIALS_REQUIRED.md](../SOURCE_MATERIALS_REQUIRED.md)) — this is a
pluggable pipeline stage, not a hard architectural commitment.

## PDF / Excel Export & Sharing

- **PDF:** `pdf` (layout/generation) + `printing` (preview/share) — mature, works fully
  offline, no native platform PDF dependency issues.
- **Excel:** `excel` Dart package — reads/writes `.xlsx` fully offline.
- **Sharing:** `share_plus` — Android system share sheet (WhatsApp/Email/Drive/etc.),
  matching brief §22 (no direct WhatsApp API integration).

## State Management

**Recommendation: Riverpod.** Compile-safe dependency injection, good testability
(critical given the testing strategy's breadth — §11), works cleanly with Drift's
reactive streams, and avoids the boilerplate overhead of Bloc for a team this size
without sacrificing structure the way ad hoc `setState`/Provider would at 40+ screens.

## Supporting packages

| Concern | Package |
|---|---|
| Navigation | `go_router` |
| Camera / image picking | `camera` and/or `image_picker` |
| Image compression | `image` (matches sibling project's downscale precedent) |
| Secure local storage (keys/tokens) | `flutter_secure_storage` (Android Keystore-backed) |
| Local DB encryption | `sqlite3` + SQLite3MultipleCiphers (`sqlite3mc`) + Drift — see note below |
| Connectivity detection | `connectivity_plus` |
| Background sync trigger | `workmanager` (Android) |
| UUID generation | `uuid` |

> **Local DB encryption — implementation note (post-Phase 1.2):** this document
> originally recommended `sqlcipher_flutter_libs`. That package reached end-of-life
> before Phase 1.2 implementation began (pub.dev: "obsolete... update to version
> 3.x of `package:sqlite3` instead"). Phase 1.2 implemented and verified the
> current Drift-recommended replacement instead — the `sqlite3` package's native
> SQLite3MultipleCiphers build (`sqlite3mc`), selected via a `hooks.user_defines`
> block in `pubspec.yaml`. It is SQLCipher-*compatible* (same `PRAGMA key`
> mechanism, same cipher family) and actively maintained.
>
> **OLD (originally planned, now obsolete):** `sqlcipher_flutter_libs`.
> **CURRENT (implemented and verified):** `sqlite3` + SQLite3MultipleCiphers
> (`sqlite3mc` / `libsqlite3mc.so`).
>
> This is a dependency/implementation update, not an architecture or domain
> change — the encryption requirement itself (encrypted local storage, key never
> hardcoded, key never committed) is unchanged. Full verification detail (256-bit
> `Random.secure()` passphrase, Android Keystore-backed `flutter_secure_storage`,
> wrong-key-rejection test, `libsqlite3mc.so` confirmed in the built APK):
> [24_PHASE_1_2_REPORT.md](24_PHASE_1_2_REPORT.md) §C. Canonical change-log entry:
> [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §9 item 13.

## Summary Recommendation

| Layer | Choice |
|---|---|
| Mobile | Flutter, Android-first |
| Local DB | SQLite via Drift, SQLCipher-encrypted |
| Cloud | Supabase (Postgres + Auth + Storage) — confirm region/self-host per data-residency answer |
| State mgmt | Riverpod |
| OCR | Google Cloud Vision/Document AI, async cloud job post-sync |
| Export | `pdf` + `printing` (PDF), `excel` (Excel), `share_plus` (sharing) |

This stack directly supports every non-functional requirement in
[01_PRD.md](01_PRD.md) §4 except NFR-10 (iOS), which is deferred as an open question
rather than built for speculatively.
