# Register Photo & OCR Architecture

> **Phase 0.6 update.** Seven high-resolution photographs of the real register have been
> analyzed ([18_REGISTER_SAMPLE_ANALYSIS.md](18_REGISTER_SAMPLE_ANALYSIS.md)) and the
> pipeline below is confirmed, with four refinements now baked into the frozen schema:
>
> 1. **Columns must be mapped by header text, per page** — the physical register's
>    `Sex`/`Age` column order changes between pages and column widths are hand-drawn.
>    Fixed positional mapping would silently swap fields.
> 2. **Preprocessing is mandatory, and originals are never modified** — pages show skew,
>    window glare, binding-gutter compression, a holder's hand at the edges, and desk
>    clutter in frame. Processed variants live in `register_photo_derivatives`; the
>    original row in `register_photos` is immutable.
> 3. **Raw extraction and human corrections are stored separately** —
>    `ocr_results.extracted_fields` (never edited) vs `corrected_fields`, with an
>    explicit `verification_status` (`UNREVIEWED → IN_REVIEW → CONFIRMED/REJECTED`) and
>    `source_region` (row bounding box) for traceability back to the image.
> 4. **Disease shorthand resolves through `disease_aliases` as a suggestion only** —
>    the register uses `Vit A`, `S.I`, `Carries` alongside full official wording like
>    `Cleft lip & palate`. A suggested match is never auto-applied.
>
> Fields the register does **not** contain — Class, Refer To, and (in practice) Serial
> No. — are never inferred by OCR. They are supplied by the app's session context or
> left null.

## Pipeline stages

```
1. CAPTURE          (device, offline)      camera/image_picker → in-memory image
2. QUALITY CHECK    (device, offline)      blur/glare/crop heuristic → accept or re-capture prompt
3. SAVE ORIGINAL    (device, offline)      write to app-private storage; insert register_photos row
                                            (upload_status=LOCAL_ONLY); enqueue for sync
── offline boundary — nothing below runs until connectivity is available ──
4. CLOUD UPLOAD      (sync engine)         binary → Supabase Storage; upload_status→UPLOADED
5. OCR JOB DISPATCH  (server-side trigger) insert ocr_jobs row (status=QUEUED) once uploaded
6. IMAGE PROCESSING  (cloud)               deskew, contrast normalize, table/row-boundary detection
7. OCR EXTRACTION    (cloud engine)        per detected row → field-level text + confidence
8. RESULT STORAGE                          ocr_results rows (jsonb fields + confidence), job→COMPLETED
9. USER REVIEW       (device, app)         OCR Review Queue → per-photo → per-row review UI
10. EDIT / CONFIRM   (device, app)         low-confidence fields highlighted; user edits; confirms
11. COMMIT           (device, app)         confirmed row → INSERT into school_screenings /
                                            awc_screenings, linked back to source_photo_id +
                                            ocr_result_id; ocr_results.is_reviewed=true
```

Stages 1–3 are the only ones on the offline-critical path (PRD FR-13.1 requires the
whole pipeline conceptually, but nothing after capture blocks fieldwork — see
[05_TECHNOLOGY_STACK.md](05_TECHNOLOGY_STACK.md) OCR rationale).

## Where OCR dispatch runs

Two options, both compatible with this schema:
- **Server-triggered**: a Supabase Edge Function fires on `register_photos.upload_status`
  transitioning to `UPLOADED`, creates the `ocr_jobs` row, and calls the OCR engine.
- **Client-triggered**: the app, once it observes its own upload completed, calls an API
  to kick off the job.

Recommend **server-triggered** — it works even if the capturing device never comes back
online (another admin device can still see photos need OCR), and keeps OCR orchestration
out of the mobile app's responsibility.

## Confidence & review UX

- Each extracted field carries a confidence score (0–1). A threshold (tunable, starting
  point ~0.75, to be calibrated against real sample photos once available — see
  [../SOURCE_MATERIALS_REQUIRED.md](../SOURCE_MATERIALS_REQUIRED.md)) below which a
  field is visually flagged (e.g. yellow highlight) in the review form.
- Review UI shows the source photo (zoomable, cropped to the row where possible)
  alongside the extracted fields, so the reviewer can verify against the original
  without leaving the screen.
- **Nothing commits without explicit confirmation** — batch "Confirm All" is offered for
  speed on high-confidence rows, but always as an explicit action, never a default/timer.

## Duplicate detection

Before commit, check for an existing `school_screening`/`awc_screening` in the same
`visit_plan_id` (+ `class_label` for school) with a close name match (e.g. normalized
string similarity) and same/similar age — surface as a non-blocking warning banner
("possible duplicate of <existing row>") on the review form, not an automatic block,
since two children can legitimately share a name.

## Multi-page / multi-photo registers

- A visit can have many `register_photos`; each gets its own `ocr_jobs`/`ocr_results`
  chain independently.
- The review queue groups by visit, then by photo, so a Medical Officer reviewing an
  entire day's registers works through one coherent batch.

## Traceability

Every committed screening row keeps `source_photo_id` and `ocr_result_id` (nullable —
manually entered records simply have both null), so any record can be traced back to
"which photo, which extracted row, reviewed by whom, when" — directly supporting audit
requirements in [08_SECURITY_ARCHITECTURE.md](08_SECURITY_ARCHITECTURE.md).

## What's deferred pending source material

The exact OCR engine choice, confidence threshold tuning, and table/row-detection
approach depend on real register photo samples (structured pre-printed form vs. plain
ruled register — materially different table-detection difficulty). This document
specifies the pipeline shape and data contracts (§ above), which hold regardless of
which engine is finally chosen.
