# PLUG visual redesign, 2026-11-15

Branches: `p3.ui-one-redesign` (iOS, Person One) and `p3.design-two-redesign` (brand, tokens, web, tests; Person Two to review). Every image below is BEFORE on the left and AFTER on the right. The screenshots come from `evidence/redesign/2026-11-15/before` and `after`. iOS shots are scaled to 390 px wide, web 1280 shots to 960 px; where one side is taller, the shorter side is padded with paper.

## 1. What changed and why

The owner chose direction C, "Nearby", on 2026-11-15 from the three directions in [directions.md](directions.md). The idea: PLUG puts you in the middle of real people near you. The visual changes follow from that: warm paper neutrals, a new mark and logotype, one shared set of iOS components, flatter screens with fewer boxes, and small physical motion. The problems the redesign set out to fix are listed in [before-critique.md](before-critique.md).

The manual rules did not change. Colour is still evidence: ink for the primary action and the mark, saturated colour only in the four truth labels and alert. One type family per platform, the 4/8/12/16/24/32/48/64 spacing scale, radii 7/9/12/20, no shadows, no gradients, no pill shapes, no dark mode in V1. Every motion stops under Reduce Motion and `prefers-reduced-motion`. No truth label, score, price or count is set on the client.

## 2. Brand

![Logo sheet](logo-sheet.png)

The mark is a solid P whose counter holds a dot: the dot is you, and the ring of space around it is the people nearby. The circle is used for one meaning only across the product, a person. Brand files and their notes: [design/brand/README.md](../../../design/brand/README.md) (on the brand branch, `p3.design-two-redesign`). The mark still needs a trademark search (section 10).

## 3. Tokens

Source: `git diff 8631357 -- design/tokens.json`.

- **Palette.** Every colour is re-derived from OKLCH (warm neutrals at hue 92). Paper `#F1F3F0` to `#F4F1E8`, sunk `#E8EBE6` to `#E9E5DB`, ink.900 `#161A17` to `#19160D`, ink.600 `#4D544E` to `#535044`, ink.400 `#7C8480` to `#6C695E`. Truth, truth surface, truth border and alert colours were re-derived on the same basis. Every text pair passes AA; `tests/contracts/tokens-contrast.test.mjs` checks this. Values and ratios: [contrast.md](contrast.md), [palettes.json](palettes.json).
- **`color.rule.control` `#89867C`.** New. Field and control borders, 3:1 or better against card and paper (WCAG 1.4.11). Before, fields used `rule.300` at about 1.7:1.
- **`color.ink.950` `#0B0905`.** New. The pressed fill of the primary button.
- **`layout.*`.** New. Page 1200, measure 640, narrow 480, read 496, index 240, auth column 320, launch mark 256, icon sizes 18/20/22/25/28, logo 22 and 48, dot 10, portraits 44/48/64/88, tab reserve 96, state minimum height 96. These replace literal numbers in the Swift and CSS code.
- **`type.hero`.** New. 56/58, weight 700, tracking -1.6, for the web hero.
- **Motion.** `fast` 120 to 150 ms, `base` 180 to 240 ms, `slow` 240 to 350 ms. New: `reveal` 1100 ms, `motion.mark.*` (dot 240, ring delay 200, ring 400, body delay 450, body 650) and `motion.spring` (response 0.35, damping 0.82). The reduced-motion note now says the logo shows its final frame.
- **Rules added to the token notes.** A circle means a person, never decoration and never a count the server did not send. Field and control borders use `rule.control`.

## 4. Motion spec

**Launch and hero reveal** (`PlugMarkAnimated` on iOS, `.mark-anim` in `web/src/app/globals.css`):

| Part | Start | End |
| --- | --- | --- |
| Dot (you) appears | 0 ms | 240 ms |
| Ring of people forms around the dot and fades | 200 ms | 600 ms |
| The P closes around both | 450 ms | 1100 ms |

- iOS: the `LaunchSplash` overlay starts where the static launch screen ends (paper, the mark at 256 pt). It waits `reveal - fast` (950 ms), then fades out over `base` (240 ms), so it is gone at about 1.19 s. It takes no touches and no VoiceOver focus.
- The splash is skipped under Reduce Motion and in UI tests (launch argument `-plug-ui-test-reset`).
- Web: the hero mark plays once on load. Under `prefers-reduced-motion` it is static and shows the final frame.

**Interaction motion:**

- One token spring, response 0.35 and damping 0.82 (`Animation.plug`), and none under Reduce Motion.
- Buttons and chips scale to 0.98 when pressed and change fill or label colour; opacity never changes.
- An offer the server just reported moves up 8 pt while it fades in. Field focus borders animate on the same spring.
- `PeopleProgress` fills a person's circle with the spring only when a server update says that person replied.

**Recorded exception:** the launch reveal's P uses a spring with a 0.65 s response (`motion.mark.body`), longer than the 0.35 s interaction spring. It runs once, on cold start, and never under Reduce Motion.

## 5. iOS

Source: commit `966d27e` (7 files: `PlugApp.swift`, `PlugTokens.swift`, `CodeEntryView.swift`, `ConsentNotice.swift`, `WelcomeView.swift`, `AskView.swift`, `ProviderView.swift`). No new Swift files; the shared components live in `ios/Plug/Core/DesignSystem/PlugTokens.swift`:

- `PlugButtonStyle`: primary (ink fill), secondary (card with control border), tertiary (text), destructive.
- `PlugTextField`: permanent label, 3:1 border, 2 pt ink border when focused, error below.
- `PlugDivider`, `PlugChip`, `PlugDeadlineTag`, `PlugNotice` (one named state with at most one action, neutral or alert).
- `PeopleProgress`: one circle per person contacted, filled when they replied, always next to the server's count sentence.
- `FlatToolbarButton`: one flat 44 pt trailing toolbar symbol, with the iOS 26 glass circle turned off.
- `PlugMarkAnimated` and `PlugLogotype`: the new mark and the drawn logotype (VoiceOver reads "PLUG").

### Home

![Home, default text size](compare/ios-visual-home-default.png)
![Home, largest text size](compare/ios-visual-home-largest.png)

- The stock photo card ("A little inspiration", "Look good. Feel like you.") is removed.
- The four category icons become a 2 by 2 grid of secondary buttons with icon and label; one column at accessibility sizes. Their test identifiers are kept.
- Subtitle "Local skills. Real connections." becomes "Ask for a service, or about a place nearby." The provider card title "Your skill. Someone's solution." becomes "Do you offer a service?".
- The composer clear button is a plain cross, not a filled circle (a circle means a person). The field border uses `rule.control`.

### Service ask: progress and results

![Results](compare/ios-results-default.png)
![Results, largest text size](compare/ios-results-largest.png)
![Progress](compare/ios-progress-default.png)

- The three stat tiles (Notified, Replied, Offers) and the progress bar are replaced by `PeopleProgress` and the sentence "3 notified, 1 replied".
- The trailing glass refresh button becomes a flat toolbar symbol. The system back button is kept.
- Sort options use `PlugChip`; the deadline uses `PlugDeadlineTag`.
- Provider portraits beside an offer are 44 pt circles, so the price stays the largest thing on the card.

### Offer and business detail

![Offer detail](compare/ios-offer-detail-default.png)
![Offer detail, largest text size](compare/ios-offer-detail-largest.png)
![Business detail](compare/ios-business-detail-default.png)

- Offer detail is one card led by the price and truth badge, then the provider, then value rows (Earliest, Away, Where to find them, Offer ends), divided rather than boxed separately. The 220 pt photo banner is removed.
- The score is never invented: when the server sends a scored state without a value, no score line is shown. Before, it showed "Score 0".
- At accessibility sizes the price always stacks above its badge.
- "Demo offer · Booking isn't available yet." becomes "Demo offer. Booking isn't available yet." (middle dots removed across the app).

### Ask outcomes

![Empty](compare/ios-empty-default.png)
![Stopped](compare/ios-stopped-default.png)
![Clarification](compare/ios-clarification-default.png)
![Restricted](compare/ios-restricted-default.png)

- No offers, Unknown, stopped and error states all use `PlugNotice`. The error notice keeps the support reference and "Retry update".
- "Offer this service" on the empty state is a text button, so "Ask something else" stays the one primary action.
- Clarification answers are secondary buttons.

### Place questions

![Place asking](compare/ios-place-asking-default.png)
![Place answered](compare/ios-place-answered-default.png)
![Place web answer](compare/ios-place-web-default.png)
![Place unknown](compare/ios-place-unknown-default.png)

- Asking: `PeopleProgress` with "N notified, N opened, N answered" replaces the three tiles.
- Answered: each person who answered is shown as initials in a circle with the time.
- The web answer is set smaller and in ink.600, so it reads quieter than any human answer. It keeps its dashed border and "Not verified" badge.

### Provider

![Provider setup](compare/ios-provider-setup-default.png)
![Inbox](compare/ios-inbox-default.png)

- Buttons use `PlugButtonStyle`; the licence field shows its error through `PlugTextField`.
- Copy: "Photo, about & links · Optional" becomes "Photo, about and links. Optional."; "Add one skill at a time · 3–40 characters." becomes "Add one skill at a time, 3 to 40 characters.".
- Inbox: travel area, licence and hours are plain value pairs, not grey tiles.

### Welcome and sign-in

Not in the composites (no matching before shots). After shots: `evidence/redesign/2026-11-15/after/ios/signin`.

- The logotype is the drawn artwork. "Ask for a service, or about a place nearby." leads, and the tested tagline "Real-time truth. Better local decisions." follows, unchanged.
- "I have an account", "Continue as guest" and the other text actions use `PlugButtonStyle`.
- "Private testing · Review the notices before continuing." becomes "Private testing. Review the notices before continuing.".

## 6. Web

Source: commits `0bdfbd9`, `69247e0`, `559ce28`.

### Home

![Home at 1280](compare/web-home-1280.png)
![Home at 360](compare/web-home-360.png)

- The logo is the drawn logotype as inline SVG. The link has a visually hidden "PLUG home" name, not an `aria-label`.
- The hero mark plays the reveal once (section 4). The hero uses `type.hero`.
- The lede says what the private test does today, including that place questions show Unknown.
- "How it works" is one numbered sequence. Each step shows what happens to the same worked example. Sections are separated by surface bands, not hairlines. Overlines are removed.

### Support and Privacy

![Support at 1280](compare/web-support-1280.png)
![Support at 360](compare/web-support-360.png)
![Privacy at 1280](compare/web-privacy-1280.png)
![Privacy at 360](compare/web-privacy-360.png)

- The "Private-test draft" overline and the "Starter draft · date" lede are replaced by one date line, "Dated September 30, 2026.".
- Text runs at `layout.read` (496 px). The page index stays on wide screens.
- "Back to home" is a text link, not a second button.

### Admin login and 404

![Admin login at 1280](compare/web-admin-login-1280.png)
![Admin login at 360](compare/web-admin-login-360.png)
![Not found at 1280](compare/web-not-found-1280.png)
![Not found at 360](compare/web-not-found-360.png)

- The "Admin" and "404" overlines are removed.
- The closed admin page gains a "Back to home" link. The 404 page drops its second link, "Contact support", and keeps one action, "Back to home".
- Fields use `rule.control` borders.

## 7. Accessibility checks

- axe: 0 violations across 60 runs (`evidence/redesign/2026-11-15/after/web/axe-report.json`).
- Line length on web text is 76 characters or fewer.
- AA contrast for every text pair: `tests/contracts/tokens-contrast.test.mjs`.
- Field and control borders at 3:1 or better (`rule.control`).
- Touch targets at least 44 pt.
- Dynamic Type: every iOS state is captured at the default and largest sizes (`after/ios/*-largest.png`).
- Truth badges in greyscale: `after/ios/greyscale`, to show the badge text carries the meaning without colour.
- Reduce Motion and `prefers-reduced-motion`: no launch splash on iOS, a static hero mark on web, and no springs.
- VoiceOver: `PeopleProgress` reads "Notified N" then the other counts; the logotype reads "PLUG"; the web logo link reads "PLUG home".

## 8. Reviews and tests

These are reviewer verdicts from this session. They are not a phase gate. A gate is passed only by both people, together, on real staging.

| Review | Result |
| --- | --- |
| Design gate, web | Round 1 FAIL (6 findings), round 2 FAIL (2), round 3 PASS |
| Design gate, iOS | Round 1 FAIL (5 findings), round 2 PASS |
| Security | PASS |
| Contract | PASS |

| Tests | Result |
| --- | --- |
| Contracts | 594 of 594 pass |
| iOS unit | 67 run, 0 failures, 1 skipped (needs a live backend) |
| iOS request UI tests | Pass |
| `SignInScreenshotTests` | 2 failures at line 186. They also fail on the pre-redesign baseline `85be0a5`; they need a sign-in backend. |
| Web end-to-end | 150 of 150 pass |

## 9. Decisions recorded

- The system back button is kept on pushed screens (platform exception to the flat toolbar).
- Chip radius is 7 (`radius.badge`).
- The home category tiles are kept, because the UI tests find them by identifier.
- Provider portraits are round, because a provider is a person.
- The "Contact PLUG:" link on `/support` is kept, because a test depends on it.
- `layout.read` is 496.
- The launch splash is skipped in UI tests.
- No new Swift files; the components are added to `PlugTokens.swift`.

## 10. Not done and open

- SwiftLint was not run locally. The 5 enabled rules were checked by grep only.
- The `/impeccable`, `/hallmark` and `/humanizer` skills are not installed; substitutes were used.
- The mark needs a trademark search. P-with-a-dot marks exist.
- Person Two must review the brand, tokens, web and tests PR.
- WEAK notes are left for Person Two: the empty right track on web home at 1280, and the height of the truth-labels intro.
- Pre-existing screenshots are missing, so no comparison was made for: `visual-examples-default`, `empty-offer-gap-default`, and the largest-text sign-in states.
- No check on a physical device. The owner is not using the iPhone until the project is done.
