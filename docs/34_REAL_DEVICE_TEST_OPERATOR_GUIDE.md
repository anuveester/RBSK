# Phone Test Guide (for the person holding the phone)

> **HISTORICAL — REMOVED IMPLEMENTATION (2026-09-24).** The Phase 1.4 authentication implementation was intentionally removed. Authentication will be redesigned and implemented from scratch after the complete functional application is finished.
> This document describes the removed implementation (and, where relevant,
> the backup/recovery features removed with it). None of the code it
> describes is part of the current application, and this document is not a
> plan for restoring it. Current status:
> [00_PROJECT_MASTER_PLAN.md](00_PROJECT_MASTER_PLAN.md) §0.
>
> **Real-device testing with this document is permanently stopped.**

This guide checks, on a real Android phone, that the app's security works
the way it was designed. You do not need to be a developer. Everything is
done with normal phone actions.

**Report results only for what you actually did and saw.** If you skip a
test, say "not run". That is fine and useful.

---

## Before you start: 5 safety rules

1. **Use only made-up data.** Name the Admin **Test Admin 001**. Never type
   a real child's, parent's or staff member's name, phone number or health
   detail.
2. **Choose new test PINs.** Never use your phone's unlock PIN, a bank PIN,
   or any PIN you use elsewhere. Suggested: pick two 6-digit numbers just
   for this test.
3. **Never send PINs, codes or keys to anyone,** including in your report.
   Write them only on the paper test sheet. Tear up the sheet when testing
   is finished.
4. **Do not photograph code screens with another phone.** Describe what
   you see instead.
5. **Do not upload the backup file** to WhatsApp, email, Google Drive or
   any other service during this test. Copy it only with a USB cable.

**The paper test sheet.** Keep one sheet of paper with these lines, filled
in as you go:

| Item | Written value |
|---|---|
| Test PIN 1 | |
| Test PIN 2 | |
| Admin Recovery Code #1 (AR-…) | |
| Admin Recovery Code #2 (AR-…) | |
| Backup Recovery Key (BK-…) | |
| Backup Key ID (e.g. 3F9A-12C4, **not secret**) | |

---

## Step 0: Tell us about the phone

Send these details before testing:

| Question | Your answer |
|---|---|
| Manufacturer (e.g. Samsung, Xiaomi, Vivo) | |
| Model (Settings → About phone) | |
| Android version (Settings → About phone → Software information) | |
| Free storage (Settings → Storage) | |
| Can you turn on Developer options / USB debugging? (yes / no / don't know; **not required**) | |
| Is this a spare test phone, or a phone with your real personal data? | |
| Is a second Android phone available for the restore test? | |

**Do not send** the phone's IMEI or serial number, your Google password,
your phone unlock PIN, or any other password.

**Spare vs. personal phone.** Most tests are safe on any phone: the app
keeps its data in its own private area. Tests marked
**🔸 SPARE PHONE ONLY** (G6, I2, J2) must be done only on a phone that
holds no real data you care about.

---

## Step 0b: Put the app on the phone

The file to install is:

```
build\app\outputs\flutter-apk\app-release.apk
```

It is in the project folder on the computer (about 57 MB, version
1.0.0 (1), built from commit `07e6807`). Its SHA-256 fingerprint begins
`30281649 40161dca`.

1. Connect the phone to the computer with a USB cable. On the phone, choose
   **File transfer**.
2. Copy `app-release.apk` into the phone's **Download** folder.
3. On the phone, open the **Files** app → **Downloads** → tap
   `app-release.apk`.
4. If Android asks, allow **"Install unknown apps"** for the Files app (for
   this one install). Afterwards you may turn that permission off again.
5. If **Play Protect** warns "unknown app", this is expected for a test
   build. Choose **Install anyway**.

---

## How to report each test

For each test, send one line like this:

> **A1: PASS** — installed and opened, setup screen appeared.
> **B3: FAIL** — after 5 wrong PINs it still let me try again (message was "…").
> **H5: NOT RUN** — my phone has no screen recorder.

- If something fails, **stop and report it before continuing**.
- Screenshots are welcome **except** on screens that show or ask for a
  code or key. Those screens should block screenshots anyway.

The column **"Changes data?"** in each table tells you whether the test
creates or changes test data inside the app.

---

## Group A: Installation

**A1: Fresh install**

| | |
|---|---|
| Purpose | The app installs and starts correctly. |
| Steps | Install as in Step 0b. Tap the app icon. |
| Expected | Installs without error. The name is **RBSK Referred Line**. The icon is the plain blue Flutter logo (a custom icon is not designed yet). The **"Set up Administrator"** screen opens. No crash. |
| Report | PASS/FAIL, and anything unusual. |
| Screenshot? | Optional (this screen is safe to screenshot). |
| Changes data? | Installs the app only. |

**A2: First Admin setup**

| | |
|---|---|
| Purpose | Admin creation, PIN rules, and the one-time Recovery Code. |
| Steps | 1. Type name **Test Admin 001**. 2. Type PIN "12345" (5 digits) in both boxes and press Create; it should be refused. 3. Type Test PIN 1 in the first box and a different number in the second; it should be refused. 4. Type Test PIN 1 in both boxes, then **Create Administrator**. 5. A screen **"Keep this code safe"** shows a code starting `AR-`. Write it on the sheet as AR #1. 6. **Now do H1** (screenshot test) on this screen. 7. Tick "I have written it down and will keep it safe…", type the **last 3 characters** of the code, then tap **Continue**. |
| Expected | Steps 2–3 show an error. The code appears once. Continue stays disabled until the tick is set and the last 3 characters are typed. Then the **Home** screen opens. |
| Report | PASS/FAIL for each numbered step that behaved differently. |
| Screenshot? | No (code screen). |
| Changes data? | Creates the test Admin. |

**A3: Restart**

| | |
|---|---|
| Purpose | Data and login survive closing the app. |
| Steps | Open recent apps, swipe the app away, then open it again. |
| Expected | It opens straight to **Home** (you stay logged in; see test K1). No error such as "Your data is locked". Then **More → Log out**. The login screen lists **Test Admin 001**. |
| Report | PASS/FAIL. |
| Screenshot? | Optional. |
| Changes data? | No. |

---

## Group B: Login and lockout

Start on the login screen and tap **Test Admin 001** each time.

| ID | Steps | Expected |
|---|---|---|
| **B1** | Enter Test PIN 1 → Log in | Home opens. Then More → Log out. |
| **B2** | Enter a wrong PIN once | "Incorrect PIN." Stays on login. |
| **B3** | Enter wrong PINs until you have made **5 wrong attempts** in total (B2 counts as one) | Each shows "Incorrect PIN." |
| **B4** | Now enter the **correct** Test PIN 1 | Refused: **"Too many incorrect attempts. Try again in N seconds."** (about 60 seconds). |
| **B5** | Wait until 60 seconds have passed since the 5th wrong attempt (use a clock). Do not try tricks such as changing the phone's time. | — |
| **B6** | Enter Test PIN 1 | Home opens. |

- **Report:** PASS/FAIL for each, and the exact message text if it
  differs.
- **Screenshot?** Optional (these screens are safe).
- **Changes data?** No.

---

## Group C: Login speed (important)

**C1: Login timing**

| | |
|---|---|
| Purpose | Measure how long the PIN check takes on this phone. |
| Steps | Log out. Tap Test Admin 001, type Test PIN 1, and have a stopwatch ready. Start the stopwatch the moment you tap **Log in**; stop it when Home appears. Repeat **5 times** (log out between tries). |
| Expected | No fixed pass mark: we are measuring. Note whether the screen freezes, or whether a spinner keeps moving while you wait. |
| Report | The 5 times (e.g. 0.8 s, 0.7 s …), and "spinner moved smoothly" or "screen froze". |
| Screenshot? | No. |
| Changes data? | No. |

**C2 (optional): PIN confirmation timing**

| | |
|---|---|
| Steps | During E2, time from tapping **Confirm** on the PIN box until the save screen opens. |
| Report | The time. |

Do not change any settings to make it faster. The numbers are only
recorded.

---

## Group D: Forgot PIN (Admin Recovery Code)

| | |
|---|---|
| **D1** | Log out. On the login screen, tap **"Admin forgot the PIN? Use the Admin Recovery Code"**. **Do H3 and H6/H7 now** (see Group H). |
| **D2** | Type AR #1 from your sheet. Small letters are OK; dashes are optional. |
| **D3** | Type Test PIN 2 in both new-PIN boxes and submit. |
| Expected | A **new** code `AR-…` is shown once. Write it as AR #2 and cross out AR #1. Confirm it as in A2. Home opens. |
| **D4** | Log out, then log in with **Test PIN 2**. Expected: Home opens. Test PIN 1 no longer works. |
| **D5** | Log out → Forgot PIN → type the **old** AR #1 → any new PIN. Expected: refused ("not correct"). |
| **D6** | Still on Forgot PIN: type the Backup Recovery Key (after Group E) instead of an AR code. Expected: refused, with a message saying it looks like the Backup Recovery Key. |

- **Also check:** after D3, **More** shows no warning, and the login
  screen still lists Test Admin 001 (the existing data is still there).
- **Report:** PASS/FAIL for D1–D6.
- **Screenshot?** No on code screens; optional elsewhere.
- **Changes data?** Yes: the PIN and the recovery code change.

---

## Group E: Making an encrypted backup

Log in with Test PIN 2 first.

| ID | Steps | Expected |
|---|---|---|
| **E1** | More → **Backup Export** → **Set up the Backup Recovery Key** → enter Test PIN 2 | A key starting `BK-` is shown once. **Do H2 now.** Write the key on the sheet, then confirm it the same way as the recovery code. The screen then shows **"Backup Recovery Key ID: XXXX-XXXX"**; write the ID down (it is not secret). |
| **E1b** | Tap **Replace the Backup Recovery Key**, but enter a **wrong** PIN | Refused; nothing changes (the Key ID stays the same). |
| **E2** | **Create encrypted backup** → Create backup → enter Test PIN 2 → Android's save screen opens → choose **Downloads** → **Save** | Message: "Backup saved…". |
| **E2b** | Create encrypted backup again, but enter a **wrong** PIN | Refused ("Incorrect PIN."); no save screen opens. |
| **E3** | Open the **Files** app → Downloads | A file named like `rbsk-recovery-20260924-101500.rbskrp` is there. |
| **E4** | Repeat E2, but press **Back/Cancel** on the save screen | Message: "Backup not saved (cancelled)." The app still works. |
| **E5** (optional, with the computer) | Copy the `.rbskrp` file by USB cable to a folder on the computer **outside** the project, e.g. `C:\RBSK-device-test\`. Tell the developer the path. | The developer checks that the file does not contain the database in readable form and does not contain "Test Admin 001". |
| **E6** | — | Tell us where you would normally keep backups (e.g. USB stick, a PC folder). This is a planning answer only; **do not upload anywhere now.** |

- **Report:** PASS/FAIL for each, the file name and size from E3, and the
  Key ID.
- **Screenshot?** No on the BK key screen; optional elsewhere.
- **Changes data?** Creates the backup key and backup files.

---

## Group F: Restoring on a second phone

**Only if you have a second phone.** If you don't, mark F1–F9 as
**NOT RUN (one phone)** and see **F-single** below.

**Moving the file.** Copy the `.rbskrp` file from phone 1 to the computer
and then to phone 2's Download folder, **by USB cable only**.

| ID | Steps | Expected |
|---|---|---|
| **F1** | Install the same `app-release.apk` on phone 2. | Installs. |
| **F2** | Open it. | "Set up Administrator" screen. **Do not create an Admin.** |
| **F3** | Tap **"Replacing a phone? Restore from a recovery package"** → **Choose backup file** → pick the `.rbskrp` file. | The screen shows "Backup made on: <date>" and the same **Backup key ID** as on phone 1. **Do H4 now.** |
| **F4** | Type the **Backup Recovery Key** (BK-…) → **Check backup**. | "The backup is genuine and complete…". |
| **F5** | Tick "I understand…" → **Restore now**. | The screen changes to "Set a new PIN for an Admin…". |
| **F6** | — | No error; no "data locked" message. |
| **F7** | Tap **Test Admin 001**. The BK key is already filled in. Type a new test PIN in both boxes → **Set Admin PIN**. | A new `AR-…` code is shown once. Confirm it; Home opens. |
| **F8** | Log out. | The login screen lists **Test Admin 001** (this name came from phone 1's backup). More → Backup Export shows the **same Key ID** as phone 1. |
| **F9** | On phone 1, open Files → Downloads. | The backup file is still there, with the same size. Phone 1's app still logs in with Test PIN 2. |

- **Report:** PASS/FAIL for each.
- **Screenshot?** Optional on F2, F3 (date/ID), F6 and F8; not on key
  screens.
- **Changes data?** Creates data on phone 2 only.

**F-single (one phone only).** Only after finishing Groups A–E, H and
K on phone 1:

1. Make sure the backup file is in **Downloads** (E3).
2. Do **I3** (uninstall and reinstall).
3. Then run F2–F8 on the same phone.

Report it as **"same-phone restore"**; it is not a cross-device test.

---

## Group G: Things that must fail safely

Run G1–G3 on the **fresh** phone (phone 2 at F2, or phone 1 after I3),
**before** doing the real restore.

| ID | Steps | Expected |
|---|---|---|
| **G1a** | At F4, type the BK key with **one character changed**. | "There is a typing mistake in the key…". Rarely (about 1 time in 32) you may instead see "…made with a different Backup Recovery Key…"; both are a PASS. Nothing changes. |
| **G1b** | At F4, type the **AR** code instead of the BK key. | "This looks like the Admin Recovery Code…". |
| **G2** | At F3, pick a file that is **not** a backup (e.g. a photo or PDF). | "This file is not an RBSK recovery package…". |
| **G3** | Go through F3 and F4, then at the "Restore now" screen press **Back** instead. | The setup screen returns. Nothing was restored (no Admin exists). |
| **G4** | On **phone 1** (already set up): look on the login screen and the More screen for any "Restore" option. | There is **none**. Restore is only offered on a fresh phone or when data is locked. |
| **G5** | On phone 1: restart the whole phone (power → Restart), then open the app. | It opens normally; Test Admin 001 is still there. |
| **G6** 🔸 SPARE PHONE ONLY, optional | On a fresh phone: go through F3 and F4, tap **Restore now**, and **immediately** hold the power button to force a restart (or use Settings → Apps → RBSK Referred Line → **Force stop** right after tapping). Then open the app. | Either the setup screen (the restore was undone) or the Admin-PIN step / login with Test Admin 001 (the restore finished). **Never** "Your data is locked" and never a crash. Report which one you saw. |

- **Report:** PASS/FAIL, and the exact message text.
- **Changes data?** G5: no. G6: yes (spare phone only).

---

## Group H: Screen, clipboard and keyboard protection

Do these at the moments mentioned in the earlier groups.

| ID | Where | Steps | Expected |
|---|---|---|---|
| **H1** | A2: "Keep this code safe" (the AR code) | Take a screenshot (power + volume down) | Blocked: a message like "Can't take screenshot…", or the saved picture is black. |
| **H2** | E1: the BK key screen | Screenshot | Blocked. |
| **H3** | D1: the Forgot PIN screen | Screenshot | Blocked. |
| **H4** | F3/F4: the restore key screen, and the F7 Admin-PIN step | Screenshot | Blocked. |
| **H5** | Any of the above | Start the phone's screen recorder (if it has one), then open the screen | The recording shows black for that screen. |
| **H6** | D1: in the code box, type "ABCD" | Long-press the text | The menu shows **no "Copy" and no "Cut"**. "Paste" and "Select all" may appear. |
| **H7** | D1 or F4: type in the code box | Watch the keyboard | No word suggestions. On Gboard, a small **incognito** icon may show. Afterwards, in a normal app (e.g. Notes), the code is **not** suggested. |
| **H8** | On a code screen | Open the recent-apps view | The app's preview is blank or hidden. |
| **H9** | After leaving the code screens (on Home) | Screenshot | Works normally (protection is only on secret screens). |

- **Report:** PASS/FAIL for each, and your keyboard's name (e.g. Gboard,
  Samsung Keyboard).
- **Screenshot?** Not applicable: you are testing the blocking itself.
- **Changes data?** No.

---

## Group I: Android backup (the app's data must not be copied by Android)

| ID | Steps | Expected |
|---|---|---|
| **I1** | Settings → **Google** → **Backup** (on some phones: Settings → System → Backup). Look at the list of apps included. **Only look; do not press "Back up now" unless this is a spare phone.** | RBSK Referred Line is not listed with backed-up data. Report exactly what you see; wording varies by phone. |
| **I2** 🔸 SPARE PHONES ONLY, optional | If you have two spare phones and a clone tool (Samsung Smart Switch, Xiaomi Mi Mover, Vivo EasyShare, Oppo Clone Phone, Google's "copy apps & data"), clone phone 1 to the other phone. | On the new phone, RBSK Referred Line either isn't copied, or opens at "Set up Administrator" with **no** Test Admin 001. |
| **I3** | Settings → Apps → RBSK Referred Line → **Uninstall**. Then install `app-release.apk` again and open it. | "Set up Administrator" appears: nothing came back automatically. Your backup file in Downloads is still there. |

- **Report:** PASS/FAIL, the tool name used in I2, and exactly what I1
  showed.
- **Changes data?** I3 deletes the app's test data, by design.

---

## Group J: Data-lock safety

| ID | Result |
|---|---|
| **J1** | **Not tested on the phone.** There is no safe way to break the encryption key with normal phone actions. This is covered by automated tests only. |
| **J2** 🔸 SPARE PHONE ONLY, optional | Change the phone's screen lock type (for example PIN → pattern → back to PIN), then open the app. **Expected:** it opens normally, or shows "Your data is locked … NOT been deleted". It must **never** show an empty "Set up Administrator" screen as if the data vanished. |

---

## Group K: Session and auto-lock

| ID | Steps | Expected / what we record |
|---|---|---|
| **K1** | Log in, stay on Home, lock the phone, and wait **10 minutes**. Unlock and look at the app. | It is still logged in (no PIN asked). The app has **no automatic lock after inactivity yet**. This is a known missing feature, recorded as a production blocker, not a test failure. |
| **K2** | More → Log out. | The login screen appears; a PIN is needed again. |

---

## Suggested order (one phone)

1. **Setup and login:** A1 → A2 (+H1) → A3 → B1–B6 → C1.
2. **Recovery code:** D1 (+H3, H6, H7, H8) → D2–D5.
3. **Backup:** E1 (+H2) → E1b → E2 (+C2) → E2b → E3 → E4 → D6 → E5 → E6.
4. **Other checks on phone 1:** G4 → G5 → H9 → K1 → K2 → I1.
5. **Fresh-phone tests:** I3 → G2 → G1a/G1b (+H4) → G3 → F-single → (J2, G6 only on a spare phone).

**With a second phone:** do F1–F9 and G1–G3 there instead, and keep
phone 1 as it is.

**Finished?** Send all your result lines, then tear up the paper sheet.
