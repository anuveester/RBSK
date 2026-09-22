# Referral Configuration (Phase 0.6)

**[USER-DECIDED]:** School and AWC referral vocabularies are **context-specific and are
never merged**. There is no single universal referral dropdown. Destinations are
configuration data (`referral_destinations` + `referral_destination_contexts`), not a
hard-coded enum — see [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md) §2.8.

## 1. Why configuration rather than an enum

- The School list is a working vocabulary confirmed by the product owner; the AWC list
  is dictated by the official Job Aid and is **category-dependent**. One enum cannot
  represent both without either polluting School with AWC-only values (DEIC, NRC) or
  flattening the Job Aid's routing rules.
- Destinations will plausibly change (a new DEIC opens, a facility is renamed) without
  any code change being desirable.
- A row in a lookup table can carry `source_reference`, so each destination records
  *why* it exists.

## 2. School destinations **[USER-DECIDED — working vocabulary, no official source document]**

| code | label | Applies to |
|---|---|---|
| `PHC_CHC` | PHC/CHC | all School finding categories |
| `DISTRICT_HOSPITAL` | District Hospital | all School finding categories |
| `HIGHER_CENTER` | Higher Center | all School finding categories |

Seeded as three `referral_destination_contexts` rows with `context = 'SCHOOL'` and
`finding_category = NULL` (all categories).

⚠ **No School (6+ years) job aid or referral card has ever been supplied.** This list is
the product owner's confirmed working vocabulary, not a transcription of an official
document. If an official School referral card later shows different destinations, this
is configuration data and can be changed without a migration.

## 3. AWC destinations **[SOURCE-DERIVED — RBSK Job Aid 0–6 years, page 4]**

Facilities named on the form:

| code | label | Source |
|---|---|---|
| `PHC` | PHC | Job Aid p.4 referral row |
| `CHC` | CHC | Job Aid p.4 referral row |
| `DH` | District Hospital (DH) | Job Aid p.4 referral row |
| `DEIC` | District Early Intervention Centre (DEIC) | Job Aid p.4 referral row |
| `NRC` | Nutrition Rehabilitation Centre (NRC) | Job Aid p.4, SAM routing |

### Category routing, exactly as printed on the form

| Finding category (`disease_category`) | Destinations offered |
|---|---|
| `DEFECTS_AT_BIRTH` | `DH`, `DEIC` |
| `DEFICIENCIES` | `PHC`, `CHC` — and `NRC` (the form routes SAM specifically to NRC) |
| `DISEASES` | `PHC`, `CHC`, `DH` — and `DEIC` (the form routes Dental condition to DEIC/DH) |
| `DEVELOPMENTAL_DELAY_DISABILITY` | `DEIC` |
| `OTHERS` | `PHC`, `CHC`, `DH` |

Each row above becomes one `referral_destination_contexts` row with
`context = 'AWC'` and the stated `finding_category`.

### Rules carried from the form but **not** auto-enforced

- *"SAM to NRC"* and *"Dental condition to DEIC/DH"* are **finding-level** routing
  hints inside a category. The schema configures destinations at category granularity,
  so the app surfaces these as a **hint on the relevant finding** (SAM → suggest NRC;
  Dental Conditions → suggest DEIC/DH) while still allowing the clinician to choose any
  destination valid for the category. The app does not silently force the routing.
- *"In case the referral has to be made for more than 1D especially involving the DEIC,
  the child must be referred to DEIC first."* This priority rule is **displayed to the
  user as guidance** when a child has findings across multiple categories and one of
  them routes to DEIC. It is **not** auto-applied — the app does not override a
  clinician's destination choice. **[NOT YET IMPLEMENTED beyond the advisory message]**

## 4. Per-category referral Yes/No

The Job Aid records referral **per category**, not per child: a child may have a Defects
finding that is not referred and a Deficiency finding that is. The frozen schema already
supports this — `referral_destination_id` sits on each **finding** row
(`school_screening_findings` / `awc_screening_findings`), not on the screening record.
No change needed; noted here so it is not "simplified" later.

## 5. Treatment follow-up destinations

`treatment_records.further_referral_destination_id` resolves against the same
`referral_destinations` table, filtered by the **context of the originating screening**
(School treatment records offer the School list; AWC treatment records offer the AWC
list). Required if and only if `further_referral = true` (DB CHECK constraint).

## 6. Admin management

Destinations and their context mappings are ADMIN-editable (see the RBAC matrix). Rows
are deactivated via `is_active = false`, never deleted, so historical findings keep
resolving to the destination that was recorded at the time.

## 7. Open items

| Item | Needed from |
|---|---|
| Whether School's three destinations match any official document | Medical Officer / district health authority |
| Whether "Higher Center" corresponds to a specific facility type (DH? DEIC? medical college?) | Medical Officer |
| Whether AWC findings ever route to a facility not listed on page 4 | Job Aid annexure / district confirmation |
