# Real-Device Security Test Checklist

**Status: NOT RUN.** No item below has been performed on a phone. Every
behaviour listed here has been tested only in unit, widget and integration
tests on a development machine (docs/31 §20). This checklist is what must be
run, on real Android phones, **before any real child or health data is
entered**.

| | |
|---|---|
| Date written | 2026-09-24 |
| Applies to | Phase 1.4 + security hardening + final security review |
| Build | a debug or release APK from the commit that adds this file |
| Data | **synthetic only**: invented names, test PINs, test codes |

## How to run it

- **Phones:** at least two, ideally three:
  - the lowest-spec phone the team will actually use (for timing);
  - a common mid-range phone;
  - one from a manufacturer with aggressive battery or backup customisation
    (for example Xiaomi, Oppo, Vivo, Realme or Samsung).

  Record each phone's model, Android version and security patch level.
- **Recording results:** write a result for every item: **PASS**,
  **FAIL**, or **N/A** with a reason. Keep screenshots only where
  screenshots are allowed. Never photograph a real recovery code.
- **Secrets during testing:** test PINs and codes may be written on the
  test sheet only. Destroy the sheet afterwards. Never put them in Git,
  chat, email or a ticket.
- **A failure:** stop, note the exact steps, and report it. Do not work
  around it on the phone.

---

## A. First install and first-run Admin setup

- [ ] Install the APK on a clean phone. The app opens to Admin setup, with
  no default PIN.
- [ ] Set a name and a 6-digit PIN. The Admin Recovery Code is shown once.
- [ ] The code cannot be continued past without ticking "written down" and
  typing its last group.

## B. Screenshot and screen-recording block (`FLAG_SECURE`)

Try a screenshot (power + volume down) and a screen recording on:

- [ ] the Admin Recovery Code display (setup, after a PIN reset, after
  replacing the code);
- [ ] the Backup Recovery Key display;
- [ ] the "forgot PIN" screen, where the recovery code is typed;
- [ ] every step of "Restore from backup", including the Admin-access step.

Each must be blocked, or must capture black. Then check:

- [ ] the Recents / app-switcher thumbnail of these screens is blank;
- [ ] after leaving these screens (for example back to Home), screenshots
  work again. Protection must switch off only when the last protected
  screen closes.

## C. Keyboard behaviour on secret fields

Test with Gboard and the manufacturer's own keyboard.

- [ ] On the recovery-code, backup-key and PIN fields, there are no word
  suggestions and no autocorrect.
- [ ] Gboard shows its incognito indicator on the recovery-code and
  backup-key fields.
- [ ] After typing a code, open a normal text field (for example in
  another app). The code's groups are not offered as suggestions.

## D. Clipboard

- [ ] Long-press or select text in the recovery-code and backup-key
  fields. The menu offers **no Copy and no Cut**; Paste still works.
- [ ] The displayed codes cannot be selected or copied.
- [ ] Android 13+: no "copied" clipboard preview appears at any point.

## E. Login, lockout and session

- [ ] A correct PIN logs in; a wrong PIN shows "Incorrect PIN".
- [ ] 5 wrong PINs lock the account for about 60 s. The correct PIN is
  refused during that time.
- [ ] Kill the app and reopen it. The session is restored without a PIN,
  offline. Logout returns to login.

## F. KDF timing (benchmark; informs the iteration decision)

- [ ] On each phone, time 10 logins from tapping "Log in" to Home
  (stopwatch or `adb logcat` timestamps). Record the median and the worst
  time.
- [ ] Time the PIN confirmation before export and before replacing a code.
- [ ] **Do not change the 210,000 iteration count on the basis of this
  checklist.** Report the numbers; the decision is separate.

## G. Admin Recovery Code: PIN reset

- [ ] On login, tap "Forgot PIN?", enter the code and a new PIN. The PIN
  is reset, a **new** code is shown once, and the Admin is signed in.
- [ ] The old code no longer works.
- [ ] Data entered before the reset is still there.
- [ ] Entering the Backup Recovery Key here is refused, with a message
  saying it is the wrong kind of code.
- [ ] Enter a wrong code (valid format) 5 times. Further attempts are
  locked for a while.

## H. Replacing the Admin Recovery Code

- [ ] More → Admin Recovery Code → create new. It asks for the PIN; a wrong
  PIN is refused.
- [ ] With the right PIN, a new code is shown and the old code stops
  working.

## I. Role separation on the device

Needs a Medical Officer and a Team Member account. These can only be created
once user management exists; until then, mark **N/A (blocked by user
management)**.

- [ ] Log in as each role. The More menu shows no Admin items.
- [ ] Deactivate a logged-in user (when that feature exists) and reopen the
  app. The user is logged out.

## J. Backup Recovery Key setup

- [ ] More → Backup Export → set up the key. It asks for the PIN, then the
  `BK-…` key is shown once.
- [ ] The key ID (for example `3F9A-12C4`) is shown on the screen.

## K. Creating an encrypted backup (export)

- [ ] "Create encrypted backup", then confirm, then **enter the PIN**. A
  wrong PIN is refused and no file is offered.
- [ ] The Android "save" picker opens. Save to:
  - Downloads;
  - a USB drive or SD card (if available);
  - a cloud-drive app (if one is installed; note which).

  Each save works.
- [ ] Cancel the picker. The message says "not saved", and no file is
  left in the app's cache (check with `adb shell run-as` on a debug build).
- [ ] Copy the saved `.rbskrp` file to a computer and open it in a text or
  hex viewer. Test names entered in the app do not appear, and there is no
  `SQLite format 3` header.

## L. Export when storage is nearly full

- [ ] Fill the phone to under ~50 MB free and try an export. It fails with
  the "not enough free space" message and does not hang.
- [ ] Free the space and try again. It works.

## M. Restore on a new phone

- [ ] On a second phone with a fresh install, choose "Restore from backup"
  on the setup screen, pick the package, and enter the Backup Recovery Key.
  The confirmation shows the backup date.
- [ ] Confirm. The data appears. "Set Admin PIN" with the Backup Recovery
  Key works, and a new Admin Recovery Code is shown.
- [ ] The Admin Recovery Code from the **old** phone does **not** open the
  package. It is refused as the wrong kind of code.

## N. Restore is refused over data in use

- [ ] On a phone that has been set up and has data, try every route to
  "Restore" (setup screen, login banner, typing the route if a debug tool
  allows it). The restore is not offered, or it is refused with "this
  phone already has data and accounts in use". Nothing changes.

## O. Wrong or damaged packages

- [ ] Wrong Backup Recovery Key: the message says it is a different key,
  and nothing changes.
- [ ] A damaged package (change a few bytes on a computer) is rejected as
  damaged, and nothing changes.
- [ ] A random non-package file is rejected.

## P. Restore when storage is nearly full

- [ ] With too little free space to unpack the package, the restore fails
  at "Check backup" with the free-space message. The phone's existing data
  still opens normally.

## Q. Power loss or crash during restore (most important)

For each of the following, then reopen the app:

- [ ] Force-stop the app (`adb shell am force-stop com.rbsk.referredline`)
  **immediately** after tapping "Restore now".
- [ ] Pull the battery, or hold power to force a reboot, during "Restore
  now" (repeat several times, at slightly different moments).

After reopening, the phone must be in exactly one of two states:

- the **previous** data opens normally (the restore was undone); or
- the **restored** data opens normally (the restore had finished).

It must **never**:

- show a locked or half-restored state;
- lose the previous data.

Check the app-private folder on a debug build: the previous database is
either in place or kept as `…preserved-…`, and no `.restore-marker` file
remains.

## R. Database key unavailable (locked data)

On a debug build only, if possible:

- [ ] Clear the key namespace's preferences (`rbsk_database_key`) with
  `adb shell run-as`, leaving the database file in place. The app shows
  "Your data is locked… NOT been deleted", and no new empty database is
  created.
- [ ] Restore from a package. The data returns, and the locked file is kept
  as `…preserved-…`.

## S. Real Keystore failure behaviour

These may not be reproducible on every phone. Record what happens.

- [ ] Change the screen lock (PIN → pattern → none → PIN), then reopen the
  app. The app still opens, or shows the locked or secure-storage screen.
  **Nothing is silently wiped.**
- [ ] After an OS update (if one is pending on a test phone), reopen the
  app. Same expectation.

## T. Android backup and device transfer are disabled

- [ ] Settings → Google → Backup: back up now, then check the app's entry
  in the backup list. It has no app data, or is excluded.
- [ ] Run `adb backup` (where still supported). It produces an empty
  archive for the app.
- [ ] Device-to-device transfer (the manufacturer's phone-clone tool, and
  the Google cable/Wi-Fi transfer on Android 12+) to another phone. The
  app's data is **not** transferred; the new phone starts at setup.
- [ ] **OEM behaviour must be recorded per manufacturer.** Some clone tools
  ignore Android's rules.

## U. Audit trail

- [ ] After G–Q, pull the database with a debug build and the key (a
  development-only procedure). `audit_log` has `security_event` rows for
  each action, including `privilegedActionDenied` for wrong-PIN export
  attempts and `restoreRolledBack` / `interruptedRestoreResolved` after Q.
- [ ] The rows contain no PIN, code, key or file path.

## V. Leftover temporary files

- [ ] Kill the app while the export "save" picker is open. On the next
  start, the app's cache `recovery` folder is empty (debug build,
  `run-as`).

## W. Activity recreation during the file picker

- [ ] Open the save or open picker, rotate the phone, or switch to another
  app and back. Note whether the screen stays busy (this is a known
  limitation, docs/31 §15 #2).

## X. Offline

- [ ] With airplane mode on, run A, E, G, K (save to Downloads) and M.
  Everything works; no network is needed.

## Y. Uninstall and reinstall

- [ ] Uninstall and reinstall. The app starts at setup (no data survives
  uninstall; there is no platform backup). A package saved outside the app
  restores it (M).

## Z. Sign-off

- [ ] All items are PASS, or FAIL items are recorded with issues raised.
- [ ] The KDF timing (F) is reported for the iteration decision.
- [ ] OEM results (T) are recorded per manufacturer.
- [ ] The test sheet with test codes is destroyed.

| Phone | Android / patch | Tester | Date | Result |
|---|---|---|---|---|
| | | | | |
