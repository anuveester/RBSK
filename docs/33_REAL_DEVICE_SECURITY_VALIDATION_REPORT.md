# Real-Device Security Validation Report: Phase 1.4

> **STATUS: IN PROGRESS — Group A run on one physical phone (2026-09-24).
> Groups B–K NOT RUN.** This report is filled in only from tests actually
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

3 (A1, A2, A3), phone 1 only.

## 7. FAIL count

0. (The discarded first attempt is described in §5.0; it was a harness
fault, and the clean re-run passed.)

## 8. NOT RUN count

Everything except Group A: B, C, D, E, F, G, H (except the A2
screenshot check), I, J, K.

## 9. KDF timing

**NOT RUN.** Current setting (unchanged): PBKDF2-HMAC-SHA256, 210,000
iterations, 16-byte salt, 32-byte key, computed off the UI thread (a
background isolate).

| Phone | 5 login times (tap → Home) | Median | UI responsive? |
|---|---|---|---|
| — | — | — | — |

No figure for any other iteration count (e.g. 600,000) will be inferred
from these results.

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
