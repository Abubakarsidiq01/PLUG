# Phase 2: any service, Claude extraction and the blueprint design

Owner decisions on 2026-10-01: PLUG serves any lawful service (ADR-009), with Claude
extracting the request and real nearby businesses from Apple Maps when no participating
supplier covers it. The interface must follow the manual's own design system (§9–§11,
§16, Figures 7, 8, 10 and 14), not an invented look.

## What changed

- **Contract 0.4.0 (proposed):** free-form `category` with `service_name` and
  `search_terms`, `time_zone`, budgets $5–$5,000, no unsupported-category refusal.
  `V5__open_service_scope.sql` is expand-only.
- **Backend:** `IntentAdapter` covers any service. Rules parse "$45", "45 dollars", "$1,200",
  "tomorrow", "tonight" and "within 5 miles" in the person's time zone, and a service
  dictionary is the fallback. `ClaudeIntentProvider` uses the official Java SDK with a strict
  JSON schema, low effort and a 6-second deadline. Its output is untrusted and validated, and
  it is used only when `ANTHROPIC_API_KEY` is set. Clarification options are stored per request.
- **iOS, Figure 10 flow:**
  - Screens: home prompt with popular examples; "New request" composer with a labelled
    field and budget, time and distance chips (§9.1); searching steps driven only by server
    status and counts; "Top options" offer cards (Figure 8); offer detail.
  - Nearby businesses come from Apple Maps under UNKNOWN badges.
  - Only Figure 7 tokens are used, together with the full type scale, flat 1px cards, 6px
    chips, uppercase truth badges and one primary action per screen.
  - Removed: decorative icon grids, a large hero, an invented warm palette and em-dash copy.
- **iOS fixes found during this work:**
  - The request lifecycle was attached to the root page, so pushing the composer marked a
    new request as stale. It is now attached to the navigation stack.
  - The multi-line field had no way to dismiss the keyboard, so a keyboard Done button was added.
  - Stacked rows were centred at the largest text size and are now left-aligned.
  - A truth-badge case bug was fixed.
  - Location chips no longer use a non-existent SF Symbol.
- **Website (Figure 14, §15):** rebuilt by a dedicated agent. Results are listed below.
- **Blueprint:** ADR-009 was added and the P2-ONE and P2-TWO outcomes, steps and exit
  criteria were amended. The request grammar, the contract changelog and the labelled
  dataset (46 vectors) were updated.

## Verification (2026-10-01)

| Check | Result |
|---|---|
| Backend unit, database (PostGIS, incl. V5 and 46-vector dataset), Checkstyle, JAR | Passed |
| Contract, fixture and dataset checks | 135 passed, 0 failed |
| Web typecheck, lint | Passed |
| Spectral (CI settings) | No findings |
| Live API suite, fresh isolated backend | 879 checks passed, 0 failed, 250 exchanges |
| Phase 2 Bruno collection | 39/39 requests |
| iOS unit tests incl. live sign-in | 58 passed |
| iOS screenshot UI tests, default and largest Dynamic Type | 2/2 passed; 20 screenshots in `evidence/P2/simulator/2026-10-01/` |
| Website (agent): typecheck, lint, build, Playwright incl. axe at 360/768/1280 | 81/81 passed |

Shoe-repair end-to-end check against the phone backend:

- **Input:** "I need to repair my shoe for 45 dollars tomorrow, who is available?"
- **Extracted:** `shoe_repair` (Shoe repair), $45.00, 23:59 tomorrow America/Chicago, search
  terms "shoe repair" and "cobbler".
- **Outcome:** with no participating supplier, it ends `no_coverage`.

The verification exposed two QA problems, both fixed:

- **Stale expectations.** The live suite and Bruno still expected old-scope results
  ("$1,000" and "$500.01" rejected; "plumber" not an option).
- **A masked failure.** `phase2-verify-all.sh` piped the live suite through `tail`, which
  hid a failure. It now fails the run.

Two earlier screenshot runs failed with XCUITest infrastructure timeouts ("Timed out
while synthesizing event" and "Timed out while loading Accessibility"). Those runs overlapped
device builds and backend restarts while the load average was 41. The same suite passed
cleanly on a quiet machine, so no app change was made for those timeouts.

## Not claimed

- **Claude:** no Anthropic key is configured, so Claude extraction is untested against the
  live API. The rules handled every case shown here.
- **Device evidence:** the physical-device screenshot matrix and the VoiceOver walkthrough
  need the owner's phone.
- **Process:** Figma parity, Person Two's Windows run, contract approval and the joint
  checkpoint are outstanding, and there are no G2 signatures.
- **Website legal text:** the website agent flagged that the Privacy Policy draft still says
  no AI or maps processing occurs, which ADR-009 makes untrue. That needs a legal update
  before anyone relies on it.
