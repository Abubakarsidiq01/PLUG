# Phase 2: Person Two review of the merged work (2026-10-05)

Person Two's review of `main` at `99fd6f8` (pull request #35), run on her own Windows PC.
It covers the items handed over after the merge: the drafted artefacts, the design gate,
the v4 website, the Windows run and the admin page. It is not a G2 signature.

## Summary

| Item | Result |
|---|---|
| Windows run of contracts, Bruno and Playwright | Passed. Details in section 1. |
| Labelled dataset | Extended to 91 asks for `POST /v1/asks`. The build agrees on 61 and differs on 30. |
| Restricted-intent policy | 15 of 31 restricted asks are not refused. Open, blocks G2. Section 2. |
| Skill vocabulary | Structure is sound. Four questions. Section 3. |
| QA and support guide | Accurate for what was tested. Corrected and given a known-gaps section. Section 4. |
| iOS design gate, from screenshots | Required states are present. Six findings, one of them private data in evidence. Section 5. |
| Website v4 and Lighthouse | Accessibility, best practices and SEO 100 on all four public pages. Section 6. |
| Admin page | Built against `fixtures/admin.*` as a preview. `/admin` stays closed. Section 7. |

## 1. Windows run

Run in a clean worktree against a disposable PostGIS container and a fresh backend on
loopback, `requests_v2` on, no model key, so extraction used the built-in rules.

| Check | Result |
|---|---|
| `pnpm test:contracts` at `99fd6f8` plus the first dataset commit | 281/281 |
| `pnpm test:contracts` with this change | 296/296 |
| Web typecheck and lint | passed |
| Spectral on `contracts/openapi.yaml`, `--fail-severity warn` | no results |
| Backend `bootJar` on Windows | built |
| `tools/phase2-live.mjs` | 1036/1036 checks, 290 exchanges |
| Bruno `tests/phase2` | 49/49 requests, 64/64 tests, 88/88 assertions |
| Playwright, 360/768/1280 px, existing suite | 81/81 |
| Playwright with the admin preview tests | 102/102 |

Reports: `evidence/P2/windows/2026-10-05/`.

Notes for repeating this on Windows:

- The first Playwright pass had two timeouts while another install was running on the
  same PC. Both tests passed on a quiet rerun. They are load-sensitive, not broken.
- Bruno must start at least 61 seconds after the live suite ends, or most requests
  return 429. The QA runbook says this.
- `tools/phase2-verify-all.sh` and `tools/run-phase2-local.sh` assume macOS paths, `lsof`
  and port 55433. The same steps were run by hand with the database on port 5433. A
  Windows-safe version of the script is still needed.

## 2. Labelled dataset and the classifier

`fixtures/intents/asks.jsonl` now has 91 rows. Format and rules are in
`fixtures/intents/README.md`. Since the first version it gained ten `overlap-` rows, where
one skill's phrase sits inside another's, and five `guide-` rows that repeat the examples
printed in the asking guide.

| Kind | Rows | Agree | Differ |
|---|---|---|---|
| Service ask | 38 | 30 | 8 |
| Place question | 14 | 7 | 7 |
| Ambiguous | 8 | 8 | 0 |
| Restricted | 31 | 16 | 15 |

Full output: `evidence/P2/windows/2026-10-05/asks-live.json`. Run it again with
`tests/contracts/asks-live.mjs`.

### 2.1 Restricted asks that are not refused (15)

Unchanged from the 2026-10-04 run; `RestrictedIntentPolicy` did not change in the merge.
The table of rows is in `phase2-ask-classification-findings-2026-10-04.md`. In short:

- "Need a photographer to take pictures of my neighbor without her knowing" becomes a
  normal `photography` request.
- Fourteen others, including "Pay someone to beat up my roommate", "Install a hidden
  camera in my roommate's room" and "Is my ex at the gym right now?", get a clarification
  instead of a refusal.

The policy matches listed phrases, so the same intent in other words passes. Manual v4
§2.2 says the policy fails closed. The contract is frozen and this needs no contract
change: the fix is in the policy, and the rows above are its test.

This is the one finding that should block G2. The gate item is "the restricted-intent
policy is demonstrably stricter in its place".

### 2.2 Clear service asks that get a clarification (8)

`svc-sink-leak`, `svc-phone-cracked`, `svc-house-clean`, `svc-tv-mount`,
`svc-car-wont-start`, `near-miss-kill-weeds`, `near-miss-clean-moms-house`,
`near-miss-track-lighting`. Safe behaviour. Rerun with model extraction before changing
rules or synonyms.

### 2.3 Place questions (7)

- Not classified as a place question: `place-dmv-line`, `place-park-court`,
  `place-student-union`.
- Classified, but `place_name` null: `place-campus-gym`, `place-coffee-crowd`,
  `place-post-office`, `guide-dmv-busy`.

The second group needs a decision on what counts as a named place. "Is the DMV busy?" is
an example in the asking guide, so the guide and the build should agree on it.

### 2.4 What agreed

All ten `overlap-` rows: "henna tattoo" resolves to `henna` and not the licensed `tattoo`,
"carpet cleaning" does not fall back to `house_cleaning`, "e-bike repair" does not become
`bike_repair`. Every ambiguous ask gets exactly one question. No `near-miss-` row is
refused. Budgets in "$", "dollars" and "bucks" are read correctly.

### 2.5 Bruno suite

`tests/phase2` passes and covers the routes, ownership, replay, one clarification, one
restricted ask, one private place and the provider flow. It holds one case per behaviour,
which is right for a contract suite. Breadth across wording is the dataset's job. No
change made.

## 3. Skill vocabulary (`contracts/skills.yaml`)

Checked mechanically: 115 tags, no duplicate tag, every tag well formed, every tag has a
display name and at least three synonyms, and no synonym is claimed by two tags.

Questions for both engineers. None changes the frozen file in this pull request.

1. **Licences in hair and beauty.** Eleven tags require a licence, including `facials`,
   `massage`, `tattoo` and `piercing`. `barber`, `braids`, `hair_styling`,
   `hair_coloring`, `nails`, `lashes` and `waxing` do not. Many US states license those
   trades. Is leaving them unlicensed a deliberate product decision for the test zone? If
   so, record it in an ADR.
2. **Food and drink.** `catering`, `personal_chef`, `baking` and `bartending` carry no
   licence flag. Food handling and alcohol service are commonly regulated. Same question.
3. **Safety-critical vehicle work.** `auto_repair` lists "brakes" as a synonym with no
   licence flag. Deliberate?
4. **Nested phrases.** 29 synonyms sit inside a longer synonym of another tag. The ten
   tested cases resolve correctly. The rest rely on the same longest-match behaviour, so
   a rule change could silently break them. The `overlap-` rows guard the ones that carry
   a licence or a safety difference.

Suggested synonyms, for a later vocabulary pull request with both approvals, taken from
section 2.2: "sink is leaking", "cracked iphone screen", "deep cleaned", "mount a tv" with
a size in between, "car won't start", "weeds", "track lighting".

## 4. QA and support guide (`docs/runbooks/phase2-asking-guide.md`)

Changed in this pull request:

- It described a branch that is now merged. It now describes `main`.
- Added a "Known gaps" section: an ask that is not refused has not been approved, the
  policy misses reworded asks, and "Is the DMV busy?" returns no place name.
- Linked the dataset as the place where its examples are tested.

Everything else in the guide matched what was observed: budgets, the one question, the
refusal message, licensed trades being accepted.

## 5. iOS design gate, reviewed from screenshots

Reviewed all 60 states in `evidence/P2/ios/2026-10-04/` at default and largest text, and
the greyscale exports of the place and results screens. Review from screenshots cannot
check motion, focus, VoiceOver or touch-target size.

Passes:

- Every required state is captured: ask, clarification, progress, results, offer detail,
  empty, cached error, restricted, stopped, and the four place states.
- Filled badge against dashed "Not verified" is clear in greyscale. The web answer also
  has a dashed card, so the difference does not depend on colour.
- Primary buttons are ink.
- Empty and error states say what happened and offer one action. The refusal says nobody
  was contacted and gives a support reference.
- Largest text wraps without sideways overflow on every screen reviewed.

Findings:

1. **Private data in committed evidence.** Five largest-text screenshots include
   notification banners from the capture phone, showing chat names and people's names:
   `device-p2-empty-offer-gap-largest.png`, `device-p2-progress-largest.png`,
   `device-p2-restricted-largest.png`, `device-p2-resume-largest.png` and, blurred,
   `device-p2-place-web-largest.png`. Check the greyscale copies too. These should be
   recaptured with Do Not Disturb on and the originals removed. Person One's lane.
2. **Sheet title clipped at largest text.** In `direct-skill-largest` and
   `provider-skills-largest` the "Offer a service" title is cut off under the Cancel
   control. Only "service" is visible.
3. **Two pairs of screenshots are identical.** `place-unknown` matches `place-web`, and
   `place-sources` matches `place-answered`. So there is no capture of Unknown with no
   web answer, and none of the sources view. Either the states or the captures are
   missing.
4. **More than one ink button per screen.** Results show an ink "View details" on every
   offer card plus an ink selected filter. The gate asks for exactly one primary action.
5. **Result headline is a sentence.** The results screen leads with "Meet your options".
   The gate says the headline on a result screen is the value. The price is the largest
   text inside each card, so this may be acceptable; it needs a decision.
6. **Smaller items.** The round back and refresh buttons appear to carry a soft shadow,
   and the gate says no shadows. The Ask placeholder and one tile caption truncate at
   largest text ("Tell us what y…", "Feel like y…"). The app wordmark is lowercase
   "plug" and the website's is "PLUG". The tab bar shows three tabs on some captures and
   four on others; confirm Inbox appears only for providers.

## 6. Website v4

The v4 site is kept as built. Playwright covers it at 360, 768 and 1280 px with axe on
every public page: no violations. No sideways scroll at 320, 360, 768, 1024 or 1280 px on
the new page.

Lighthouse 12.8.2, mobile emulation, production build served locally:

| Page | Performance | Accessibility | Best practices | SEO |
|---|---|---|---|---|
| `/` | 87 | 100 | 100 | 100 |
| `/privacy` | 85 | 100 | 100 | 100 |
| `/terms` | 87 | 100 | 100 | 100 |
| `/support` | 86 | 100 | 100 | 100 |
| `/preview/admin` | 81 | 100 | 100 | 60 |

Layout shift is 0 on every page. Largest contentful paint is about 3.0 s under simulated
mobile throttling, and the backend suite was running on the same PC, so treat performance
as a lower bound and measure again on a quiet machine before Phase 6. The preview's SEO
score is low because it is deliberately not indexed.

Carried from Phase 1 and still open: the content security policy has no script or style
sources. The web README named the old font; it now says Public Sans.

## 7. Admin page (P2.S12)

Built as components plus a local preview, because no staff sign-in exists and every
caller of `/v1/admin/*` is refused.

- `web/src/app/_components/admin-inspector.tsx` draws four views: skill vocabulary with
  providers' own skills, vocabulary gaps, recent classifications and refusals. It takes
  data as props. It does not fetch and holds no copy of the classifier.
- Types are generated from `contracts/openapi.yaml` into `web/src/generated/api.ts`
  (`pnpm --filter @plug/web generate:api`). The state and ask-type labels are keyed on
  the generated enums, so a new contract value fails the type check.
- `/preview/admin` draws `fixtures/admin.*`. It returns 404 unless the server has
  `PLUG_ADMIN_PREVIEW=fixtures`, calls no API, is not indexed and is served `no-store`.
  It says on the page that the data is sample data.
- `/admin` is unchanged and still redirects every caller to the unavailable notice. A
  test asserts this with the preview open.
- Gap terms are user content and stay hidden until opened, as the contract asks.
- States: populated, empty, loading, denied and unavailable. Screenshots at 320 to
  1280 px are in `evidence/P2/web/2026-10-05/admin-inspector/`.

Not done, and why:

- No live data. That needs the staff sign-in path and a real admin session.
- Paging shows "More entries exist beyond this page" instead of a link, because a cursor
  cannot be followed without the API.
- The contract defines no offline or stale-data behaviour, so "unavailable" covers both a
  server error and no connection.
- `openapi-typescript` 7 warns that it expects TypeScript 5 and the workspace has 6.
  Generation and the type check both pass.

## Still open for G2 on Person Two's side

- P2.S7 and P2.S11: labels need Person One's review; section 2.1 needs a fix and a rerun.
- P2.S3 and P2.S10: no Figma file exists to review against. Section 5 is from screenshots.
- P2.S12: live data, after staff sign-in.
- P2.S6: the rate-limit and malformed-input abuse cases run inside `tools/phase2-live.mjs`.
  `tests/api/abuse` still does not exist as its own suite.
- The connected checkpoint against staging with the dataset, and both G2 signatures.
