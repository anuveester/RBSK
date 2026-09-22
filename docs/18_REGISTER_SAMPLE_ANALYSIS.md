# Register Sample Analysis (Phase 0.6)

Source: `reference_materials/Registered Sample/` — **7 high-resolution photographs**
(4080×3072) of the team's actual physical register, covering April 2026 and May 2026
pages. These supersede the single low-resolution sample analyzed in Phase 0.5
([15_REGISTER_OCR_FIELD_MAPPING.md](15_REGISTER_OCR_FIELD_MAPPING.md)) and are treated
as **authoritative** for physical register structure.

Approximately 90+ data rows were readable across the 7 images. Nothing below is
transcribed unless it could be read with reasonable confidence; uncertain readings are
marked **(uncertain)** and were not used to drive any design decision.

## 1. Page layout

A bound, hardcover ruled notebook (decorative patterned cover), photographed open, two
facing pages per photo, held by hand on a desk. Columns are **hand-drawn in ink**
(blue or brown pen) over the notebook's pre-printed horizontal rules — there is no
pre-printed form. Column lines run the full height of the page; horizontal row lines are
the notebook's own ruling.

Some pages carry a **hand-written month heading** in large letters at the top right of
the right-hand page: "Aprail 2026" *(sic — "April" is misspelled in the source)* and
"May 2026". Not every page has a heading; continuation pages have none.

## 2. Header structure

The column header row is hand-written at the top of each page spread and **repeats on
every page** (it is not written once at the front of the book). Header wording varies
slightly page to page (see §21).

## 3–4. Visible columns and exact column names

**9 ruled columns**, of which 8 carry headers and 1 is an unlabeled trailing column:

| # | Header as written | Notes |
|---|---|---|
| 1 | `S.N.` / `S.No.` | Column exists on every page but is **never filled in** — see §6 |
| 2 | `Date` | |
| 3 | `School / Aganwadi Name` (also seen: `School OR Aganwadi Name`, `School's or Aganwadi's Name`) | *"Aganwadi"/"Anganwadi"* spelling varies |
| 4 | `Child's Name` | |
| 5 | `Sex` | order relative to Age varies — see §21 |
| 6 | `Age` | |
| 7 | `Father's Name` | |
| 8 | `Mother's Name` | |
| 9 | `Disease` | |
| 10 | *(no header)* | Unlabeled trailing column, used rarely — see §16 |

## 5. Row structure

One child per row. Rows are grouped into **date/institution blocks**: the Date and
School/Anganwadi Name are written once on the first row of a block, and the following
rows for the same institution/day leave those cells blank (a forward-fill convention
identical to the one found in the Micro Plan Excel). Blocks are separated by one or more
blank ruled lines — spacing is irregular (1–4 blank lines).

Within a single date, a **second institution block may appear with no new date** (e.g.
`02/04/2026 UPS Raipur` followed by an undated `P.S. Kadoran Raipur` block), meaning
both were visited the same day.

## 6. Serial number pattern

**The `S.N.` column is present on every page and empty on every observed row.** No
serial numbers were found anywhere in the 7 images. The digital model's auto-assigned
`serial_no` therefore has **no counterpart in the physical register** and must not be
expected from OCR.

## 7. Date format

`DD/MM/YYYY` with `/` separators, e.g. `01/04/2026`, `13/05/2026`. Some rows abbreviate
the year: `12/05/26`.

Two anomalies observed, **not corrected and not assumed to be typos**:
- Two rows on the April 2026 spread read `16/04/2024` and `17/04/2024` — year `2024`
  where the surrounding sequence implies 2026 **(uncertain: may be a habitual
  mis-write, or a "6" read as "4")**.
- One row dated `05/02/2026` appears physically between April 2026 and May 2026 rows,
  breaking chronological order.

## 8. Class representation

**There is no Class column and no class value anywhere in the register.** Class is not
recorded in this book at all. This is the single largest divergence from the previously
assumed 10-field model.

## 9. Child name field

Single free-text column, first name only in nearly all rows (e.g. *Devika, Nihal, Kirti,
Baby boy*). One row records an unnamed infant as `Baby boy`.

## 10. Age field

Written as a number plus a unit suffix: `8yr`, `9y`, `11yr`, `13y`. Infants are recorded
in months: `6m`, `3m`. Unit usage is inconsistent (`yr` / `y` / `y.`).

## 11. Gender representation

Single lower-case letter in the `Sex` column: `m` / `f`. A few glyphs are ambiguous
between `m` and `n`/`w` **(uncertain)**. No third-gender value observed.

## 12–13. Mother name / Father name

Two separate free-text columns, first name only in nearly all rows. Both are populated
consistently; a few cells appear to have the father's and mother's names in the opposite
order relative to neighbouring rows **(uncertain — cannot be confirmed from the image
alone)**.

## 14. Disease / finding field

Free text, in a **mixture of abbreviation and full official wording**:

| As written | Apparent meaning | Confidence |
|---|---|---|
| `Vit A` / `VitA` / `Vit. A` | Vitamin A Deficiency (Job Aid code 11) | High |
| `S.I` / `S.I.` | Skin Infection — the same page also spells out `Skin-infection` in full on one row, which is the basis for this reading (Job Aid code 15, Skin Conditions) | High, **still to be confirmed by the MO** |
| `Carries` / `Carrics` / `Carnies` | Dental Caries (Job Aid code 19, Dental Conditions). *Phase 0.5 read this as "Cornea" from the low-resolution image — that reading was wrong and is hereby corrected.* | High |
| `Otitis media` / `Otitismedia` | Otitis Media (Job Aid code 16) | High |
| `SAM` | Severe Acute Malnutrition (Job Aid code 13, "SAM up to 60 mon.") | High |
| `Cleft lip & palate` | Cleft Lip & Palate (Job Aid code 3) — written in full official wording | High |

Only **one** finding per row was observed; no row lists two diseases. This does not
prove the register cannot hold two — it may simply not have occurred in these pages.

## 15. Referral field

**There is no referral / "Refer To" column.** Referral destination is not recorded in
this register at all. The closest thing observed is the word `Admit` (and once
`Adimit`, *sic*) written in the unlabeled trailing column for two severe cases — see
§16.

## 16. Additional fields

The **unlabeled trailing column** is used on 3 rows out of 90+, always for escalation
context on a severe case:
- a 10-digit contact number + `Admit` — beside a `SAM` finding for a 6-month-old at an
  Anganwadi.
- a 10-digit contact number — beside a `SAM` finding at "Adimit Awc. Jakhaura"
  *(uncertain reading of the institution name)*.
- a 10-digit contact number — beside the `Cleft lip & palate` finding for a
  3-month-old.

*(The numbers themselves are child-linked contact data and are deliberately not
reproduced in version-controlled documentation; they remain in the source photographs,
which are excluded from version control.)*

Functionally this is an **ad-hoc remarks / contact-number / escalation note** column.
It maps to `school_screenings.remarks` / `awc_screenings.remarks` in the frozen schema.

## 17. Fields from the earlier assumed 10-field model that are NOT present

| Assumed field | Present in the real register? |
|---|---|
| Serial No. | Column exists, **never filled** |
| Date | ✅ |
| **Class** | ❌ **absent entirely** |
| Child Name | ✅ |
| Age | ✅ (years or months) |
| Gender | ✅ (`Sex`, m/f) |
| Mother Name | ✅ |
| Father Name | ✅ |
| Disease | ✅ (free text, abbreviated or full) |
| **Refer To** | ❌ **absent entirely** |

Two additional realities the model did not anticipate:
- An **institution column** (`School/Aganwadi Name`) that the digital model instead
  derives from the visit's school/AWC link.
- An **unlabeled remarks column**.

## 18. Handwriting characteristics

Latin script (English) throughout. **No Devanagari appears anywhere in the 7 images** —
including in names, which are written in romanised form. Mixed print/cursive, generally
legible to a human reader, written with a fine ballpoint. Digits are clearer than
letters. Names are the hardest field to read with certainty; short disease abbreviations
are the easiest.

## 19. Does handwriting vary between rows?

Yes, but moderately. At least **two distinct hands** appear across the set: the April
pages are written in a rounder, more upright hand than the May pages, and the column
headers appear to be drawn by whoever started each page. Pen colour changes between
pages (blue vs. brown column rules). Within a single date block the handwriting is
consistent, suggesting one person writes a whole visit's rows.

## 20. Is image quality sufficient for OCR?

For these particular photographs: **yes, marginally, for a cloud handwriting engine
with mandatory human review** — but not sufficient to expect unattended accuracy.

- Resolution (4080×3072) is ample; individual characters are well resolved.
- Lighting is uneven: a bright window reflection washes out the upper-right of several
  pages, and the photographer's hand/shadow darkens the lower-left corner.
- The page curves into the binding gutter, compressing the `Sex`/`Age` columns where
  they sit near the centre fold on some spreads.
- Background clutter (laptop keyboard, shortcut-key card, desk) is present at the page
  edges on every photo and must be cropped out before OCR.

## 21. Are columns visually consistent?

**No — and this is a load-bearing finding for OCR design.**
- The **order of `Sex` and `Age` swaps between pages.** Some spreads read
  `… Child's Name | Sex | Age | Father's Name …`, others read
  `… Child's Name | Age | Sex | Father's Name …`.
- Column widths differ from page to page (hand-drawn).
- Header wording varies (`School / Aganwadi Name` vs. `School OR Aganwadi Name` etc.).

OCR therefore **cannot rely on fixed column positions**. It must detect the header row
per page and map columns by header text, with a human confirming the mapping.

## 22. Are rows skewed / merged / cut off?

- **Skew:** yes, mild. Pages are photographed at a slight angle; hand-drawn column lines
  are not perfectly vertical and drift by several degrees down the page.
- **Merged:** no true merged cells, but the forward-fill convention (§5) means Date and
  Institution cells are *visually* blank for most rows in a block.
- **Cut off:** the left edge (the `S.N.` column) is clipped or obscured by the holder's
  hand on several images; one image loses part of the trailing column at the right edge.
- **Gutter compression:** the centre fold compresses columns that fall across it.

## 23. Stamps, signatures, marks, overwriting, corrections

- **No stamps and no signatures** anywhere in the 7 images.
- A small number of **strike-throughs / overwrites** on individual names (a letter
  written over another). No whole-row cancellations.
- AWC entries use a **circled ordinal**: `Awc Jkh No.①` … `No.⑧`.
- Some institution names carry a trailing `(A)` — e.g. `Jamoramafi (A)`,
  `Madawari (A)` — apparently marking an Anganwadi. Its use is inconsistent (other AWC
  rows instead start with `AWC …`).

## 24. Abbreviations actually visible

| Abbreviation | Reading | Confidence |
|---|---|---|
| `P.S.` | Primary School | High (matches `PS` in the Micro Plan) |
| `UPS` | Upper Primary School | High (matches Micro Plan) |
| `Com.` / `Comp` | Composite school | Medium — matches `COM` in the Micro Plan |
| `AWC` / `Awc` | Anganwadi Centre | High |
| `Jkh` | Jakhaura | High (block name in the Micro Plan) |
| `(A)` suffix | Anganwadi | Medium |
| `Vit A`, `S.I`, `SAM` | see §14 | see §14 |
| `Admit` / `Adimit` | child admitted for treatment | Medium |
| `m` / `f` | male / female | High |
| `y` / `yr` / `m` (age) | years / months | High |

---

## What this register actually is

**Every one of the 90+ observed rows carries a disease/finding value. Not a single row
records a normal child.** Combined with the absence of a Class column and of any
per-class totals, the evidence strongly indicates this book is a **Disease / Referred
Child Line List** — a ledger of affected children only — and **not** the full class-wise
screening register in which every screened child (normal and affected) would appear.

This remains an inference, not a confirmed fact, and it carries a direct consequence:
if the full screening register exists as a separate book, its photographs have not been
supplied, and the OCR pipeline has therefore only been designed against the line-list
format. **Confirmation required from the Medical Officer** — see
[21_PHASE_0_6_FREEZE.md](21_PHASE_0_6_FREEZE.md) §Unresolved.

The register also mixes **School and AWC** entries in one continuous book, with no
type column — the workflow type is inferable only from the institution-name prefix
(`P.S.`/`UPS`/`Com.` vs `AWC`/`(A)`), which is itself inconsistently applied.

## Direct consequences for the architecture

| Finding | Consequence (applied in the frozen schema) |
|---|---|
| No Class column | `school_screenings.class_label` is **nullable**; OCR cannot supply it, app session context can |
| No Refer To column | `referral_destination_id` on findings is nullable; OCR never infers a destination |
| Serial No. never filled | `serial_no` is app-assigned only; never expected from OCR |
| Unlabeled remarks column | mapped to `remarks` on the screening tables |
| Age in years *or* months | `age_years` + `age_months` both present on `school_screenings` |
| Sex/Age column order swaps | OCR must map columns by **header text**, never by fixed position |
| Disease written as shorthand | `disease_aliases` table — suggestions for human review, never auto-applied |
| Skew, glare, gutter, clutter | preprocessing stage is mandatory; originals preserved separately in `register_photo_derivatives` |
| Two distinct handwriting styles | per-page confidence will vary; no global confidence threshold can be assumed |
| Line-list, not full screening register | the digital model stores **all** screened children regardless; OCR import covers only what the register contains |
