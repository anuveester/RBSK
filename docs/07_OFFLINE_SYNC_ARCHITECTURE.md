# Offline-First & Sync Architecture

## Principles

1. Local SQLite (Drift) is the **source of truth for the device**. Every screen reads/
   writes local data; nothing blocks on network.
2. Sync is a **background, best-effort, resumable** process. It never blocks UI, never
   loses data, and always leaves the user able to tell what state a record is in.
3. Conflicts are **surfaced, never silently resolved by discarding data** (except the
   well-understood, safe Last-Writer-Wins case described below).

## Record identity & change tracking

- Every syncable row's primary key is a **client-generated UUIDv4**, created at the
  moment of local insert — never a server-assigned ID. This is what makes two offline
  devices safe to insert concurrently without collision (see
  [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §0).
- Every syncable row carries `row_version` (monotonic per-row counter) and `updated_at`.
  A local write always increments `row_version` and sets `updated_at` to local device
  time.

## Outbox pattern (local-only table)

```sql
-- Local SQLite only — never synced itself.
CREATE TABLE sync_queue (
  id              TEXT PRIMARY KEY,       -- uuid
  entity_table    TEXT NOT NULL,
  entity_id       TEXT NOT NULL,
  operation       TEXT NOT NULL,          -- 'UPSERT' | 'SOFT_DELETE'
  payload         TEXT NOT NULL,          -- JSON snapshot of the row at write time
  local_created_at TEXT NOT NULL,
  sync_status     TEXT NOT NULL DEFAULT 'PENDING', -- PENDING | SYNCED | ERROR | CONFLICT
  last_attempt_at TEXT,
  error_message   TEXT,
  retry_count     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_sync_queue_status ON sync_queue(sync_status);
```

Every repository write (insert/update/soft-delete) on a syncable table writes its
business-table row **and** a `sync_queue` row in the same local transaction. This
guarantees nothing is ever saved locally without also being queued for sync — there is
no separate "did I remember to sync this" bookkeeping elsewhere.

## Sync engine

Triggered on: connectivity restored (`connectivity_plus`), app foregrounded, and a
periodic background task (`workmanager`, e.g. every 15–30 min while online).

**Push phase:**
1. Read `sync_queue` rows with `sync_status = PENDING`, oldest first, batched (e.g. 50
   rows/request) per table.
2. Upsert to Supabase via `id` + compare `row_version`: if the incoming `row_version` is
   greater than what the server currently might have wait for — see conflict handling
   below.
3. On success: mark queue row `SYNCED`, update local row's `server_synced_at`.
4. On failure (network/validation): increment `retry_count`, mark `ERROR`, exponential
   backoff before retry. Never drop a queued write.

**Pull phase:**
1. Per table, track a local `last_pull_checkpoint` (server `updated_at` watermark +
   tie-break `id`).
2. Fetch server rows with `updated_at > checkpoint`, paginated.
3. For each incoming row: if no local row exists, insert. If a local row exists:
   - If the local row has **no pending outbox entry** for it, apply the server version
     directly (simple pull, no conflict).
   - If the local row **does have a pending outbox entry** (local edit not yet pushed,
     or push in flight when the pull ran), compare `row_version`/`updated_at` — this is
     a genuine concurrent-edit case, handled below.

## Conflict resolution

- **Default: Last-Writer-Wins at the row level**, using `updated_at`, for the common
  case where two devices edited *different* records, or the same record but one edit
  clearly precedes the other with no overlap window. This covers the overwhelming
  majority of real usage with 8–10 users who each typically own their own visits.
- **True conflict (both sides edited the same row within an overlapping sync window):**
  do not silently pick one. Mark the local `sync_queue` row `CONFLICT`, keep both
  versions (server version applied to the row; local edit preserved in the queue
  payload), and surface it on an ADMIN-visible **Sync Conflicts** screen (part of
  Settings/Admin, see [02_SCREEN_MAP.md](02_SCREEN_MAP.md)) for manual resolution
  (keep mine / keep theirs / merge fields). This is intentionally a rare-path UI, not a
  primary screen — expected frequency is very low at this team size.
- **Append-only tables** (`visit_status_history`, `staff_assignments`,
  `audit_log`, `ocr_results`) never conflict by construction — every write is a new row,
  never an update to an existing one.

## Photos: synced independently of row data

- `register_photos` row data (metadata) syncs through the normal outbox mechanism like
  any other table.
- The **binary file** uploads separately to Supabase Storage, tracked via
  `upload_status` (`LOCAL_ONLY → UPLOADING → UPLOADED`/`UPLOAD_ERROR`). Large files are
  not queued through the same JSON outbox as row data.
- The local file is **never deleted automatically** after a successful upload — "the
  original photograph must be permanently preserved" (brief §18) is read as applying to
  the local copy too, not just the cloud copy, until an explicit admin storage-cleanup
  feature is built (out of scope Phase 0).
- OCR (§ [09_OCR_REGISTER_PHOTO_ARCHITECTURE.md](09_OCR_REGISTER_PHOTO_ARCHITECTURE.md))
  only runs once `upload_status = UPLOADED`, since it's a cloud-side job.

## Sync status surfaced to the user

- Per-record: a small chip (Synced / Pending / Error) derived from whether an open
  `sync_queue` row exists for that entity and its status.
- Global: a status bar/icon (Home screen + Settings) summarizing pending count and last
  successful sync time, with a manual "Sync Now" action.
- Errors are actionable: tapping a Sync Error surfaces the `error_message` and a retry
  button, not a silent failure.

## What this design deliberately avoids

- No server-generated IDs anywhere in the business schema (would break offline insert
  safety).
- No blocking network calls in the UI thread/critical path for data entry.
- No automatic "just overwrite with whichever is newer" resolution for genuinely
  concurrent edits — only for the safe non-overlapping case.
- No deletion (local or remote) of an uploaded register photo as a side effect of
  anything in this pipeline.
