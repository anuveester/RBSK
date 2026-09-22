# Screen Map

## Navigation shell

Bottom navigation (or drawer — either is fine; recommend bottom nav for 4–5 primary
destinations given the "simple as a register" principle):

**Home · Visits · Referrals · Reports · More**

`More` holds lower-frequency destinations (Masters, Staff, Settings, Admin) to avoid
cluttering primary navigation for a Medical Officer who mostly lives in Home/Visits/
Referrals.

## Full screen inventory

### Auth
1. **Login** — username/email + password (or PIN after first login). No self-signup.
2. **Forced Password Reset** (first login / admin-triggered) — optional, low priority.

### Home
3. **Home / Dashboard** — Today's Visit card (deep-links to visit plan for today),
   sync status chip, pending-treatment count, quick shortcuts (+ Special Visit,
   Register Photo).

### Visit Planning
4. **Visit Plan List** — by Financial Year, filterable by status/month/location type.
5. **Visit Plan Detail** — target, dates (original + current), status, history log,
   actions (Start Visit, Mark Missed, Reschedule, Reopen).
6. **Add Special Visit** — date picker (unrestricted), School/AWC search, reason.
7. **Missed Visits** — filtered list view over Visit Plan (status = MISSED).
8. **Reschedule Visit** — from Missed Visit, pick new date, reason carried forward.
9. **Holiday Calendar** — list by FY, add manual holiday.

### School Visit / Screening
10. **School Visit Landing** — School + Date context banner, Class selector
    ("Select Class" / "Change Class"), running count for this visit, list of children
    entered so far, **Add Child** / **Capture Register Photo** actions.
11. **Child Entry Form (School)** — Serial No. (auto), Name, Age, Gender, Mother Name,
    Father Name, Normal/Disease toggle → conditional Disease (searchable) + Refer To.
    **Save & Next** returns to a blank form with context intact.
12. **Child List (current visit/class)** — quick edit/delete (soft) of entries made in
    this session.
13. **Complete Visit** — summary counts (screened/normal/referred, class-wise,
    gender-wise), confirm → status → COMPLETED.

### AWC Visit / Screening
14. **AWC Visit Landing** — AWC + Date context, list of children entered, **Add Child**
    / **Capture Register Photo**.
15. **Child Entry Form (AWC)** — full Job Aid-derived form: preliminary particulars,
    ASHA/AWC details, guardian/contact, anthropometry + classification, findings by
    category, developmental screening, referral, doctor/MHT, register reference.
    *(Exact fields pending Job Aid — see PRD FR-8.2.)*
16. **Complete AWC Visit** — summary, confirm.

### Disease / Referred Line List
17. **Referred Line List** — filterable (disease, date, school, class, referral
    destination, FY, month), tap-through to source screening record.

### Master Data
18. **School Master List** — search/filter (district/block/active).
19. **School Detail / Edit**.
20. **Add School (manual)** — for schools not from an imported plan.
21. **AWC Master List** — search/filter.
22. **AWC Detail / Edit**.
23. **Add AWC (manual)**.
24. **Annual Plan Import** (ADMIN) — upload Excel → staging preview (row
    classification, dedup preview) → confirm commit.
25. **Disease Master List** (searchable, mostly read-only for non-admin) — grouped by
    category.
26. **Disease Detail / Edit** (ADMIN).

### Referral / Treatment
27. **Referral/Treatment Worklist** — filters: pending / completed / did-not-attend /
    needs further referral / disease / destination / date / school / month / FY.
28. **Treatment Entry Form** — child + screening context (read-only), Attended,
    Treatment status, Further Referral (+ conditional destination/remarks).
29. **Child Treatment History** — all follow-up records for one child over time.

### Register Photo & OCR
30. **Register Photo Capture** — camera/gallery, attached to current visit.
31. **Register Photo Gallery (per visit)** — view all photos for a visit.
32. **OCR Review Queue** — jobs pending review, grouped by visit/photo.
33. **OCR Row Review** — extracted rows with confidence highlighting, inline edit,
    duplicate-warning banner, per-row Confirm, batch Confirm All.

### Staff / Team
34. **Staff List** (ADMIN).
35. **Staff Detail — Assignment History** (append-only timeline).
36. **Add Staff Assignment** (ADMIN).

### Reports
37. **Report Catalog** — list of report types (per PRD FR-15.1).
38. **Report Filter Panel** — contextual filters per report type (date range / FY /
    month / school / class / disease / etc.).
39. **Report Preview** — on-screen result before export.
40. **Export & Share** — PDF/Excel generation, Android share sheet.

### Admin / Settings
41. **User Management** (ADMIN) — list, add, deactivate; role assignment.
42. **Settings** — profile, change PIN, sync now, sync history/log, app version.
43. **Backup Export** (ADMIN) — manual encrypted backup file, shareable.
44. **Audit Log Viewer** (ADMIN, optional for Phase 0 — read-only trail of
    who/when/what changed).

## Navigation notes

- **Today's Visit** on Home is the single highest-value shortcut — it should resolve
  directly to whatever Visit Plan row matches today's date + this user's team, skipping
  the Visit Plan List entirely when unambiguous.
- Screens 10–13 and 14–16 are two parallel flows sharing the same context-preservation
  pattern (FR-7) — implemented as one reusable "visit session" controller in Phase 1/2,
  not duplicated logic (see [06_PROJECT_STRUCTURE.md](06_PROJECT_STRUCTURE.md)).
- OCR Review (32–33) is reachable both from a notification/badge ("3 photos ready for
  review") and from the source Visit Detail screen.
