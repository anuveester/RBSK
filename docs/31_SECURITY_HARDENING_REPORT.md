# Security Hardening — Implementation Report

> **HISTORICAL — PARTLY REMOVED (2026-09-24).** The Phase 1.4 authentication implementation was intentionally removed. Authentication will be redesigned and implemented from scratch after the complete functional application is finished.
> **Removed (authentication):**
> - login, PIN, KDF, lockout and sessions;
> - the Admin Recovery Code;
> - Admin-PIN checks and role gating;
> - "set Admin PIN after restore";
> - authentication audit events.
>
> **Restored as independent infrastructure, with no user interface yet:**
> - the Encrypted Recovery Package and the Backup Recovery Key;
> - export, verified import and the crash-safe restore transaction;
> - start-up recovery;
> - the audit writer.
>
> The old restore refusal rule ("user accounts exist") is replaced by the
> 17-table business-data rule (docs/00 §7). Current status:
> [00_PROJECT_MASTER_PLAN.md](00_PROJECT_MASTER_PLAN.md) §0.

**Status: IMPLEMENTED, then corrected by the final security review (§20),
awaiting your review. Phase 1.4 remains NOT CLOSED. Phase 1.5 NOT
STARTED.**

> **Read §20 first.** The final security review found and fixed genuine
> gaps: service-layer authorization, a restore that was not crash-safe, a
> staging write that could hang, audit replay duplicates, and screenshot and
> clipboard exposure. Statements in §§2–19 that the review changed are
> marked *(superseded, §20)*.

| | |
|---|---|
| Date | 2026-09-24 |
| Decisions | docs/30 (analysis) + your approval: recovery code, recovery package, controlled encrypted backup, KDF 210,000 for now, fix the DB-key failure first |
| Code commit | `f27d85b` |
| Schema | Unchanged: `schemaVersion` 1, 28 tables, no migration |
| Dependencies | None added (`pubspec.yaml` / `pubspec.lock` unchanged) |
| Real device | **Not available — nothing here was verified on a phone** |

## 1. What was inspected

- **Docs:** 00, 04 (§2.11 audit, §3 RBAC, §6 backup), 08, 27, 28, 29, 30.
- **Code:** `credential_hasher`, `login_lockout_tracker`,
  `local_auth_repository`, `auth_providers`, `database_connection`
  (`SecureKeyStore`, `DatabaseKeyManager`), `database_provider`,
  `AppDatabase`, the `audit_log` table, the `Users` table and repository,
  `AndroidManifest.xml`, `MainActivity.kt`, `pubspec.yaml`, and all tests.
- **Library sources:** `flutter_secure_storage` 11.2.0 (`resetOnError`,
  `storageNamespace`, what happens when decryption fails) and
  `pointycastle` 4.0.0 (AES-GCM, HKDF, PBKDF2).
- **Android documentation:** `data-extraction-rules` domain names and the
  semantics of each backup mode.
- **Existing export or backup code:** none (docs/04 §6 only anticipated
  it).

## 2. What was changed

**New `lib/` modules:**
- `core/security/crypto_utils.dart`: secure random bytes, constant-time
  compare, hex.
- `core/security/secret_code.dart`: 128-bit recovery secrets, human format,
  check character.
- `core/platform/recovery_file_gateway.dart`: Android document picker and
  `FLAG_SECURE`.
- `data/local/auth/admin_recovery_code_store.dart`
- `data/local/recovery/recovery_package.dart`: format and crypto.
- `data/local/recovery/backup_key_store.dart`
- `data/local/recovery/database_recovery_service.dart`: export and import.
- `data/local/security/security_audit.dart`: `audit_log` writer and
  pending journal.
- `data/local/security/security_providers.dart`
- `domain/entities/auth_recovery.dart`
- `features/auth/presentation/screens/pin_recovery_screen.dart`
- `features/auth/presentation/widgets/recovery_code_display.dart`
- `features/auth/presentation/widgets/pin_confirm_dialog.dart`
- `features/recovery/`: restore, backup, recovery-code screens, and plain
  messages.

**Modified `lib/`:**
- `database_connection.dart`: the fail-safe.
- `database_provider.dart`: journal on failure, flush on open, idempotent
  close.
- `credential_hasher.dart`: KDF policy and versioning; corrected Argon2
  rationale.
- `local_auth_repository.dart` and `auth_repository.dart`: recovery,
  re-hash, audit.
- `auth_controller.dart` and `auth_providers.dart`
- Setup, login, splash and More screens.
- Routes, guard and router.
- RBAC read model.
- `failure.dart`: plain-language failures.

**Android:**
- `AndroidManifest.xml`: backup disabled.
- `res/xml/data_extraction_rules.xml`: new.
- `MainActivity.kt`: Storage Access Framework channel and `FLAG_SECURE`.

**Existing tests changed (for transparency):**
- `database_connection_test.dart` (Phase 1.2): the API moved from
  `getOrCreateKey()` to `resolveKey(databaseFileExists:)`. The original
  assertions are kept.
  - The wrong-key test used to open a file with an *empty* key store and
    expect the first query to fail. That scenario must now fail earlier and
    explicitly, so the test gives the manager a *different* key and expects
    `keyDoesNotOpenDatabase`.
  - It additionally proves the raw file is not plaintext SQLite, that the
    file is unchanged, and that no key was replaced. The empty-store case
    moved to the new fail-safe test B.
- `local_auth_repository_test.dart`: setup now returns
  `RecoveryCodeIssued`. It also now asserts that the recovery code is never
  stored.
- `more_menu_items_test.dart`: the Admin menu gained "Admin Recovery Code".
- `auth_flow_test.dart`: first-run setup now shows the recovery code before
  Home.
- `auth_redirect_test.dart`: gained route-guard tests.

No assertion was weakened or removed.

## 3. Database-key fail-safe

| Situation | Behavior |
|---|---|
| No database file, no key (first install) | Generate a 256-bit key, write it, **read it back**, then create the database. If the key can't be saved, stop; no database is created with an unsaved key. |
| Database exists, key present and correct | Open normally. |
| Database exists, **key missing** | `DatabaseKeyUnavailableException(keyMissingForExistingDatabase)`. **No key generated, nothing deleted or changed.** |
| Database exists, **secure storage unreadable** | `…(secureStorageUnreadable)`. **No key generated, nothing deleted.** Opens normally once storage reads again. |
| Database exists, key present but wrong | Detected by a read-only test-open *before* use: `…(keyDoesNotOpenDatabase)`. The stored key is not replaced. |
| Key replaced by a restore | The previous key is kept under `rbsk_db_encryption_key_v1.preserved.<time>`, never discarded. |

- **Storage configuration:** `resetOnError: false` on every
  `flutter_secure_storage` instance, so the library can no longer silently
  delete entries it can't decrypt. The database key lives in its own
  `storageNamespace` (`rbsk_database_key`): its own preferences files and
  its own Keystore alias. Nothing done to credentials can reach it.
- **Migration:** a key already stored in the previous location (Phase
  1.2–1.4) is copied forward, and the old copy is kept.
- **Races:** key resolution is serialized, so two overlapping first-launch
  opens agree on one key (tested).
- **What the user sees:** the splash screen says *"Your data is locked … Your
  existing data has NOT been deleted … restore from your backup file using
  the Backup Recovery Key … Do not uninstall the app or clear its data"*. It
  offers "Restore from backup" and "Try again", plus a short reference code
  (for example `keyMissingForExistingDatabase`) and no secrets. A
  `databaseKeyUnavailable` event is journaled.

## 4. Admin Recovery Code

- **Generation:** 16 bytes (128 bits) from `Random.secure()` at first-run
  Admin setup. Never a PIN, a timestamp, a UUID, or a fixed value.
- **Format:** `AR-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXX`, in Crockford Base32
  (no I/L/O/U).
- **Check character:** one character computed over (type, secret). It
  catches about 31 in 32 typing mistakes before they count as attempts, and
  recognizes the Backup Recovery Key if it is typed in the wrong place.
- **Storage:** only a PBKDF2 verifier (same format as PINs), with the
  Admin's id, in secure storage. Never the code, and never in the
  database, logs, tests, docs or the APK (all scanned).
- **Display:**
  - shown once, with plain instructions (write it on paper, keep it away
    from the phone, don't photograph or message it);
  - to continue, the Admin must tick "written down" and type the code's
    last group;
  - screenshots and screen recording are blocked (`FLAG_SECURE`) while it
    is visible.
- **Single use:** a successful reset replaces the code, and the old one
  stops working. An Admin can also replace it (More → Admin Recovery Code,
  requires the current PIN).
- **Limits:** a wrong code counts as an attempt (5, then 60 s, the existing
  lockout) and is audited. A typing mistake is not counted.
- **Independence:** it doesn't use the phone's own screen lock, and there is
  no master password. Resetting the Admin PIN needs the 128-bit code, so
  someone who merely has the phone in hand cannot do it.

## 5. PIN reset flow

**Login → "Admin forgot the PIN?"** → enter the code and a new PIN twice.
Then:
1. The new PIN is written. If this fails, nothing has changed and the code
   still works.
2. The code is used up and a new code is issued. If this fails, the PIN is
   still reset and the old code stays valid; the Admin is told to create a
   new one. No state leaves nobody able to log in.
3. The new code is shown once, then the Admin is signed in.

The database, its key and all data are not touched; tests confirm the
key-store write count is unchanged and the data is still readable. It works
fully offline.

## 6. Database-key recovery package

| Part | Protection |
|---|---|
| Database data | The SQLite file as stored, **still encrypted** with its own key. Never exported as plaintext. Export also refuses any file that starts with the plaintext SQLite header (tested). |
| Database key | In a payload encrypted with **AES-256-GCM**. |
| Recovery secret | The **Backup Recovery Key**: 128 bits, `BK-…` format, shown once, separate from the PIN and from the Admin Recovery Code. The payload key is **HKDF-SHA256(secret, per-key salt)**. The phone stores only the derived key and salt, never the secret. |
| Integrity / authenticity | GCM authenticates the header (as associated data) and the payload. The payload holds the database's SHA-256 and length; trailing bytes and truncation are rejected. Only a holder of the Backup Recovery Key can make a package that verifies. |

- **Primitives:** only `pointycastle` (AES-GCM, HKDF, SHA-256), already a
  dependency. Nothing was invented. Both primitives are pinned by
  known-answer tests: RFC 5869 for HKDF, and a vector produced by OpenSSL
  for GCM.
- **Independent cross-check:** a real package was decrypted by Python
  `cryptography` using only the documented format.
- **No file paths:** the package contains none, so no path traversal is
  possible; import always writes to the app's fixed location.
- **Snapshot consistency:** export copies the file while holding a
  database transaction, so the copy is consistent (WAL mode is refused).
- **Import:**
  1. read the summary (date and backup key ID) without the key;
  2. enter the Backup Recovery Key and verify everything: that it is the
     right key, authenticity, the database hash, that the key opens the
     database, and that the schema version is supported;
  3. **explicit confirmation** ("kept aside, not deleted");
  4. install.

  Install keeps the existing database (renamed, never deleted) and the
  existing key (preserved), moves the new database into place, then stores
  its key. *(Superseded, §20: install is now an all-or-nothing
  transaction, rolled back on failure and at the next start after a crash.
  Import is also refused, in the service itself, while the database on the
  phone is in use.)*
- **Credentials never travel in a package.** After a restore, an Admin's
  PIN is set with the Backup Recovery Key. This is allowed **only while no
  Admin can log in on that phone**, so it can't be used to take over a
  working phone. It is rate-limited, audited, and issues a new Admin
  Recovery Code.
- **Where restore is offered:** only on a phone with no accounts (first
  run) or when the database key is unavailable. It is never offered over
  working data.

## 7. Controlled encrypted backup

- **More → Backup Export** (Admin only):
  - set up the Backup Recovery Key (asks for the current PIN), shown once;
  - "Create encrypted backup" (with a confirmation);
  - Android's own "save document" picker, where the user chooses Downloads,
    a USB drive, a cloud drive app, and so on;
  - the app's temporary copy is deleted afterwards.
- **Where it is shown:** the Backup Recovery Key ID (for example
  `3F9A-12C4`) appears on the screen and in each package, so a package can
  be matched to its key.
- **Replacing the key:** needs the PIN; older backups still need the old
  key, and the user is warned.
- **File access:** the Storage Access Framework, with no storage permission
  and no cloud provider assumed. Implemented as a small platform channel in
  `MainActivity.kt` rather than a new plugin: no new dependency, but also
  **not exercised on a device** (§15).

## 8. Android backup configuration

Verified in the merged APK manifest:
- **`android:allowBackup="false"`:** cloud backup and adb backup, all API
  levels.
- **`android:fullBackupContent="false"`**
- **`android:dataExtractionRules="@xml/data_extraction_rules"`:** Android
  12+. It excludes **every** app-private domain (`root`, `file`,
  `database`, `sharedpref`, `external`, and the four `device_*` domains)
  from **both** `<cloud-backup>` and `<device-transfer>`. On some devices
  `allowBackup="false"` alone does not stop device-to-device transfer, and a
  mode with no section would be fully enabled.

**Why:** a platform backup would copy the encrypted database and the
secure-storage files but never the Keystore keys, producing copies that can
never be decrypted. It would also send child health data off the phone
outside the app's control. The Encrypted Recovery Package is the intended
backup.

**Not verified on a device:** whether a particular manufacturer honours
these rules.

## 9. KDF and versioning

- **Unchanged:** PBKDF2-HMAC-SHA256, **210,000** iterations, 16-byte salt,
  32-byte key.
- **Single definition:** these values are defined once, in
  `CredentialKdfPolicy.current`.
- **Self-describing verifiers:**
  `pbkdf2-hmac-sha256$<iterations>$<salt>$<key>`.
- **Bounds:** a verifier outside 10,000–10,000,000 iterations, with a salt
  under 16 bytes, or with a key outside 32–64 bytes, fails closed.
- **Re-hash:** after a successful login, a verifier made with weaker
  parameters than the policy is re-derived. If writing it fails, **the old,
  valid verifier is kept** and login still succeeds; this is tested.
  Stronger verifiers are never downgraded.
- **Raising the count later** is a one-line change to the policy, with no
  migration.
- **Not measured:** no KDF performance was measured on a phone, and 600,000
  was not tested anywhere.

## 10. Audit

- **Where events go:** into the existing **`audit_log`** table, with no
  second audit system and no schema change. Each row has
  `table_name='security_event'`, `action=INSERT`, `record_id` set to the
  affected user (or the event's id), and `new_values` holding the event
  type, time and non-secret details.
- **Before the database opens:** events that happen then (key unavailable,
  restore attempts) go to a small pending journal in app-private storage.
  It is flushed into `audit_log` on the next successful open.
- **Events recorded:**
  - recovery code created and confirmed;
  - PIN reset succeeded and rejected;
  - PIN verifier upgraded;
  - backup key created;
  - export created and failed;
  - import attempted, succeeded and rejected;
  - database recovery attempted, succeeded and failed;
  - Admin access restored and rejected;
  - database key unavailable;
  - secure-storage failure.
- **Never recorded:** PINs, codes, keys, derived keys, salts, verifiers,
  file paths, or health data. Tests scan the audit log and the journal for
  every secret used.
- **Best effort:** auditing never blocks the security operation it records.

## 11. Security tests (new)

| Area | File | Tests |
|---|---|---|
| A–C fail-safe, wrong key, legacy key, preserved key, save-failure, race | `data/local/database_key_fail_safe_test.dart` | 11 |
| E–G, K recovery code: valid, invalid, single use, rate limit, typos, wrong kind, deactivated Admin, save failure, replacement, non-Admin, audit | `data/repositories/admin_recovery_test.dart` | 17 |
| F code format and entropy | `core/security/secret_code_test.dart` | 7 |
| H package: known-answer tests, round trip, no plaintext, every region tampered, truncation, wrong key, version | `data/local/recovery/recovery_package_test.dart` | 16 |
| H–I, K export/import end to end (two simulated phones), confirmation, tamper, plaintext refusal, key-loss recovery, Admin access after restore, no secrets in journal or audit | `data/local/recovery/database_recovery_service_test.dart` | 12 |
| J KDF versioning, re-hash, failed re-hash | `data/local/auth/kdf_versioning_test.dart` | 7 |
| UI: data-locked screen, forgot-PIN flow, wrong code, Admin-only routes by direct navigation, backup key setup, post-restore login | `features/recovery/recovery_ui_test.dart` | 8 |

The tests for the race and plaintext-export fixes, and the earlier
verification fixes, were each shown to **fail** with the fix disabled.

## 12. Full test result

**246 / 246 passed** (the test runner's own count; 165 before this work,
plus 81).

## 13. `flutter analyze`

No issues found.

## 14. APK build

- `flutter build apk --debug` succeeds; the Kotlin channel compiles.
- Package `com.rbsk.referredline`, minSdk 26, targetSdk 36.
- `libsqlite3mc.so` is still bundled.
- No storage permission was added.

## 15. Known limitations (honest list)

1. **Nothing was tested on a real phone.** Untested there:
   - the document picker save/open;
   - `FLAG_SECURE`;
   - the backup and device-transfer exclusions;
   - `resetOnError: false` behaviour on real Keystore failures;
   - the timing of any flow.
2. If Android recreates the activity while the file picker is open, the
   pending request is lost, and the screen may stay busy until the app is
   restarted.
3. The derived backup wrapping key lives on the phone (so backups can be
   made without typing the key). Someone who can run code as the app on a
   rooted phone could decrypt packages, but could already read the
   database key there.
4. ~~Authorization for export and backup-key creation is not re-checked
   inside `DatabaseRecoveryService`.~~ **Fixed (§20.1).**
5. **Rollback:** an older package can be restored on a new or locked phone.
   The confirmation shows its date, but restoring older data is not
   prevented.
6. **Accumulating copies:** preserved databases and keys build up; there is
   no clean-up tool.
7. **Audit is best effort:** if both the database and the journal writes
   fail, an event is lost.
8. **Audit mapping:** security events use `action=INSERT` under
   `table_name='security_event'`. A dedicated audit action would need a
   schema amendment.
9. If a new recovery code cannot be saved after a reset, the old code
   stays valid (chosen over the risk of lockout); the Admin is told.
10. **Lockout** still uses the wall clock. There is no overall cap, and
    moving the clock forward shortens a lockout.
11. **Non-Admin users:** after a restore, and in general, non-Admin users
    can't be given PINs until user management exists. Second-Admin reset
    (R2) isn't available yet.
12. **No inactivity re-lock.**
13. **Language:** screens are in simple English only; no Hindi
    localization.
14. **Package size:** packages are capped at 1 GiB, and large-database
    performance is untested.
15. ~~Screenshots blocked only while a secret is displayed.~~ **Fixed
    (§20.4):** code-entry screens are protected too.
16. ~~Leftover files remain after an interrupted export or import.~~
    **Fixed (§20.6):** they are removed at start-up.

## 16. Remaining production blockers (before real child-health data)

- A real-device test campaign: every flow above, backup and restore
  drills, and the KDF benchmark, followed by the latency and iteration
  decision.
- Custody: who holds the Admin Recovery Code and the Backup Recovery Key,
  where, and how they are reissued.
- Where recovery packages may be stored (data residency, docs/00 §10 #6).
- ~~Your confirmation that the two secrets are separate.~~ **Approved**
  (final security review); now also enforced by tests (§20.7).
- The inactivity re-lock decision and its implementation.
- User management (non-Admin logins, and R2).

## 17. Commits

- `f27d85b`: code and tests.
- The documentation commit that adds this report (see `git log`).

## 18. Phase 1.4

**Remains OPEN / NOT CLOSED.**

## 19. Phase 1.5

**NOT started.**

---

## 20. Final security review (Phase 1.4 hardening), 2026-09-24

A review of every privileged operation, recovery path and failure mode
before real-device validation. It kept every approved decision:

- the Admin Recovery Code;
- the local Encrypted Recovery Package;
- controlled encrypted backup;
- PBKDF2-HMAC-SHA256 at 210,000 iterations (unchanged);
- separate secrets (now approved).

It found and fixed only genuine problems, each with regression tests. Each
fix was also shown to be needed: with the fix temporarily removed, its
test **fails** (§20.9).

### 20.1 Service-layer authorization: FIXED

| Operation | Before | Now |
|---|---|---|
| Export (`DatabaseRecoveryService.createPackage`) | **No check in the service.** It took a caller-supplied `actorUserId`; only the route and UI protected it. | The service calls `AuthRepository.reauthenticateAdmin(pin)`: a stored session, re-checked against the `users` row, must belong to an **active ADMIN**, and the PIN must verify (counted by the lockout). The actor is taken from the session and cannot be passed in. The UI now asks for the PIN before export. |
| Backup Recovery Key creation (`createBackupKey`) | Same gap | Same check. |
| Replace Admin Recovery Code (`createNewRecoveryCode`) | Took a caller-supplied `adminUserId` | Bound to the session: `createNewRecoveryCode(currentPin:)`. It writes the code for the session's Admin only. |
| Confirm code written down (`confirmRecoveryCodeRecorded`) | **No check at all** | Only the logged-in, active Admin who owns the code can confirm it. |
| `confirmAdminPin(adminUserId, pin)` | Public, keyed by a caller-supplied id | **Removed.** Replaced by `requireAdminSession()` / `reauthenticateAdmin()`. |
| Import (`verify` / `install`) | Relied on the UI offering restore only on a new or locked phone | The service refuses (`DatabaseInUseException`) when the database on the phone opens with the stored key **and has accounts**, and checks again at `install`. It fails closed. |

Every refusal records `privilegedActionDenied` (operation and reason only).
These checks reuse the existing `AuthRepository` and RBAC; there is no
second auth system. A stale session is safe: a deactivated or demoted user
is refused at the service, because the role is read from the current
`users` row.

### 20.2 Restore is now atomic and crash-safe: FIXED

**Before:** install renamed the live database, moved the new one in, then
wrote the key and the backup material, with **no rollback and no crash
record**. A failure after the rename, for example a key write failing,
left the phone on the restored file with the old key: a locked phone,
while the previous data sat under a renamed file.

**Now:** `RestoreTransaction` (new) works as follows.
1. Remember the stored key and backup material in rollback slots.
2. Write a marker next to the database (phase and file name only; no
   secrets; written atomically by temp-file then rename).
3. Preserve the current database.
4. Move the restored database into place.
5. Install its key.
6. Install the backup material.
7. **Verify that the stored key opens the database in place.**
8. Commit (marker → `committed`).
9. Clean up.

If any step fails, everything is rolled back **before `install`
returns**: the previous database goes back in place, and the key and
backup material are set back (the restored key is kept aside, not
discarded). If the phone loses power, **the next start resolves it before
the database is opened** (`appDatabaseProvider`):

- an unfinished restore is undone;
- a committed one is finished.

If the rollback itself cannot complete (for example secure storage is
still failing), the marker stays and the database is **not** opened. It is
retried at the next start. A damaged marker never leads to a database file
being deleted.

The restore screen also now:

- re-creates the closed database connection after a failed install (it
  used to leave the app on a closed connection until restart);
- returns to the key step, because a verified restore is single-use.

### 20.3 Staging and export writes could hang on a full disk: FIXED

Both writes used an `IOSink`, which reports a write error only
asynchronously. When the file could not be written, the `await` **never
completed**: the test hung, and on a phone the screen would stay busy. Both
now use `RandomAccessFile`, so a write error fails immediately. A full disk
during restore is reported as `couldNotSave` ("not enough free space;
nothing changed"), instead of the misleading "damaged file". A full disk
during export is reported as a free-space message, leaves nothing behind,
and is audited.

### 20.4 Screenshots, keyboard and clipboard: FIXED

- **`FLAG_SECURE` is reference-counted** (`SecureScreen.acquire/release`).
  Before, a code display inside the restore screen switched protection
  **off** when it closed, while the screen still held the Backup Recovery
  Key. Now the "forgot PIN" screen and the whole restore screen are
  protected (the restore screen's Admin-access step, where the key is typed,
  was not protected at all before).
- Recovery-secret fields (`SecretCodeField`):
  - `enableIMEPersonalizedLearning: false` (the keyboard's incognito
    request), no suggestions, no autocorrect;
  - the long-press menu has **no Copy or Cut** (Paste is kept), so a secret
    is not put on the clipboard.

  PIN fields also turn off personalised learning. Displayed codes remain
  plain `Text` and cannot be selected.
- **Device behaviour** (whether a given keyboard honours these requests)
  is **not verified** (docs/32 B–D).

### 20.5 Audit: FIXED

- **Idempotent replay:** each event has an id, fixed when the event is
  created, which becomes the `audit_log` row id (`insertOrIgnore`). A crash
  between writing the journal's rows and clearing the journal no longer
  duplicates them on the next start. Journal lines written without an id
  get a deterministic id from their content.
- **No lost events:** journal appends and the flush are serialized, so an
  event recorded during a flush is no longer cleared unwritten.
- **Details allowlist:** only 12 known keys are kept, and each value must
  be a short plain token (no `/`, `\`, spaces; 80 characters at most). A
  path, free text or an unknown key is dropped before anything is written.

### 20.6 Leftover files: FIXED

Once per app start, before anything can be in progress, the app removes:

- the recovery work folder (package copies, snapshots);
- a stray staged database (only when no restore marker exists).

Export also removes stale exports before starting. The database file is
never touched.

### 20.7 Separate secrets: approved, now enforced by tests

Tests prove each of the following:

- the Admin Recovery Code cannot open a package (it is refused as the wrong
  kind of code);
- the Backup Recovery Key cannot reset a PIN, and isn't even counted as an
  attempt;
- the Backup Recovery Key cannot set an Admin PIN while an Admin can log in;
- the Admin Recovery Code cannot stand in for the Backup Recovery Key;
- the two secrets are stored under different names, and neither verifies
  as the other.

### 20.8 Checked and found sound (no change)

- **DB-key fail-safe:** all cases in §3, plus the new rollback. A rollback
  only ever writes back the key that was there; the restored key is kept
  aside.
- **KDF:** `210000` appears once in `lib/`
  (`CredentialKdfPolicy.current`). The iterations are unchanged.
- **Android backup:** re-checked in the merged manifest of the new APK
  (§20.10).
- **Routes:** `Routes.adminOnly` and the redirect were unchanged; the
  existing direct-navigation tests still pass.

### 20.9 Evidence

Status of each fix below:
**IMPLEMENTED** · **VERIFIED BY TESTS** · **NOT YET VERIFIED ON REAL DEVICE**

| Fix | New tests | Test fails with the fix removed |
|---|---|---|
| Service authorization (export, backup key, code replace or confirm; no session, Medical Officer, Team Member, deactivated Admin, demoted Admin, wrong PIN, lockout; actor from session) | `test/security/service_authorization_test.dart` | yes (role check removed; owner check removed) |
| Import refused over data in use (at verify **and** install); a locked phone can still be restored | same file | yes (install re-check removed) |
| Separate secrets | same file | n/a (behaviour pinned) |
| Atomic restore: failure **and** power loss before each of the 8 steps; loss after commit; repeat resolution; key and backup-material write failures; storage broken during the rollback; damaged marker; the app's real start-up provider resolving a crash | `test/data/local/recovery/restore_atomicity_test.dart` | yes (rollback skipped; start-up resolve removed: the app opened the half-restored data) |
| Full disk: restore staging and export (no hang) | atomicity and authorization files | yes (it **hung** before the fix) |
| Journal idempotency, append during flush, details allowlist | `test/data/local/security/security_audit_test.dart` | yes, each of the three |
| `FLAG_SECURE` lease | `test/core/platform/secure_screen_test.dart` | yes |
| No Copy/Cut; keyboard flags | `test/features/auth/secret_code_field_test.dart` | yes |
| Restore UI: failure message, rollback, database connection re-created | `test/features/recovery/recovery_ui_test.dart` (+1) | yes |

**Existing tests changed:** two files, for the new signatures only:

- `database_recovery_service_test` now uses the shared `Phone` fixture and
  passes the PIN;
- `admin_recovery_test` uses the session-bound replace, and its non-Admin
  case now logs in as that Medical Officer.

No assertion was weakened.

### 20.10 Results

| Check | Result |
|---|---|
| Full suite | **321 / 321 passed** (the test runner's count: 246 before, plus 75 new) |
| `flutter analyze` | No issues found |
| APK | `flutter build apk --debug` succeeds; `libsqlite3mc.so` is bundled; no storage permission was added |
| Merged manifest | Re-checked with `aapt2`: `allowBackup=false`, `fullBackupContent=false`, and `dataExtractionRules` excludes all 9 domains from both `cloud-backup` and `device-transfer` |
| Schema / dependencies | Unchanged: `schemaVersion` 1, no migration; `pubspec.yaml` / `pubspec.lock` unchanged |

### 20.11 Not yet verified on a real device

Everything in this section and in §§3–10 has run only on a development
machine. **docs/32** is the checklist (A–Z) to run on real phones before
real data. Most important:

- Q: power loss during restore;
- B–D: screenshot, keyboard and clipboard;
- T: OEM backup and clone tools;
- F: KDF timing.

### 20.12 Remaining production blockers

Unchanged from §16, minus the separate-secrets confirmation (now
approved):

- run docs/32 on real phones, then the KDF iteration decision;
- custody of the two secrets;
- package storage and residency policy;
- inactivity re-lock;
- user management (non-Admin logins, R2).
