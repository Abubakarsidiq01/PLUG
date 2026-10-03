# Phase 2 hardening and temporary UI experiment

Owner-authorized review against `PLUG_Production_Master_Manual_v4.docx`, §10–12,
§16.8, §19A and §27.3. This is a local implementation review, not a G2 signature.
The design is temporary and awaits the owner's visual review. The token palette
is unchanged. Existing Phase 0/1 approvals are not reopened or extended.

## Changes

- Ask has a compact PLUG masthead, a display-sized question, a larger labelled
  composer and two grouped example lists. Provider setup uses distinct sections
  instead of putting every setting into the same card treatment.
- Result values and their truth badges stack when large text cannot fit them in
  a row. Colours, typography, radii, spacing and motion use the existing tokens.
  Key/value rows also reserve space for both columns and stack when needed.
  The web uses locally bundled Public Sans, sentence-case labels, the dashed
  Not verified badge, and copy for both ask types. Removed obsolete Apple Maps
  fallback and closed-provider-signup claims.
- Answered place questions render the supplied source initials and answer times,
  as Figure A1 requires. A shared synthetic answered fixture covers the previously
  uncaptured answer state; no live Phase 4 answer service is implied.
- Active place asks survive back navigation and cannot be silently replaced.
  Offline place results receive the same cached-state warning as service asks.
  Invalid negative/impossible place progress is rejected before rendering.
- Dictation stops when submitting, choosing an example or leaving Ask.
- Provider edits preserve untouched custom radius, availability and time zone.
  A new skill extraction replaces its previous proposal instead of accumulating
  more tags than the contract allows. Controls cannot change during a save.
  Save failures no longer claim that nothing was saved after a lost response.
- Inbox states that delivery is not connected yet; it does not claim to have
  queried an empty inbox. No fabricated request counts or truth badge.
- Matching uses wall-clock availability across daylight-saving changes. Added
  spring-forward, fall-back and midnight-boundary regression checks.
- Whitespace-only licence references cannot enable regulated matching. A
  database-backed regression checks rejection and absence of a provider profile.
- The verification script now preserves contract-test failures instead of
  replacing their exit status with `grep`'s. Evidence paths are overridable so
  this experiment does not overwrite the earlier captures.

## Verification

- Backend: 55 unit tests and 82 database tests passed; Checkstyle and boot JAR passed.
- Contracts/fixtures/dataset: 181 passed after adding the answered-place fixture. Spectral: no warnings or errors.
- Live API: 972 assertions passed across 274 exchanges on a fresh disposable
  database. `evidence/P2/security/phase2-hardening-2026-10-02.json`.
- Web: typecheck, lint and production build passed. 81 Playwright tests passed,
  including axe on all public surfaces at 360, 768 and 1280 px. Additional
  production screenshots at 320, 360, 768 and 1280 px confirm no horizontal overflow:
  `evidence/P2/web/2026-10-02/ui-experiment/`.
- iOS: 65 unit/integration tests passed, including live sign-in. Both simulator
  walkthroughs passed, with 32 screenshots. Largest text passed again after the
  final key/value layout correction. Request tests passed again with the new
  answered fixture (22 request tests). The focused answer-source capture passed
  at both sizes, bringing the collection to 36 screenshots. The first focused
  capture failed because its test locator targeted a noninteractive layout group;
  targeting the visible source heading fixed the test. No app behavior was
  bypassed. Filled/dashed greyscale specimens were exported and visually checked.

## Manual gaps that remain open

1. Contract 0.5.0 and the vocabulary still require both engineers' approval.
2. P2-TWO.S12's vocabulary/classifier admin view is missing. The current admin
   boundary intentionally denies every Phase 1 account and no admin read
   endpoints are contracted. Specify authenticated, paginated, redacted read
   schemas and an independently tested admin access path in the contract session;
   do not expose tables or ask text through a public page to bypass this gap.
3. Figma parity has no linked source file in the repository. This pass follows
   the manual and token source, not a claimed Figma approval.
4. Physical-device states, VoiceOver, an independent greyscale review, the
   Windows run, the connected staging checkpoint and both G2 signatures remain.
5. Live Claude extraction is unverified without configured credentials. The
   reproducible tests use the deterministic fallback. External red-team coverage
   of the rule-based restricted-intent policy remains required.
6. Legal copy still requires review for the v4 processing model before public
   launch; the existing starter documents are not an approved public policy.

Phase 3 Inbox delivery and Phase 4 live place answers are explicit future
capabilities, not failures to conceal with sample data. No gate was marked passed,
no account was given admin access and no production deployment was performed.

## Optional business profiles (completed after the pass above)

Owner-authorized. Codex built the feature; its credits ran out after the contract edit, before
verification, changelog and documentation. Person One completed those without changing the
implementation.

- A provider may add a business name, a short description, one JPEG thumbnail and up to five
  `https://` links. The server re-encodes the photo (≤ 48 KiB, ≤ 512 px) so EXIF/GPS metadata
  is dropped, refuses private, IP, `.local` and credentialed link hosts, and never fetches a
  link; links open only when a customer taps them. Details are provider-supplied and shown
  as such, never as verified.
- An offer carries business details only through an explicit `request_offers.provider_id`
  (migration V7), never by matching a name or a place. Offers now carry the provider's real
  score instead of a fixed `new`.
- `POST /v1/providers/skills` alone accepts 96 KiB for the thumbnail; other routes keep 16 KiB.
  Omitting `business` keeps stored details; `{}` removes them.
- Contract: `BusinessProfile` and `BusinessLink`, recorded as the 0.5.0 amendment in
  `contracts/CHANGELOG.md`. Manual v4 §27.3 now carries a "Phase 2 amendments" subsection and
  steps P2.S20–P2.S21.

Verification (`tools/phase2-verify-all.sh`, fresh disposable database, 2026-10-02):
backend 57 unit and 83 database tests; 182 contract tests; Spectral clean; live API 968 checks
over 273 exchanges; Bruno 49/49; iOS 67 tests including live sign-in; both simulator walks,
44 screenshots with greyscale copies in `evidence/P2/simulator/2026-10-02/business-final/`.
The live suite then gained four business-profile checks (https-only link refused, round trip,
omitted keeps, empty removes): 988 checks passed over 278 exchanges
(`evidence/P2/security/phase2-business-profiles-2026-10-02.json`).

## Larger skill list and own-words skills (ADR-011)

Owner decision after the business-profile work. The vocabulary grows from 35 to 115 tags
(licences on regulated trades), and a provider may keep up to five skills PLUG does not list,
in their own words. An ask that names no listed skill is matched to those providers by
keywords (one-word skills need that word; longer ones at least two). Listed skills always win,
so a licensed skill cannot be re-entered in other words; the restricted-intent policy checks
every label; a test keeps all 115 listed skills clear of that policy. The provider screen turns
unlisted words into "Your own skills" chips and has an "Add your own skill" field; the Inbox
shows own skills outlined beside listed ones. The live suite found `POST /v1/providers/skills`
returning an undocumented 422 for an unsafe label (and an undocumented 413 from the business
work); both are now in the contract with fixtures.

Verification (fresh disposable database): backend 63 unit and 84 database tests; 185 contract
tests; Spectral clean; live API 1004 checks over 282 exchanges
(`evidence/P2/security/phase2-custom-skills-2026-10-02.json`); Bruno 49/49; iOS 67 tests;
both simulator walks, 46 screenshots with greyscale copies in
`evidence/P2/simulator/2026-10-02/custom-skills/`.

## Review and reversal

The prior simulator evidence is retained alongside the new `ui-experiment/`
folder. The working changes are uncommitted for review. Local rollback source
copies are under `output/phase2-ui-experiment/baseline/`, with a sibling manifest; they exclude
the pre-existing user change to `backend/gradlew.bat`. Revert the visual experiment
selectively on request, preserving the independently useful correctness fixes.
The `ios-hardening-only/` copies retain the fixes with the prior visual hierarchy.
