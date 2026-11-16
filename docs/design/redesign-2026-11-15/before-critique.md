# BEFORE critique, merged and ranked

2026-11-15. Sources: plug-design-gate (manual §16.8, §16.1-16.6), the apple-design lens, and the six reference studies in [references/](references/). The `/impeccable` skill is not installed, so web-design-guidelines and the gate covered web. The iOS screens reviewed are the 2026-11-14 UI-pass captures in `evidence/ui-pass/`, the latest build of `p3.ui-one-ios-polish`.

Gate verdict on the current screens: **FAIL**, with 7 rule failures, 15 weaknesses and 2 passes.

## Ranked findings (most visible first)

| # | Verdict | Surface | Where | Finding | Redesign fix |
| --- | --- | --- | --- | --- | --- |
| 1 | FAIL | iOS | home, AskView.swift:244 | A stock photo of a stylist and client stands in for real people (§16.4) | Remove it. Show the product's own worked ask instead |
| 2 | FAIL | iOS | home, AskView.swift:109,120,248 | Buzzword taglines ("Local skills. Real connections.", "Look good. Feel like you.") | Plain words. Keep the tested strings and rewrite the untested ones |
| 3 | FAIL | iOS | answer pages, AskView.swift:459-470 | Default iOS 26 glass toolbar circles with a soft shadow (§16.1, §16.2) | Flat ink toolbar buttons from tokens |
| 4 | FAIL | iOS | results, AskView.swift:536-538 | Three counter tiles read as a stat display. "Offers 1" comes from the server's `offersReady` and sits next to a headline that counts the list | Replace the tiles with one server sentence. No change to data sources |
| 5 | FAIL | web | support, privacy, terms | Middle-dot meta string "Starter draft … · September 30, 2026" (§16.1) | A sentence plus a separate date. The tested phrase "For private-test review" stays |
| 6 | FAIL | iOS | home, AskView.swift:130 | Middle-dot meta "Private preview · Example offers." | Two sentences |
| 7 | FAIL | web | globals.css | Hand-typed weights, widths and `color-mix` badge borders instead of tokens (§16.5) | Layout and weight tokens; badges use `truthBorder.*` |
| 8 | WEAK | iOS | home, AskView.swift:218-236 | Four grey icon tiles in a row: the template look | Example asks as text, or the C "well" pattern, with no decorative boxes |
| 9 | WEAK | web | home | A 34/20/15 ramp makes 1280 px read like documentation. The lede mixes steps | A deliberate display/title/body ramp, each on its own line height |
| 10 | WEAK | web | globals.css:335 | `band-muted` equals paper, so sections are separated only by hairlines | Real surface steps: a full-bleed band change instead of boxes (taste A) |
| 11 | WEAK | web | page.tsx, legal-page.tsx, 404, admin | A label sits above every heading | Cut them |
| 12 | WEAK | web | page.tsx:85-94 | The three-up ruled columns are a template | One worked example: ask, then parse, then result |
| 13 | WEAK | iOS | offer detail | Four identical cards, a 72 pt initials circle above the price, distance shown twice | Lead with the value. Merge the cards |
| 14 | WEAK | iOS | place web answer | The dashed web card outweighs the human "No answers" card | The web card steps down in size and weight |
| 15 | WEAK | web | support | Five competing actions | One action and one note |
| 16 | WEAK | web | admin-login, 404 | Content floats at the top of an empty page with no route | Centre it and give it one route |
| 17 | WEAK | iOS vs web | wordmark | iOS uses SF Rounded Heavy, web uses Public Sans 700 | One drawn wordmark (SVG paths) on both |
| 18 | WEAK | iOS | many files | Icon sizes, image heights and widths outside tokens | Size tokens |
| 19 | WEAK | iOS | empty state | Two actions compete | One |
| 20 | WEAK | all | field borders | `rule.300` field borders are about 1.7:1 and fail WCAG 1.4.11 | New `rule.control` token at 3:1 or better |
| 21 | WEAK | iOS | launch | The launch screen is a static asset with no brand moment | Animated reveal on launch only, static under Reduce Motion |
| 22 | WEAK | brand | design/brand | `generate-brand.mjs` is broken against the v4 tokens. No favicon set, manifest or OG image. README is stale v3 text | Rebuild the brand pipeline and README |
| 23 | PASS | both | truth system | Filled versus dashed badges are correct and legible in greyscale. Ink primary, no gradients or pills | Keep |
| 24 | PASS | web | header and focus | The focus ring is ink with a 2 px offset, and targets are 44 px | Keep |

## Apple-design lens (iOS)

- Motion is almost absent: fades only, and default push and sheet transitions. Add small, physical, interruptible state changes (spring, 150-350 ms) for the composer, offers arriving and badge state, with none when Reduce Motion is on.
- Depth comes from glass toolbar defaults rather than from the system the manual specifies (brightness). Remove the glass and use a brighter surface for raised content.
- Typography is system-correct but flat. The value headline (price, wait) should carry the screen, per manual §16.5 and the "number is the headline" principle from Transit.

## What not to fix in this redesign

Data sources, counts and copy owned by tests or models stay as they are. Finding 4 changes presentation only.
