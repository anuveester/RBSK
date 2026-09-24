# Authentication Recovery, Database-Key Recovery, Android Backup, and KDF — Decision Analysis

> **Outcome (2026-09-24).** Decisions were approved and implemented as
> security hardening within Phase 1.4 (commit `f27d85b`; report:
> [31_SECURITY_HARDENING_REPORT.md](31_SECURITY_HARDENING_REPORT.md)).
> Phase 1.4 remains **NOT CLOSED**; Phase 1.5 remains **NOT STARTED**. The
> analysis below (§1–§16) is unchanged from when it was written, except
> where this box says otherwise.
>
> | §14 decision | Status |
> |---|---|
> | 1. KDF | **APPROVED FOR NOW:** PBKDF2-HMAC-SHA256, 210,000 iterations, 16-byte salt, 32-byte key. **Not** raised to 600,000; that waits for a real-device benchmark. **IMPLEMENTED:** centralized policy, versioned verifiers, re-hash after login, a failed re-hash keeps the old verifier. |
> | 2. Latency budget | **OPEN** — to be set together with the device benchmark. |
> | 3. PIN recovery (R1; R2 later) | **APPROVED + IMPLEMENTED:** R1 Admin Recovery Code. R2 (second-Admin reset) still needs user management — **FUTURE**. |
> | 4. Recovery code custody | **OPEN** — operational; who keeps the codes is not something the app can decide. |
> | 5. Database-key fail-safe (R3) | **APPROVED (as a mandatory fix) + IMPLEMENTED.** |
> | 6. Android backup policy | **APPROVED: "controlled encrypted backup". IMPLEMENTED** as policy 6 (1 + 4): platform backup and device-to-device transfer disabled; the app's own encrypted recovery package is the backup. |
> | 7. Disaster recovery (R5) | **APPROVED + IMPLEMENTED:** Encrypted Recovery Package. |
> | 8. Separate secrets | **IMPLEMENTED AS PROPOSED** (Admin Recovery Code ≠ Backup Recovery Key). The approval did not address this point explicitly; **please confirm.** |
> | 9. Inactivity re-lock | **OPEN** — not implemented. |
> | 10. Where the work goes | **DECIDED:** security hardening within Phase 1.4 scope. |
> | 11. Phase 1.4 closure | **OPEN** — awaiting your review. |
>
> Section 12's proposed architecture was implemented with one refinement:
> after a restore, an Admin's PIN is set on the new phone using the Backup
> Recovery Key, and only while no Admin can log in there (credentials never
> travel in a package). Details and remaining limitations: docs/31.
>
> *Original status line, kept for the record:* ANALYSIS / PROPOSAL ONLY —
> nothing in this document was approved when it was written.

Prepared 2026-09-24, as the Security Decision Follow-up to the Phase 1.4
independent verification ([29_PHASE_1_4_REPORT.md](29_PHASE_1_4_REPORT.md)
§20).

---

## 1. Purpose

Before real child-health data enters the app, four linked questions need
decisions:

- **A.** What KDF strength the 6-digit PIN verifier should have.
- **B.** How a forgotten PIN is recovered without deleting data.
- **C.** How the database encryption key is protected against loss (a
  different problem from B).
- **D.** What Android backup and restore does to all of the above.

They are analyzed together because the recovery and backup choices decide
what the KDF actually protects, and because **PIN recovery and
database-key recovery are not the same problem** (§9).

## 2. Current architecture (as designed)

```
AUTHENTICATION (Phase 1.4)                 DATA AT REST (Phase 1.2)

IDENTITY        users row (UUIDv4)          DATABASE ENCRYPTION KEY
   ↓                                           256-bit random (Random.secure())
CREDENTIAL      6-digit PIN → PBKDF2           stored in SecureKeyStore
                verifier in SecureKeyStore       ↓
   ↓                                        ENCRYPTED LOCAL DATABASE
SESSION         {userId, role, loggedInAt}     SQLite3MultipleCiphers (PRAGMA key)
                in SecureKeyStore              app_flutter/rbsk_referred_line.sqlite
   ↓
RBAC            AppRole → More-menu entries, route guard
```

The two stacks are **independent**. The PIN does not encrypt, wrap, or
derive the database key, and the database key never depends on any user.

## 3. Verified current implementation

Each item was checked against the code, the library sources, or the built
APK during this analysis, not taken from earlier reports.

| Fact | Evidence |
|---|---|
| PIN verifier = PBKDF2-HMAC-SHA256, 210,000 iterations, 16-byte salt, 32-byte key, constant-time compare; keys that aren't 32 bytes are rejected | `lib/data/local/auth/credential_hasher.dart`; cross-checked with OpenSSL at verification (docs/29 §20) |
| The KDF runs in a background isolate | `Isolate.run` in `credential_hasher.dart`; event-loop probe at verification |
| **The database key and the PIN verifiers/sessions/lockout state share one storage instance** | Both use `const FlutterSecureStorageKeyStore()` → `const FlutterSecureStorage()` with default options (`database_connection.dart:37,54`; `auth_providers.dart:13`) |
| `flutter_secure_storage` 11.2.0 on Android stores values AES-GCM-encrypted in **SharedPreferences** (default file name `FlutterSecureStorage`). The AES key is wrapped by an RSA-OAEP key held in the **Android Keystore**. | Package source: `FlutterSecureStorageConfig.java` (`DEFAULT_PREF_NAME`), `android_options.dart` (default ciphers) |
| **`resetOnError` defaults to `true`**. If the stored key can't be unwrapped (`BadPadding`/`InvalidKey`/`IllegalBlockSize`), the library **deletes all stored data and keys** (`deleteAllDataAndKeys`). If a single value fails to decrypt, it **deletes that value** and returns empty. | `android_options.dart:51`; `FlutterSecureStorage.java` `handleKeyMismatch`, `handleStorageError` |
| `DatabaseKeyManager.getOrCreateKey()` **generates a new key whenever the stored one reads as empty**, and doesn't check whether a database file already exists | `database_connection.dart` (`DatabaseKeyManager`) |
| The database file is in `context.getDir("flutter")` (`app_flutter/`); the SQLite temp dir is the cache dir | `path_provider_android` 2.3.1 `getApplicationDocumentsPath` / `getTemporaryPath` |
| The **merged APK manifest** has no `allowBackup`, `fullBackupContent`, or `dataExtractionRules`, so Android's platform defaults apply. `targetSdk` is 36. There is no `res/xml` directory. | `aapt2 dump xmltree` of the built APK; `android/app/src/main/` |
| Only one runtime `users` insert exists (role `ADMIN`); the verifier is written only at setup; no reset or recovery code exists | `local_auth_repository.dart:80,83` |
| **`pointycastle` 4.0.0 already includes pure-Dart Argon2 (incl. Argon2id) and scrypt**, exported from the same `export.dart` the hasher imports | `pointycastle-4.0.0/lib/key_derivators/argon2*.dart`, `export.dart:72-73` |

**Correction recorded here.** docs/27 §0.1 and the doc comment in
`credential_hasher.dart` say Argon2 was not chosen because "the maintained
Dart options rely on native bindings". **That rationale is factually
wrong.** The dependency already in use provides Argon2id in pure Dart. The
Phase 1.4 verification did not catch this. Its outcome (PBKDF2 was chosen)
is still valid on other grounds (§5), but the stated reason must not be
relied on. This task authorizes no edits to docs/27 or source code, so the
comment and docs/27 should be corrected when the KDF decision (§6) is
implemented.

## 4. KDF analysis

### 4.1 Current baselines, re-checked 2026-09-24

| Source | What it says |
|---|---|
| OWASP Password Storage Cheat Sheet | PBKDF2-HMAC-SHA256: **600,000** iterations. Argon2id is the primary recommendation (minimum configurations from m=46 MiB/t=1 to m=7 MiB/t=5, e.g. m=19 MiB, t=2, p=1). PBKDF2 is preferred where FIPS-140 is required. A pepper should live in an HSM or secrets vault. Hashing "should take less than one second". |
| NIST SP 800-63B-4 §3.1.1.2 (centrally verified passwords) | Salt ≥ 32 bits. Use an approved hashing scheme (SP 800-132). The cost factor "SHOULD be as high as practical without negatively impacting verifier performance". An additional keyed hash with a secret held in a TEE or HSM SHOULD be performed. |
| NIST SP 800-63B-4 §3.2.10 (activation secrets) | At least 4 characters, SHOULD be at least 6. MAY be entirely numeric. At most **10** consecutive failed attempts, after which the authenticator SHALL be disabled. The activation secret "SHALL remain within the authenticator". |

600,000 is therefore still the current OWASP figure for PBKDF2-HMAC-SHA256,
and the current implementation (210,000) is **35%** of it.

That doesn't make 600,000 automatically the right value for this app. The
OWASP and NIST §3.1.1.2 figures are calibrated for **server-side password
databases**. This app's credential is closer to NIST's **activation secret**
model: a short numeric PIN, verified locally, whose protection comes mainly
from the platform and from retry limits, not from hashing cost.

### 4.2 What the KDF actually protects in this architecture

**Search space.** A 6-digit PIN has 10⁶ values. Exhausting it offline costs
10⁶ × 210,000 ≈ 2.1 × 10¹¹ PBKDF2 iterations at the current setting, and
6 × 10¹¹ at 600,000. Either way, the whole space costs about as much as
testing a million guesses against *one* OWASP-grade password hash. OWASP's
work factors are designed to make each guess expensive for passwords with a
far larger search space; they don't claim to make a 10⁶ space safe. **No
iteration count, and no algorithm (Argon2id included), makes a 6-digit PIN
resistant to offline exhaustion.** Going from 210,000 to 600,000 multiplies
the attacker's cost by about 2.9; it doesn't change the conclusion. No
attacker-hardware timings are given here; none were measured, and none are
invented.

**When would an attacker have the verifier?** The verifier is stored
AES-GCM-encrypted under a key wrapped by a non-exportable Keystore key
(§3). Android's documentation is explicit that key material "never enters
the application process" and that an attacker who compromises the app
process "might be able to use the app's keys but can't extract their key
material".

- **Offline file copy** (backup file, storage dump without code execution
  as the app): the verifier is ciphertext and unusable. **The KDF isn't
  reached.**
- **Code execution as the app** (rooted or compromised device): the
  attacker can use the Keystore key to decrypt *every* secure-storage
  entry. **That includes the database encryption key, which sits in the
  same storage** (§3). The attacker can then read the database directly
  without the PIN. Cracking the PIN adds nothing for data confidentiality.

**The consequence is important.** In the current architecture, the PBKDF2
iteration count protects the **PIN value itself** — against reuse of the
same digits elsewhere, such as a phone unlock code, and against
impersonation of that user. It **does not protect the child-health data**.
Data confidentiality rests on the Android sandbox, the Keystore, and the
device lock. It fails entirely on a compromised device, whatever the KDF.

**Where the KDF cost does matter: on-device guessing through the app.**

- With the lockout (5 attempts, then 60 s), guessing is capped at about
  7,200 attempts a day. Exhausting all 10⁶ PINs would take up to about
  139 days (about 69 days on average) for someone with unrestricted access
  to an unlocked device.
- Moving the device clock forward can end lockouts early (docs/27 §0.3). An
  attacker who controls an unlocked device's clock is then limited by the
  KDF time per attempt, which scales linearly with the iteration count.
  That per-attempt time on real hardware is **unmeasured**.
- The lockout has **no overall cap**. NIST's activation-secret model allows
  at most 10 consecutive failures before disabling. A hard cap is only safe
  once a recovery path exists (§7). Otherwise it becomes the permanent
  lockout the Phase 1.4 approval prohibits. This coupling is why
  lockout-cap changes are sequenced after recovery (§15).

### 4.3 Practical constraints

| Factor | Assessment |
|---|---|
| Device latency | **Unmeasured.** No Android device or emulator was available. The only measurement is about 1.7 s per derivation for 210,000 iterations in the Flutter *debug* test VM on a desktop. It is **not** representative of a release (AOT) build on a phone, in either direction. |
| Latency budget | OWASP says hashing "should take less than one second". Login happens many times per field day on shared devices, so a budget of about 1 s on the lowest-spec field device is a reasonable target (this is a proposal — §14). |
| Memory | PBKDF2 needs negligible memory. Argon2id needs 7–46 MiB per derivation at OWASP's minimums, allocated inside the Dart heap of a background isolate. Whether older `minSdk 26` devices tolerate this comfortably is unmeasured. |
| Battery | One short CPU burst per login attempt. Expected to be small next to screen use, but **unmeasured**. |
| Pure-Dart implementation | Both PBKDF2 and Argon2id in `pointycastle` are pure Dart, with no native acceleration. Pure-Dart Argon2id performance on Android is **unknown**. The constraint is speed, not availability (see the §3 correction). |
| Upgrade path | The verifier format embeds its own iteration count, so raising it needs no migration. **Today, though, a verifier only changes when the credential is re-set.** Without a "re-hash on successful login" step, existing verifiers never reach a new count. |

### 4.4 Should the algorithm change to Argon2id?

Argon2id is OWASP's primary recommendation, and memory-hardness raises the
cost of GPU attacks per guess. Here, however:

1. the 10⁶ search space stays exhaustible either way (§4.2);
2. the verifier is only reachable by an attacker who can already read the
   database key (§4.2), so a stronger KDF buys no data protection;
3. pure-Dart Argon2id performance and memory behavior on target devices are
   unknown;
4. changing algorithm adds a second verifier format and a migration path.

**Assessment:** switching to Argon2id is **not justified at this stage**.
Revisit it if verifiers ever leave the device's protection domain, for
example if a future cloud identity design stores verifiers server-side, or
if an on-device benchmark shows Argon2id fits the latency budget at no
extra complexity.

**The control that actually changes the posture** is NIST's "additional
keyed hash with a secret held in the TEE". That would mean an Android
Keystore HMAC key (StrongBox where available), applied on top of PBKDF2, so
a copied verifier can't be tested off the device at all. It needs native
platform code or a new plugin (a new dependency). It still wouldn't stop an
attacker who can run code as the app, who would use the database key
instead. **Classified as FUTURE ARCHITECTURE.**

## 5. KDF options

| Option | Security effect | Cost/risk | Assessment |
|---|---|---|---|
| K1. Keep PBKDF2 at 210,000 | Current posture. Protects the PIN value only; below OWASP's figure. | None | Acceptable only as an explicit, recorded trade-off |
| K2. PBKDF2 at 600,000 | About 2.9× more work per guess; matches the published baseline, which helps defensibility for government health data | About 2.9× login latency (unmeasured on device) | Preferred **if** it fits the latency budget |
| K3. PBKDF2 at the highest count within the budget, never below 210,000 | Between K1 and K2 | Needs a benchmark | Fallback if K2 misses the budget |
| K4. Argon2id (OWASP minimum config) | Memory-hard per guess; still exhaustible over 10⁶ | Unknown pure-Dart performance and memory; a second format; migration | Not justified now (§4.4) |
| K5. Add a hardware-bound keyed hash (Keystore HMAC pepper) | Stops off-device testing of a copied verifier | Native code or a new plugin; a Keystore key-loss mode | Future architecture |
| K6. Longer or alphanumeric PIN | Grows the search space, the only lever that changes the offline picture materially | UX change; would reverse an approved decision (6-digit PIN) | Not proposed; noted for completeness |

## 6. KDF — PROPOSED decision (awaiting your approval)

1. **Keep PBKDF2-HMAC-SHA256.** No algorithm change now.
2. **Target 600,000 iterations (OWASP), gated on an on-device benchmark.**
   Measure a release build on the lowest-spec device the RBSK team will
   actually use. If one derivation takes ≤ about 1 s (the budget is your
   decision, §14), adopt 600,000. Otherwise adopt the highest count within
   the budget, never below 210,000, and record the residual risk.
3. **Add re-hash on successful login** so existing verifiers move to the
   new count automatically.
4. **Correct the Argon2 rationale** in docs/27 §0.1 and in the
   `credential_hasher.dart` comment (§3), at the same time.
5. **Record plainly** that the KDF protects the PIN value, not the data
   (§4.2), so no one mistakes a higher iteration count for data protection.
6. Until the benchmark exists, **210,000 remains in force** as a documented
   trade-off. That keeps Phase 1.4 closable without a device.

## 7. The PIN recovery problem

**Current state (verified):** there is no recovery path. If the only Admin
forgets the PIN, the only way out is Android's "Clear data" or reinstalling.
That deletes the database file and the secure-storage entries, and all
local data with them.

**What this is and isn't:** data loss after a forgotten PIN is **not a
cryptographic necessity**. The database key isn't derived from the PIN
(§2). After a forgotten PIN the key is still intact in secure storage and
the data is still decryptable by the app. What's missing is an **authorized
way to issue a new credential**. So PIN recovery is purely an
**authentication** problem.

**The two requirements:**
- Forgetting the PIN **must not** force deletion of real child-health data.
- Recovery **must not** become a backdoor that lets an unauthorized person
  reach the data.

Any recovery path is by definition a way into the app without the PIN, so
its security equals the security of whatever authorizes it. It must
require a secret or authority that is at least as hard for an unauthorized
person to obtain as the PIN, and every use must be visible (audited).

## 8. PIN recovery options

All options below assume the device itself is still available. Device loss
is §9–§11.

| | A. Second Admin reset | B. Admin recovery code | C. Device-bound (Android screen lock / biometric) | D. Encrypted recovery package | E. Cloud / server-assisted | F. Hybrid |
|---|---|---|---|---|---|---|
| Mechanism | Another active Admin **on the same device** resets the forgotten user's PIN | A high-entropy code (e.g. 128-bit), generated at first-run Admin setup, shown once, kept off-device by a designated custodian. Stored on the device only as a verifier. Entering it lets you set a new Admin PIN. | Prove the device's own lock-screen credential (Keystore user-authentication) to reset the app PIN | An off-device file holding the DB key (or the data), encrypted under a high-entropy recovery secret | A server identity (e.g. Supabase Auth) authorizes the reset; possibly server key escrow | A (when available) + B for access; D (later E) for data and devices |
| Security | Strong. Needs a second valid credential. | Strong if the code is high-entropy and custody is sound. **Anyone holding code + device can take over the Admin account**; that's the intended power, so custody is the control. | **Weak for shared departmental devices**: whoever knows the phone's unlock code (possibly several team members) could reset the Admin PIN, bypassing RBAC. Needs a device lock to be set at all. | Strong if the secret is high-entropy. Solves a different problem (data portability), not access on this device. | Depends on the server; strong if designed well | Strongest overall |
| Offline | Yes | Yes | Yes | Yes (file transport is manual) | **No** | Yes for A and B |
| Preserves local encrypted data | Yes (DB key untouched) | Yes (DB key untouched) | Yes | Yes, and also on another device | Yes | Yes |
| Creates a bypass? | No. Only another authorized credential. | A controlled, audited one: the code *is* an authorization credential. | **Yes**, in the shared-device context | Not for access on this device | Controlled by the server | Controlled |
| Needs another trusted person/device | Yes, a second Admin enrolled on **this** device (accounts are device-local) | A trusted custodian | No | A custodian for the file and secret | Server operator, network | Custodian ± second Admin |
| Complexity | Needs user management (not built) | Moderate: generation, one-time display, verifier, reset flow, rotation after use | Moderate plus a new plugin; biometrics explicitly deferred | High: key wrapping, file format, import flow | Very high; needs the cloud phase and a data-residency decision | Sum of the chosen parts |
| Forgotten PIN | Solved if a second Admin is available | Solved if the code is retrievable | Solved | Not directly (it's for data) | Solved when online | Solved |
| Lost device | Nothing on the device helps; see §11 | Code is useless without the device | Same | **This is what D is for** | Server data re-sync, if built | D or E |
| Stolen device | Thief also needs a second Admin's PIN | Thief also needs the code (kept off-device) | **Thief with the unlock code can reset** | Package isn't on the device | Server can revoke | Good |
| Compromised recovery secret | n/a | Holder + device = Admin access. Rotate the code; the device must also be in their hands. | n/a | Holder + package = **full data decryption** | Server compromise | Keep secrets separate (see §12) |
| Backup/restore | Accounts don't survive restore (§10) | Code verifier doesn't survive restore (Keystore) | Keystore-bound | Designed to survive | Designed to survive | — |

**Assessment:** C is rejected for this deployment (shared devices, and
biometrics are deferred). E isn't available (no cloud phase, and data
residency is undecided). **A alone isn't enough.** Accounts are
device-local, a second Admin isn't guaranteed to be present, and user
management doesn't exist yet. **B is the only option that works offline,
on the device, now, without creating an unaudited bypass.** D answers a
different question (device and data recovery), handled in §11–§12.

## 9. Database-encryption-key recovery analysis

**PIN recovery and database-key recovery are different problems.**
Resetting a PIN re-issues an *authentication* credential and never touches
the database key. Losing the database key makes the data *mathematically*
unreadable, and no authentication step can bring it back.

| Scenario | Effect today (from code and library source; **device behavior UNVERIFIED**) |
|---|---|
| Does the PIN encrypt the database? | **No.** The DB key is random and independent of every user. |
| Can the PIN verifier recover the DB key? | **No.** The verifier is a one-way derivation of the PIN; the DB key is unrelated. |
| PIN forgotten | DB key and data intact. Only access is blocked (§7). |
| Secure-storage entry lost or unreadable (e.g. a Keystore key-unwrap failure, an OEM Keystore fault, corruption) | With `resetOnError: true` (the default) the library **silently deletes** the unreadable entries. `DatabaseKeyManager` then **generates and stores a new key**, and opening the existing database with it fails ("file is not a database"). The app stays on the splash error permanently, the old key is gone, and **the data is unrecoverable**. **This silent path from a storage error to permanent data loss is a new finding.** It predates Phase 1.4 (Phase 1.2 key handling) and should be fixed before production (§13). |
| App uninstalled and reinstalled | Uninstall removes the app's data directory (database file and secure-storage prefs). App-owned Keystore keys are expected to be removed too (**not verified in this pass**). With no restore, the data is gone. |
| Device migration (device-to-device transfer) or restore from cloud backup | The database file and the secure-storage prefs file may be transferred (§10). **Keystore keys are non-exportable and can't be transferred.** The restored wrapped key can't be unwrapped, so the path in row 5 follows. Result: a restored database that **can never be decrypted**, plus a stuck app. **UNVERIFIED on a device.** The `flutter_secure_storage` README itself warns that backup "can cause exception `java.security.InvalidKeyException: Failed to unwrap key`". |
| Factory reset | Everything on the device is gone. A later restore behaves as in row 7. |
| Auto Backup restores the encrypted DB but not the Keystore key | As row 7: the DB is undecryptable. It keeps occupying space, and nothing in the app explains why. |
| Phone lost | Local data is encrypted at rest; an attacker needs a device unlock or an exploit (§4.2). **RBSK loses all data held only on that phone.** There is no off-device copy today (no export, no sync). |
| Recovery secret lost | Not applicable today; see §12 for the proposed design. |

**Conclusion:** today the only copy of the database key lives in one
Keystore-protected storage slot on one device. That slot can be **silently
deleted** by a storage error, and nothing distinguishes "key lost" from
"first launch". Before real data is entered, the key must fail safe, and
any off-device recovery must be a deliberate, separately protected design
(§11–§12).

## 10. Android backup / restore analysis

**Current configuration (verified in the built APK):** there is no
`allowBackup`, no `fullBackupContent`, no `dataExtractionRules`, and no
`res/xml` backup rules, so platform defaults apply. `targetSdk` is 36.

**What Android's documentation says the defaults mean:**
- `allowBackup` defaults to `true`; apps targeting API 23+ take part in
  Auto Backup.
- Included by default: shared-preferences files, `getFilesDir()`,
  **`getDir()` directories**, `getDatabasePath()`, and
  `getExternalFilesDir()`.
- Excluded by default: the cache dir, the code-cache dir, and the
  `getNoBackupFilesDir()` dir.
- Quota: 25 MB per app. Above that, cloud backup doesn't happen.
- Backups are end-to-end encrypted only on Android 9+ with a screen lock
  set.
- For apps targeting Android 12+: on some manufacturers' devices,
  `allowBackup="false"` disables Google Drive backup but **not
  device-to-device transfer**. Include/exclude rules for device-to-device
  transfer need `dataExtractionRules` with a `<device-transfer>` section.

**What that means for this app:**

| Item | Eligible for backup/transfer? | Usable after restore? |
|---|---|---|
| Encrypted database (`app_flutter/rbsk_referred_line.sqlite`) | **Yes** (a `getDir()` directory), while under 25 MB | **No.** Its key isn't restorable. |
| Secure-storage prefs (DB key, PIN verifiers, session, lockout; all encrypted) | **Yes** (shared prefs) | **No.** The Keystore wrapping key is non-exportable, which triggers the silent-deletion path in §9. |
| Keystore keys | No (non-exportable) | — |
| SQLite temp files | No (cache dir) | — |

- **Same device:** there is no in-place restore. A restore happens on
  reinstall, after uninstall has removed the Keystore keys (expected; **not
  verified**), so the outcome matches a different device.
- **Different device:** the database and the encrypted prefs arrive; the key
  doesn't. The result is **a restored database that cannot be decrypted**,
  plus the stuck state described in §9.
- **Confidentiality:** the backed-up database stays encrypted under a key
  that isn't in the backup, so cloud copies shouldn't be readable by Google
  or an attacker. **However,** encrypted child-health data still leaves the
  device for Google Drive. That bears on the **open data-residency
  decision** (Master Plan §10 #6; Phase 0.6 approval condition 4).

**This whole section is UNVERIFIED on a device.** It needs these tests later:
- cloud backup and restore;
- device-to-device transfer;
- reinstall with restore;
- exactly what the app shows afterwards.

**Policies:**

| Policy | Effect | Assessment |
|---|---|---|
| 1. Disable backup completely: `allowBackup="false"` **and** `dataExtractionRules` excluding everything from both `<cloud-backup>` and `<device-transfer>` | No unusable restores, no silent-deletion trigger from restore, no child data sent to Google Drive | **Recommended.** Loses nothing, since today's backups can't be decrypted. |
| 2. Exclude only the database | The prefs still restore, and still hit the key-unwrap and silent-deletion path | Incomplete |
| 3. Keep DB backup plus a separately recoverable key (key escrow in backed-up prefs, wrapped by a recovery secret) | Would make OS backup genuinely restorable | Couples recovery to Google Drive; residency question; the recovery secret then decrypts cloud-held child data. **Not before the data-residency decision.** |
| 4. App-level encrypted recovery package (export) | Deliberate, Admin-triggered, off-device copy under a separate high-entropy secret; already anticipated by docs/04 §6 and docs/08 §Backup | **Recommended** as the data/disaster-recovery path |
| 5. Future server sync/backup | Makes a lost device non-fatal (server as source of truth) | Future; needs the cloud phase and a data-residency decision |
| 6. Hybrid (1 + 4, later 5) | — | **Proposed** |

## 11. Recovery architecture options (layered)

The layers are kept separate so that no single secret or failure does
everything:

| Layer | Question it answers | Candidate mechanisms |
|---|---|---|
| **Authentication recovery** | "The user forgot their PIN; the device is fine." | B (recovery code); A (second Admin, once user management exists) |
| **Database-key protection** | "Don't lose the key on the device by accident." | Fail-safe storage (no silent reset), key-lost detection |
| **Device recovery** | "The device was lost, replaced, or reset." | Fresh first-run setup on the new device; re-provision users; restore data from layer 5 |
| **Backup recovery** | "What does OS backup do?" | Policy 1: disabled, so it can't produce broken restores |
| **Disaster recovery** | "Get the data back after device or key loss." | Encrypted recovery package (policy 4); later server sync (policy 5) |

## 12. PROPOSED recovery architecture (awaiting your approval)

**R1 — Admin Recovery Code (authentication recovery; offline; same device).**
- Generated at first-run Admin setup, and regenerable later by an Admin.
- At least 128 bits of randomness from `Random.secure()`, shown in a
  human-transcribable form, **displayed once**, with transcription
  confirmed.
- Stored on the device **only as a verifier**, in the same verifier format.
- Entering it:
  - lets the user set a new Admin PIN;
  - **consumes the code**, and a new one is issued immediately;
  - is subject to the lockout;
  - writes an audit event (requires the audit write path, §13).
- **It never touches the database key**, so data is preserved.
- Custody: the physical code is held by a designated custodian, separate
  from the device and from the Medical Officer's own PIN. Who that is is an
  operational decision for you and the RBSK program (§14).

**R2 — Second-Admin reset (authentication recovery; when user management exists).**
Any active Admin on the same device may reset another user's PIN, audited.
Operational policy proposal: at least two Admin accounts per device.

**R3 — Database-key fail-safe (must precede real data).**
- (a) Store the DB key in a secure-storage configuration with
  **`resetOnError: false`**, so a storage error surfaces as an error instead
  of silently deleting the key.
- (b) **Never generate a new key when a database file already exists.**
  Treat that as a "database key unavailable" state, with a clear message
  and no destructive action.
- (c) Keep the DB key logically separate from auth state (verifiers,
  sessions, lockout), so auth-state handling can never reach it.

**R4 — Backup policy.** Policy 1: disable cloud backup **and**
device-to-device transfer explicitly.

**R5 — Encrypted Recovery Package (disaster recovery).**
- An Admin-triggered export (as anticipated by docs/04 §6 and docs/08)
  containing the database, or the database key plus database, encrypted
  under a key derived from a **separate high-entropy Data Recovery Secret**.
  It is **not** derived from the PIN, and **not** the same as the R1 code.
- The package is stored off-device according to a custody and residency
  policy you decide.
- On a replacement device: fresh first-run setup, then import with the
  secret.
- The R1 code and the R5 secret are separate so that one compromised
  secret doesn't give both app access and data decryption.

**R6 — Future:** server sync/backup and cloud identity (policy 5 / option
E), after the data-residency decision.

**Answers to the three required questions (under the proposal):**

1. *"If the Medical Officer forgets the 6-digit PIN, how can an authorized
   person regain access to the same encrypted local data without deleting
   it and without creating an unauthorized bypass?"*
   - If the MO's account is the only Admin: the custodian supplies the
     **Admin Recovery Code** (R1), which is used on that device to set a
     new PIN.
   - If the MO is a non-Admin, or a second Admin exists: an Admin resets
     the PIN (R2).
   - In both cases the database key and data are untouched. The reset needs
     a credential the attacker doesn't have (code custody, or another
     Admin's PIN). It is audited, and the code is rotated after use.
2. *"If the Android device is lost or replaced, what exactly can and cannot
   be recovered?"*
   - **Cannot:** user accounts and PIN verifiers (device-local and
     Keystore-bound, by design), sessions, lockout state, and any data
     created after the last recovery package.
   - **Can:** data up to the last R5 package, onto the new device, with the
     Data Recovery Secret. Users are re-provisioned there.
   - **Today (no R5):** nothing is recoverable. Device loss means loss of
     all digital data held on that device. The physical register remains,
     since the app never replaces the paper original.
3. *"What happens if both the PIN and the recovery mechanism are lost?"*
   - If another Admin exists on the device: R2.
   - Otherwise there is **deliberately no way back into that device's
     data**, because any such way would be a backdoor. The data stays
     encrypted on the device, with its key intact but no authorized path
     to use it. Data can then only come from an R5 package (with its
     separate secret) or a future server copy. If neither exists, the
     digital data on that device is lost. **This is the intended outcome
     of "no backdoor"; it can only be mitigated operationally**: custody
     of the code, two Admins, regular packages.

## 13. Production blockers — classification

| Item | Classification | Notes |
|---|---|---|
| KDF parameter (§6) | **MUST DECIDE** | Keeping 210,000 as a recorded trade-off is a valid decision |
| KDF on-device benchmark | **MUST IMPLEMENT BEFORE PRODUCTION** | Needs a real device |
| PIN recovery (R1; later R2) | **MUST DECIDE + MUST IMPLEMENT BEFORE PRODUCTION** | Blocker before real child/health data (existing Master Plan §10 #13) |
| Database-key fail-safe (R3: `resetOnError`, key-lost detection) | **MUST IMPLEMENT BEFORE PRODUCTION** | **New finding.** Today a storage error can silently destroy the only key. Predates Phase 1.4. |
| Android backup policy (R4) | **MUST DECIDE + MUST IMPLEMENT BEFORE PRODUCTION** | Manifest and XML configuration only |
| Disaster recovery (R5, or an explicit acceptance of "device loss = digital data loss") | **MUST DECIDE**; implement before production unless you explicitly accept the loss | Tied to custody and data residency |
| Real-device testing (auth flows, lockout, restart, restore/transfer/reinstall behavior, KDF timing) | **MUST IMPLEMENT BEFORE PRODUCTION** | Nothing has run on a device yet |
| Session inactivity re-lock | **MUST DECIDE** (duration) + **MUST IMPLEMENT BEFORE PRODUCTION** | Shared devices + child-health data; docs/08 already recommends it |
| User creation / Admin management | **MUST IMPLEMENT BEFORE PRODUCTION** | Needed for any non-Admin login, and enables R2 |
| Audit write path for auth and recovery events | **MUST IMPLEMENT BEFORE PRODUCTION** | Core principle 10; recovery without an audit trail is an unaccountable bypass |
| Lockout overall cap / escalation (NIST ≤10 model) | **CAN BE DEFERRED**; only after recovery exists | A cap without recovery is a permanent lockout |
| Role/deactivation propagation across devices | **FUTURE ARCHITECTURE** | Sync phase |
| Hardware-bound verifier pepper (Keystore HMAC) | **FUTURE ARCHITECTURE** | New native code or plugin |
| PIN-gated database key (key slots wrapped by per-user secrets) | **FUTURE ARCHITECTURE**, and not recommended with 6-digit PINs unless hardware-bound | Adds data-loss modes; small gain (§4.2) |
| Server sync/backup, cloud identity | **FUTURE ARCHITECTURE** | Needs the data-residency decision |
| Data backup/restore testing | **MUST IMPLEMENT BEFORE PRODUCTION** once R5 exists | — |

## 14. Open decisions requiring your approval

1. **KDF:** approve §6 (PBKDF2 kept; 600,000 target gated on a benchmark;
   re-hash on login), or choose another option from §5.
2. **Latency budget** for the KDF benchmark (proposed: about 1 s per
   derivation, release build, lowest-spec field device).
3. **PIN recovery architecture:** approve R1 (Admin Recovery Code) now and
   R2 when user management exists, or choose differently from §8.
4. **Recovery code custody:** who holds it, where, and how it's reissued.
   This is operational and cannot be invented by Claude.
5. **Database-key fail-safe (R3):** approve as a pre-production
   requirement.
6. **Android backup policy:** approve policy 1 (disable cloud backup and
   device-to-device transfer), or choose another.
7. **Disaster recovery:** approve R5 (encrypted recovery package) as a
   pre-production requirement, or explicitly accept that device or key loss
   means loss of digital data (the paper register remains).
8. **Separate secrets:** confirm that the R1 code and the R5 secret must be
   different.
9. **Inactivity re-lock duration.**
10. **Where this work goes:** a dedicated security-hardening phase before any
    real data (proposed), rather than expanding Phase 1.4. Numbering is
    yours to assign.
11. **Phase 1.4 closure:** Phase 1.4 can be closed with these items as
    tracked pre-production blockers, or held open. Your call.

## 15. Recommended next implementation sequence (PROPOSAL)

Ordered cheapest-and-most-protective first:

1. **Your decisions** (§14).
2. **Security-hardening phase** (before real data):
   - a. Backup policy (R4): configuration only.
   - b. Database-key fail-safe (R3): no silent deletion; key-lost state.
   - c. Admin Recovery Code (R1) with audit events.
   - d. KDF per the decision, plus re-hash on login and the corrected
     rationale comment.
   - e. Inactivity re-lock.
3. **Real-device test campaign:**
   - KDF benchmark (it feeds back into 2d);
   - all auth flows;
   - restore, device-transfer, and reinstall behavior;
   - memory and latency.
4. **User management** (enables non-Admin logins and R2).
5. **Encrypted Recovery Package (R5)**, with restore testing; or the sync
   phase, per the data-residency decision.
6. Only then: real child-health data. Feature phases (1.5+) may be
   developed in parallel with synthetic data only, if you choose.

## 16. Status of this document

**This document is ANALYSIS and PROPOSAL only. It does not constitute your
approval of any decision.** Every "Proposed" item above is pending. It
changes no code, schema, dependency, authentication or encryption
behavior, or Android configuration. Phase 1.4 remains **NOT CLOSED**.
Phase 1.5 remains **NOT STARTED**.

### Sources consulted (2026-09-24)

- OWASP Password Storage Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
- NIST SP 800-63B-4 (§3.1.1.2 password verifiers; §3.2.10 activation secrets): https://pages.nist.gov/800-63-4/sp800-63b.html
- Android Auto Backup: https://developer.android.com/identity/data/autobackup
- Android 12 behavior changes (backup / device-to-device transfer): https://developer.android.com/about/versions/12/behavior-changes-12
- Android Keystore system: https://developer.android.com/privacy-and-security/keystore
- Package sources in the local pub cache: `flutter_secure_storage` 11.2.0 (README, `AndroidOptions`, `FlutterSecureStorage.java`, `FlutterSecureStorageConfig.java`); `path_provider_android` 2.3.1; `pointycastle` 4.0.0
