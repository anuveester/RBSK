# Risks & Open Questions

## Open questions requiring a human answer (not guessed in this package)

1. **Data residency / hosting policy for child health data.** Does the district health
   authority or state RBSK program require data to stay on India-based or
   government-approved infrastructure? This determines whether Supabase Cloud (default
   region) is acceptable or whether self-hosted Supabase (or another India-region host)
   is required. See [08_SECURITY_ARCHITECTURE.md](08_SECURITY_ARCHITECTURE.md).
2. **iOS support.** Brief mentions Android specifically throughout (Android file
   sharing, APK-style deployment implied). Confirm whether iOS is ever needed — Flutter
   keeps this cheap to add later, but confirming now avoids wasted iOS-specific testing
   effort if it's genuinely never needed.
3. **Geo hierarchy scope.** Is this team's coverage area a single block, a single
   district, or multiple districts? Determines whether plain-text district/block columns
   (current design) are sufficient or whether normalized lookup tables should be built
   now instead of later. See [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md)
   §7.
4. **"Own-team" report scoping for TEAM_MEMBER role.** With only 8–10 users likely all
   on one team, does restricting TEAM_MEMBER report visibility to "their own entries"
   make sense, or should all authenticated users see all team reports? Current RBAC
   matrix (§04 §3) flags this as unresolved — leaning toward "all users see all reports"
   given the small, trusted team size, pending confirmation.
5. **Treatment record final-disposition permission.** Should TEAM_MEMBER be able to mark
   a treatment as fully DONE/further-referred, or only enter attendance and let a
   Medical Officer confirm disposition? Flagged in §04 §3, not decided.
6. **Backup/retention policy and budget.** Supabase tier (free vs. paid, which affects
   point-in-time recovery availability) is a cost decision outside this document's
   scope — needs a budget owner's input.
7. **Official report format.** Does the department mandate a specific PDF/Excel layout
   for upward submission? If a sample exists, supply it (see
   [../SOURCE_MATERIALS_REQUIRED.md](../SOURCE_MATERIALS_REQUIRED.md)) so
   [10_REPORTING_EXPORT_ARCHITECTURE.md](10_REPORTING_EXPORT_ARCHITECTURE.md) can match
   it exactly instead of using a generic layout.
8. **Aadhaar handling.** The brief lists Aadhaar as a possible AWC field ("where
   applicable"). Aadhaar numbers are legally sensitive in India — confirm whether it's
   actually required by the official Job Aid, and if so, whether it needs masking in the
   UI/reports and additional storage safeguards beyond what's specified in
   [08_SECURITY_ARCHITECTURE.md](08_SECURITY_ARCHITECTURE.md). Do not collect it
   speculatively if the Job Aid doesn't actually require it.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Job Aid / Micro Plan Excel never supplied, or supplied late | Blocks Phase 1 real data modeling (School/AWC/Disease Master finalization) | Schema already reserves the known field names as nullable/TBD (§04 §7); scaffolding work (auth, navigation, local DB skeleton) can proceed in parallel |
| OCR accuracy on handwritten Devanagari/mixed-script registers is poor | Review burden shifts heavily to manual correction, undermining the "less typing" principle for that one feature | Mandatory human review already designed in (FR-13.2); confidence threshold tunable; worst case, OCR becomes a lower-priority feature while manual entry remains fully functional standalone |
| 8–10 users all editing near-real-time on visit days causes more sync conflicts than expected | Conflict-resolution UI (rare-path by design) gets used more than anticipated | Conflict detection is already structural (row_version), not a Phase-4 add-on; can promote Sync Conflicts screen to a more prominent location if usage data shows it's needed |
| Underestimating device diversity (old/low-end Android phones in field use) | Performance/camera-quality issues | Target minSdk conservatively (align with sibling project's minSdk 26 precedent unless a reason to differ emerges); test on a low-end device during Phase 1 |
| Scope creep back into "just build everything now" | Repeated schema changes, technical debt | This Phase 0 package + phased plan (§13) is the guardrail — treat schema changes after Phase 1 sign-off as exceptional, not routine |
| Disease Master taxonomy finalized from Job Aid turns out to need more structure (e.g. scoring, cutoffs) than a flat name+category | Could need additional fields | `disease_master` and `awc_screenings` already leave room (§04 §7) for additive columns without breaking existing data |

## Non-risks worth naming (to avoid over-engineering against them)

- **Scale**: 8–10 users, a few thousand records/year is not a "big data" problem. Don't
  add sharding, caching layers, or premature performance work.
- **Multi-tenancy**: this is a single team's private app, not a SaaS product. No
  tenant-isolation architecture needed.
- **Real-time collaboration**: no requirement for two users to see each other's edits
  live. Standard sync-on-reconnect is sufficient; no need for websocket-based live
  presence/collaboration infrastructure.
