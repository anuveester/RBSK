# Real-Device Security Validation Report: Phase 1.4

> **STATUS: IN PROGRESS — Groups A, B and C run on one physical phone
> (2026-09-24). Groups D–K NOT RUN.** This report is filled in only from tests actually
> performed on a real Android phone (driven over ADB, with the tester
> holding the phone). Nothing here is marked PASS on the basis of
> automated tests or assumption.
>
> Phase 1.4 remains **OPEN**. Phase 1.5 has **NOT started**.

**Evidence labels used in this report:**

| Label | Meaning |
|---|---|
| **AUTOMATED VERIFIED** | Covered by the automated suite on a development machine (321/321 at `07e6807`). **Not** device evidence. |
| **REAL DEVICE VERIFIED** | Performed on a physical phone and reported by the tester. |
| **NOT VERIFIED** | Neither of the above. |

The operator guide is [34_REAL_DEVICE_TEST_OPERATOR_GUIDE.md](34_REAL_DEVICE_TEST_OPERATOR_GUIDE.md).
The underlying checklist is [32_REAL_DEVICE_SECURITY_TEST_CHECKLIST.md](32_REAL_DEVICE_SECURITY_TEST_CHECKLIST.md).

---

## 1. Device details

Phone 1 details were read over ADB (`getprop`, `df`). Whether a second phone is available has not been stated. Requested fields:

- manufacturer;
- model;
- Android version;
- free storage;
- Developer options available (not required);
- spare phone or phone with personal data;
- second phone available.

Not requested, and must not be recorded here: IMEI, serial number,
account passwords, phone unlock PIN.

| Field | Phone 1 | Phone 2 |
|---|---|---|
| Manufacturer / model | Nothing, model `A059` (from `ro.product.*`) | — |
| Android version | 16 (SDK 36), security patch 2026-08-01, build `B4.1-260810-1153`, arm64-v8a | — |
| Free storage | 101 GB free of 225 GB | — |
| Keyboard | Gboard | — |
| Spare or personal | Not stated; treated as **personal** (other apps present), so no spare-only tests | — |
| Connection | USB, USB debugging ON, already authorized | — |

## 2. Android version

Android 16 (SDK 36); see §1.

## 3. APK version / build

| | |
|---|---|
| **File to install** | `build/app/outputs/flutter-apk/app-release.apk` (universal: arm64-v8a, armeabi-v7a, x86_64) |
| Size | 60,220,304 bytes (57.4 MB) |
| SHA-256 | `3028164940161dcadea196ac9cdc4b252faf3909d22f87826ef7d7909af87565` |
| Source commit | `07e6807`, clean working tree |
| Build command | `flutter build apk --release` |
| Package / applicationId | `com.rbsk.referredline` |
| Version | `1.0.0`, versionCode `1` |
| minSdk / targetSdk / compileSdk | 26 / 36 / 36 |
| Signing | **Android debug certificate** (`CN=Android Debug`), from the Flutter template's `signingConfig = debug` (see §17) |
| Debuggable | No (release build) |
| Permissions | None requested beyond the AndroidX-internal `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. **No INTERNET, no storage permission.** |
| Backup settings (checked in the APK itself with `aapt2`) | `allowBackup=false`, `fullBackupContent=false`, `dataExtractionRules` excludes all 9 domains from `cloud-backup` and `device-transfer` |
| Cipher library | `libsqlite3mc.so` present for all three ABIs |
| Launcher icon | Flutter template default (never customised) |

**Why the release APK, not the debug APK.** The debug APK (220 MB) runs
Dart unoptimised (JIT) code. Its login timing would overstate the real
KDF cost, so it is unsuitable for the benchmark (C1). The release APK is
what users would run. Per-ABI release APKs (arm64 19.7 MB, armeabi-v7a
17.3 MB) were also built. The universal APK was chosen so the tester does
not need to know the phone's CPU type.

## 4. Test date

2026-09-24 (Group A). Preparation: 2026-09-24.

## 5. Tests executed

### 5.0 Group A (phone 1), REAL DEVICE VERIFIED

The app was installed with `adb install` and driven with `adb shell input`
and `uiautomator`. Screen dumps were streamed to the host, never stored on
the phone, and recovery codes were masked before any output. The tester
unlocked the phone, read and wrote down the Recovery Code on paper, and
did the physical screenshot check.

**Harness incident (first attempt, discarded).** In the first run, the
synthetic test-PIN file on the host had Windows CRLF line endings, so a
hidden carriage return was typed after each PIN. In that run the
"mismatched PIN" step created the Admin instead of being refused. The
cause was **not** proven at the time, so the run was stopped and reported.
On instruction, the app was **uninstalled and reinstalled clean**, and the
harness was changed to type only strings matching `^[0-9]{6}$`, with the
field contents checked before each Create. In the clean run the mismatch
**was refused** (below). The anomaly is therefore attributed to the
harness. No app code was changed.

| Test | Result | Observed |
|---|---|---|
| **A1** Fresh install | **PASS** | Clean reinstall after `adb uninstall`. APK SHA-256 matches §3. `Success`, versionName 1.0.0 / versionCode 1, minSdk 26 / targetSdk 36. Package flags `[HAS_CODE, ALLOW_CLEAR_USER_DATA]`: **no `ALLOW_BACKUP`, not debuggable** (platform backup off, confirmed on device). Launches with no crash (crash buffer and `E/flutter` empty). App info shows **"RBSK Referred Line"** with the Flutter default icon. First screen: **"Set up Administrator"**. |
| **A2** First Admin setup | **PASS** | Name "Test Admin 001". **5-digit PIN** in both fields → "PIN must be exactly 6 digits.", PIN fields cleared. **Mismatched 6-digit PINs** (6 dots in each field, confirmed by screenshot before Create) → **"The two PINs do not match."**; still on setup, **no Admin created**. Matching 6-digit PINs → "Keep this code safe" with the AR code (masked in all output). **FLAG_SECURE:** the `adb screencap` of the code screen was 99.95% black, and the tester's **physical screenshot (Power + Volume-down) was blocked**. **Continue:** disabled initially; still disabled after only the tick; still disabled with a wrong last group; **enabled only with the correct last 3 characters** → Home (5 tabs). The tester wrote the code on paper; it was never sent in chat. After leaving the code screen, a capture of Home was normal (0.2% black): protection is released. |
| **A3** Restart / session restore | **PASS** | `am force-stop` (process ended), then relaunch (new PID) → **opened directly to Home**. No "data locked" error, so the encrypted database opened with the stored key. More shows no "Recovery Code needs attention" warning (the confirmation persisted). **More → Log out** → login screen lists **Test Admin 001**, "Log in" is disabled until a PIN is entered, and there is no restore banner. No crash at any point. |

**Observation (not a defect of this build; recorded for the risk
register).** `uiautomator` could read the Recovery Code text through
Android's **accessibility** tree while FLAG_SECURE was blocking screen
capture. This is standard Android behaviour: FLAG_SECURE does not hide
content from accessibility services. The harness masked it. Implication:
a malicious app granted accessibility permission could read codes on
screen. This is not verified further, and nothing was changed.

### 5.0b Group B (phone 1), REAL DEVICE VERIFIED

Same phone, app and setup as Group A. Each attempt used the **Test Admin
001** entry on the login screen. Before every tap on "Log in", the harness
checked that the PIN field held exactly 6 characters. The wrong PIN was
derived from Test PIN 1 inside the shell (a different last digit); no PIN
was printed.

Harness note: the first B1 run aborted **before** "Log in" was tapped,
because the field check itself failed (a helper quoting bug). No login
attempt was made. The helper was fixed and B1 re-run.

| Test | Result | Observed |
|---|---|---|
| **B1** Correct PIN | **PASS** | Home opened (5 tabs); More → Log out → login screen. |
| **B2** One wrong PIN | **PASS** | "Incorrect PIN."; stayed on the login screen. |
| **B3** Five wrong attempts | **PASS** | Attempts 2–5 each showed "Incorrect PIN." (5 in total, B2 included). As designed (docs/33 P8), the 5th still shows "Incorrect PIN.". |
| **B4** Lockout | **PASS** | Right after the 5th wrong attempt, the **correct** PIN was refused: **"Too many incorrect attempts. Try again in 41 seconds."** It answered in about 6 s versus about 12 s for a PIN check, consistent with the lockout being checked before PIN verification. The remaining time is consistent with a 60 s lockout from the 5th failure. |
| **B5** Lockout expiry | **PASS** | Waited until 70 s after the 5th wrong attempt. The device clock was **not** changed. The screen was kept awake with taps on the non-interactive title. The old lockout text stays on screen until the next attempt (display only). |
| **B6** Correct PIN after lockout | **PASS** | Home opened. |

- **Crashes:** none (crash buffer and `FATAL` / `E/flutter` empty).
- **Timing caveat:** the "about 11.5–12.9 s" per attempt is the
  **harness's** time from tap to detection. It includes `uiautomator`
  dumps of about 2 s each and is **not** a KDF measurement (that is
  Group C).
- **End state:** logged in, on Home.

### 5.0c Group C (phone 1), REAL DEVICE VERIFIED

| Test | Result | Summary |
|---|---|---|
| **C1** Login timing | **PASS** (accepted by the project owner) | **5.038–5.068 s, median 5.049 s**, from tap to Home. The UI stayed responsive: no frame gap above 16.6 ms. Detail in §9. |
| **C2** PIN-confirmation timing | **NOT RUN** (intentional) | Measured as part of E2, as the operator guide specifies. |

### 5.1 Pre-test inspection findings: checklist vs. implementation

These were found while preparing. None is a security defect in the
tested flows. They change **how** some tests can be done.

| # | Finding | Effect on testing |
|---|---|---|
| P1 | **The app has no data-entry screens yet.** Home, Visits, Referrals and Reports are placeholders; Audit Log is "not available yet". The requested "Test School / Test Child 001 / Test Disease" **cannot be entered** through the UI. | "Existing data is preserved" can only be checked through what the UI shows: the Admin's name (**Test Admin 001**) on the login screen, the recovery-code status on More, and the Backup Key ID. The seeded reference data is not visible. **Deeper data checks remain AUTOMATED VERIFIED only.** |
| P2 | Roles: there is **no user-management screen**, so only the Admin exists on a device. | Role-separation tests (docs/32 I) are **NOT APPLICABLE on device** until user management exists. Covered by automated tests. |
| P3 | docs/32 items that inspect app-private files (R, U, parts of K, Q, V) need `adb run-as`, which works only on a **debuggable** build. The release APK is not debuggable, and the tester is not a developer. | Those inspections are **NOT RUN** on device. The UI-visible outcome of each (e.g. G6 after a forced restart) is still tested. |
| P4 | No in-app timing diagnostics exist. | KDF timing (C1) is by stopwatch: approximate, and it includes the screen transition. No code was added for measurement. |
| P5 | "Import over an existing active database is refused" (user's G4): on a set-up phone the UI **never offers** restore. The service-level refusal (`DatabaseInUseException`) cannot be reached through the UI. | G4 on device checks that the option is **not offered**. The service refusal itself is **AUTOMATED VERIFIED** only. |
| P6 | A "tampered package" test needs a byte editor, which a non-developer cannot use. | G2 on device uses a **non-package file** (photo or PDF). True byte-level tampering is **AUTOMATED VERIFIED** only (every region of the file). E5 (plaintext check) can be done by the developer on a copy the tester places on the computer. |
| P7 | "Database encryption key unchanged after PIN reset" (user's D) is not visible in the UI. | On device, the check is that the data is still there after the reset. The key itself being unchanged is **AUTOMATED VERIFIED** only. |
| P8 | Lockout detail: the **5th** wrong PIN still shows "Incorrect PIN."; the lockout message appears on the **next** attempt (60 s, fixed; not extended by more tries; a successful login resets the count). | The guide's B3/B4 are written accordingly. |
| P9 | A stale code comment in `login_lockout_tracker.dart` still says there is "no separate forgot PIN recovery flow in this phase". This is **untrue since `f27d85b`**. | Documentation drift only; behaviour is unaffected. **Not changed**: no code edits during validation preparation. |
| P10 | **The release APK is signed with the Android debug key.** Not tracked anywhere as a blocker until now. | Fine for testing. **Production blocker** (§17). Note: moving the test phones to a properly signed build later will need an **uninstall**, which erases the test data (there is no platform backup, by design). |
| P11 | The launcher icon is the Flutter default. | A1 expects the Flutter logo. Branding item, not security. |

## 6. PASS count

10 (A1–A3, B1–B6, C1), phone 1 only. C1 is a completed measurement,
not a threshold pass.

## 7. FAIL count

0. (The discarded first attempt is described in §5.0; it was a harness
fault, and the clean re-run passed.)

## 8. NOT RUN count

C2 (deferred to E2), plus Groups D, E, F, G, H (except the A2 screenshot
check), I, J and K.

## 9. KDF timing

**Setting under test (unchanged during and after the test):**

- PBKDF2-HMAC-SHA256, **210,000** iterations, 16-byte salt, 32-byte key;
- computed with `pointycastle` in a background isolate
  (`verifyCredentialInBackground`);
- the release APK from §3.

No source code or security parameter was changed.

### 9.1 Method

The measurement follows the guide's C1 definition: from tapping
**Log in** until **Home** appears. It uses the phone's own clock instead of
a stopwatch:

- **Tap time:** `EventTime` of the `TYPE_VIEW_CLICKED` accessibility event
  on "Log in" (`adb shell uiautomator events`, device uptime ms).
- **Home time:** `EventTime` of the first `TYPE_WINDOW_STATE_CHANGED`
  event whose text is "Home" (the new route's first semantics update).
- **UI responsiveness:** frame presentation timestamps of the app's
  Flutter SurfaceView layer (`dumpsys SurfaceFlinger --latency`, polled
  about every 0.5 s, merged). The gaps between frames between the tap and
  Home were examined.

Each run went as follows:

1. log out;
2. select Test Admin 001 and type Test PIN 1 (only a validated 6-digit
   string; never printed);
3. hide the keyboard;
4. start capture, tap Log in, wait for Home.

One **trial run** (tool validation, not counted) measured 5,119 ms.

**Conditions:**

- Nothing A059, Snapdragon SM7635, Android 16;
- display at 60 Hz (16.67 ms refresh period reported by SurfaceFlinger);
- screen on, **charging (AC)**, battery 70% → 72%, battery temperature
  37.0 → 36.0 °C, thermal status 1 (light) before and after;
- an accessibility client (`uiautomator`) was connected during each
  measurement;
- no stay-awake setting was used, and nothing touched the screen during a
  measurement.

### 9.2 Raw evidence

| Run | Tap `EventTime` (ms) | Home `EventTime` (ms) | Tap → Home (ms) | Frames in window | Largest frame gap | Gaps > 50 ms / > 100 ms | First frame after tap |
|---|---|---|---|---|---|---|---|
| 1 | 182373026 | 182378066 | **5040** | 301 | 16.6 ms | 0 / 0 | 57 ms |
| 2 | 182407395 | 182412433 | **5038** | 301 | 16.6 ms | 0 / 0 | 53 ms |
| 3 | 182441632 | 182446681 | **5049** | 301 | 16.6 ms | 0 / 0 | 64 ms |
| 4 | 182475778 | 182480845 | **5067** | 303 | 16.6 ms | 0 / 0 | 50 ms |
| 5 | 182510108 | 182515176 | **5068** | 303 | 16.6 ms | 0 / 0 | 52 ms |

**Summary:** N = 5; min 5,038 ms; **median 5,049 ms**; mean 5,052 ms;
max 5,068 ms; population SD 13 ms.

Raw capture files are kept outside the repository (they contain no PIN;
checked: no 6-digit sequence).

### 9.3 Interpretation (documented; **no decision taken**)

**Measured facts:**

- On this phone, a successful login takes about **5.05 s** from tap to
  Home, with a tight spread (±15 ms).
- The UI **stays fully responsive** throughout. Frames are presented every
  16.6 ms (the display rate) during the whole wait, with no gap above one
  frame, and the first frame after the tap arrives within 50–64 ms. There
  is no visible freeze.

**Not isolated:** the 5.05 s includes more than the KDF:

- one PBKDF2 verification, including isolate start-up;
- about 4 secure-storage (Android Keystore) operations;
- one database write (last login);
- the navigation to Home.

How much of the total is the KDF alone was **not measured**. Measuring it
would need instrumented code, which was not added.

**Implications, for review:**

- About 5 s per login is long for repeated field use. The same cost
  applies to every PIN re-check (export, replacing codes; see C2) and to
  the recovery-code check.
- Slower (low-end) phones were **not** measured, and nothing is inferred
  for them. **Nothing is inferred for 600,000 iterations.**
- **Owner decision (2026-09-24):** the C1 result is accepted.
  - The PBKDF2 setting stays at **210,000** and is **not** increased on
    the basis of this result.
  - **No KDF-only timing is inferred** from the 5.05 s login
    measurement.
  - Group D waits for approval.

## 10. Recovery results (Group D)

NOT RUN. Automated coverage: `admin_recovery_test.dart`,
`service_authorization_test.dart` (AUTOMATED VERIFIED).

## 11. Backup export results (Group E)

NOT RUN.

## 12. Backup import results (Group F)

NOT RUN. If only one phone is available, cross-device F1–F9 will be
recorded as **NOT RUN (one phone)**. A same-phone restore after reinstall
will be reported separately as "same-device restore".

## 13. Failure-case results (Group G)

NOT RUN. G6 (forced restart during restore) is optional, **spare phone
with synthetic data only**. Crash safety is AUTOMATED VERIFIED
(`restore_atomicity_test.dart`).

## 14. Screenshot / clipboard / keyboard results (Group H)

NOT RUN. Whether the keyboard honours no-learning / incognito, and what
the recent-apps preview shows, depend on the keyboard and OEM. They must
be recorded per phone and keyboard.

## 15. Android backup observations (Group I)

NOT RUN. The APK configuration is verified (§3). OEM clone-tool behaviour
will be recorded **per manufacturer and tool only**, never generalised.

### Database-key fail-safe (Group J)

- **J1: NOT TESTED ON DEVICE.** There is no safe UI method to make the key
  unavailable. All fail-safe cases are **AUTOMATED VERIFIED**
  (`database_key_fail_safe_test.dart`, `restore_atomicity_test.dart`).
- **J2** (change the screen-lock type, spare phone only) is optional.

### Session / auto-lock (Group K)

**Current behaviour (from the code):** the session persists until
logout; there is **no inactivity auto-lock**.

**Record: NOT IMPLEMENTED — PRODUCTION BLOCKER.** K1 on device will only
confirm the observed behaviour.

## 16. Known limitations

- docs/31 §15 still applies.
- Plus P1–P7 above: what a non-developer can observe on a device in
  Phase 1.4 is limited.
- Timing is by stopwatch.

## 17. Production blockers

Already tracked:

- docs/32 run on real phones, then the KDF iteration decision;
- custody of the two recovery secrets;
- package storage / residency policy;
- **inactivity auto-lock (not implemented)**;
- user management.

**New from this preparation:** a **release signing key and signing
configuration**. The release build is currently signed with the Android
debug key (P10). Custody of the signing key is also a policy question.

## 18. Recommended next step

1. The tester sends the §1 device details.
2. The tester installs `app-release.apk` (SHA-256 above) and runs the
   guide's groups in the suggested order, reporting one line per test.
3. On any security-significant FAIL: **stop**, and report the exact test,
   the observed and expected behaviour, and whether data was affected.
   Nothing will be patched without instruction.
4. After the results come in, this report is updated with REAL DEVICE
   VERIFIED results only.
