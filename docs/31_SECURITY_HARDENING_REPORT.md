# Security Hardening — Implementation Report

**Status: IMPLEMENTED, awaiting your review. Phase 1.4 remains NOT CLOSED.
Phase 1.5 NOT STARTED.**

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
  its key. An interruption can be finished by running the restore again.
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
4. **Authorization for export and backup-key creation** is enforced by the
   Admin-only route, the UI and a PIN check, but not re-checked inside
   `DatabaseRecoveryService` (defense-in-depth gap).
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
15. **Screenshots:** blocked only while a secret is displayed, not on the
    screens where codes are typed.
16. **Leftover files:** if the app is killed mid-export or mid-import,
    encrypted temporary files may remain until the next operation or a
    cache clear.

## 16. Remaining production blockers (before real child-health data)

- A real-device test campaign: every flow above, backup and restore
  drills, and the KDF benchmark, followed by the latency and iteration
  decision.
- Custody: who holds the Admin Recovery Code and the Backup Recovery Key,
  where, and how they are reissued.
- Where recovery packages may be stored (data residency, docs/00 §10 #6).
- Your confirmation that the two secrets are separate (docs/30 box,
  decision 8).
- The inactivity re-lock decision and its implementation.
- User management (non-Admin logins, and R2).

## 17. Commits

- `f27d85b`: code and tests.
- The documentation commit that adds this report (see `git log`).

## 18. Phase 1.4

**Remains OPEN / NOT CLOSED.**

## 19. Phase 1.5

**NOT started.**
