# Person One Phase 2 hardening

The Person One implementation was checked against manual v4 §8.4, §19.5,
§19.6, §19A and §27.3, including the owner's accepted direct-skill and visual
amendments. Backend, iOS and private-device tooling changes are implemented and
locally verified. G2 remains open for the actual device walkthrough and independent
contract/design/connected-checkpoint approvals.

## Findings fixed

| Severity | Finding | Fix and evidence |
|---|---|---|
| High | Ask classification ran before account creation limits and idempotency replay. Repeated accepted/rejected mutations could spend model capacity again. | `AskService` and `RequestService` perform admission before classification, then recheck replay inside the final transaction. `ClassificationAdmissionTest` proves replay/conflicts/over-limit calls do not invoke the provider, including replay after quota exhaustion. |
| Medium | The legacy request route held its account row lock during external classification. | Extraction now runs outside the database transaction. A provider-thread `FOR UPDATE NOWAIT` probe proves both creation routes release the account lock. Existing concurrent replay/cancellation tests and the live suite still pass. |
| Medium | Structured model decoding accepted omitted required fields and a null/oversized skill list. | Missing schema fields now reject the whole model response; tags must be an array of at most five. Nullable fields must be explicitly present. Valid structured output is still accepted; failures use deterministic rules. |
| Medium | Truncating long custom-skill tags or removing non-Latin characters could alias unrelated services or silently deduplicate two labels on one profile. | Lossy identifiers receive a stable digest within the existing category length. Short ASCII tags stay unchanged. Unit cases cover long and non-Latin labels; a real PostGIS test proves only the correct provider receives a match. Existing saved tags remain unchanged until a profile is re-saved. |
| Medium | Phone scripts depended on ephemeral public tunnels and addresses. | Both phone workflows now use a paired-interface-only relay with exact peer allowlisting, bounded bodies/responses and no sensitive request logging. The live runner discovers the paired address and holds the connection. It restores prior local build settings on exit. |
| Low | The live suite still expected the old `listed_skill` rejection after direct entry was approved. | It now asserts canonical `wig_install` mapping and retains the licensed-work rejection. No response shape or contract route changed. |
| Low | The phase README used nonexistent root Gradle tasks and old Xcode project/scheme names. | Commands now reference `backend/dev`, `ios/Plug.xcodeproj`, the Plug scheme and the isolated database runbook. |

## Verification

- Backend: **65 unit tests and 88 database tests**, zero failures, plus Checkstyle and
  boot JAR. Final run used a new disposable `plug_p2_owner_final_20261004` database.
  The provider suite also passed on a second fresh database after strengthening the
  persisted-identifier assertion.
- Static contracts/fixtures: **185 passed**.
- Live API: **1,008 checks passed**, zero failed across 283 exchanges. Report:
  `evidence/P2/security/phase2-person-one-2026-10-04.json`.
- Bruno: **49 requests, 64 tests, 88 assertions**, all passed.
- iOS: **67 unit/integration tests passed**, including real sign-in against the isolated API.
- Backend outage/restart: five checks passed. The same session and ask survived; replay
  returned the original response; repeated cancellation remained idempotent. Report:
  `evidence/P2/failures/backend-recovery-2026-10-04.json`.
- Approved Ask home and navigation source sections exactly match their saved snapshots.
  No UI layout changed in this hardening pass; previous normal/largest-text screenshot
  results remain in `phase2-remaining-pages-2026-10-04.md`.
- Final signed app installed and launched on the paired iPhone through the updated private
  launcher; the live database was preserved.
- Shell syntax, JavaScript syntax and diff whitespace checks passed. Relay rejects
  wildcard/public addresses, peers outside the paired subnet, and a peer equal to the host.

An intermediate database rerun reused prior test state and failed two worker/matching
assertions. The new admission tests now clean up only their own records; the final full
run used a fresh database and passed. The phone's live database was never reset.

The live suite ran the admission/schema build; the subsequent identifier change was
verified by the full final unit/database run, including actual provider matching. The
outage/recovery check and phone backend use the final JAR snapshot.

## Remaining evidence and shared work

Physical UI automation is blocked by the separate UI test runner provisioning profile.
The existing app profile is valid, but two command-line attempts report `No Accounts`
and no profile for `com.abubakarsidiq01.plug.app101.uitests.xctrunner`. The UI test target
now explicitly uses the app's development team and automatic signing. The owner confirmed
Xcode is signed in and has been given the exact Signing & Capabilities steps. This is
not an app compilation failure or an independent device pass.

Still required:

1. Generate the test-runner profile in signed-in Xcode, then run the physical state matrix
   at normal/largest Dynamic Type using the private fixture relay.
2. Record the real VoiceOver walkthrough and device failure/recovery; obtain the independent
   greyscale/design review. Simulator images and the backend restart check do not replace these.
3. Complete Person Two's contract 0.5.0 review/approval, vocabulary/classifier admin contract
   and inspector work, Windows checks, and the joint staging checkpoint with both signatures.
   The admin proposal remains in `docs/handoff/phase2-admin-contract-review.md`; no unapproved
   admin endpoint, scope or staff identity was introduced.

Phase 1 carried release requirements retain their original release boundaries. No public
release, production migration, gate signature or Person Two approval is claimed here.
