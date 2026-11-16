# ADR-015: Signal, the v2 visual system

- Status: Proposed. Chosen by the project owner on 2026-11-16 from three concepts
  (`docs/design/redesign-v2-2026-11-16/concepts.md`, Signal). Needs Person Two's approval:
  `design/tokens.json` is Person Two's file (manual §10.1) and the web migration is Person Two's
  lane. Until then the tokens on this branch are a proposal, not a merged design system.
- Amends: manual §10 (design tokens) and §16.1, §16.2, §16.3 and §16.5 (anti-vibecode standard),
  as listed below. Supersedes ADR-012's visual direction. Recorded for the manual's §27 Phase 3
  amendments.

## Context

The owner judged the v1 interface (ink on paper, no brand colour, no shadows, almost no motion)
as reading "AI-generic": correct, but anonymous in a thumbnail, a feed or a pitch deck. The ask
was a look that is premium, alive and investor-grade, without giving up the honesty rules that
make PLUG trustworthy. Three concepts were drawn and measured (Signal, Tactile, Editorial). Signal
was picked because it is distinctive at thumbnail size, needs no imagery or map data (PLUG has
neither yet), and is the cheapest of the three to build in SwiftUI and Next.js.

## Decision

PLUG adopts Signal: one loud brand pink, big heavy display type, and buttons and cards drawn as
physical keys with a hard ink edge.

| Role | Token | Value |
| --- | --- | --- |
| Signal (primary actions, brand surfaces) | `color.signal.500` | `#FF2E8B` |
| Deep (pink text and accents on light surfaces) | `color.signal.deep` | `#B5064C` |
| Cream page | `color.paper` | `#FFF4EC` |
| Card | `color.card` | `#FFFFFF` |
| Ink | `color.ink.900` | `#15110F` |
| Error | `color.alert.600` | `#B3261E` |
| Truth labels (text on surface) | `color.truth.*` / `color.truthSurface.*` | Confirmed `#0E7A43` on `#DDF3E6`, Recent `#0B6E7A` on `#D5EEF1`, Estimated `#7A4E00` on `#FBE9BE`, Unknown `#4F4A45` on `#ECE8E4` |

Key pairs (WCAG 2.x, guarded by `tests/contracts/tokens-contrast.test.mjs`): ink on Signal
5.38:1, ink on cream 17.34:1, deep on cream 6.27:1, white on deep 6.78:1, error on cream 6.04:1,
Confirmed 4.64:1, Recent 4.92:1, Estimated 6.00:1, Unknown 7.19:1. White on Signal is 3.49:1,
so white or card text on Signal pink is banned.

### Rules relaxed

1. **A brand colour exists** (amends §10's "nothing is coloured to signal a brand" and §16.5
   "the primary action is ink"). Signal pink fills primary actions and brand surfaces (the home
   field, the app icon background). Pink text on a light surface uses `signal.deep`. Pink never
   says anything about an answer: it is not a truth colour, a status, a chart colour or an error.
   Secondary actions stay ink.
2. **Elevation is a hard keycap edge** (amends §16.5 "there are no shadows" and the token rule
   "elevation is brightness"). Keys carry a solid ink edge of `elevation.keyEdge` (4 px) that drops
   to `elevation.keyEdgePressed` (1 px) when pressed; cards carry `elevation.cardEdge` (2 px). The
   edge is an offset solid shape, never a blurred or soft shadow, so §16.1 "excessive shadows and
   floating elements" and §16.2 "the same soft grey shadow under every card" still apply.
3. **Richer motion** (amends §16.5 "motion is brief"). Allowed: springs on keys
   (`motion.spring.key`) and sheets (`motion.spring.sheet`), an 80 ms press (`motion.press`),
   live rings on the people being asked (`motion.rings.node`, 1.8 s loop) and on the home field
   (`motion.rings.home`, 4 s), offers arriving with a rise and scale, and haptics (light impact on
   press, success on the first offer). Rings loop only while a real ask is waiting on real people.
4. **A display typeface** (amends §16.5 "iOS uses Apple system typography; web uses Public Sans").
   Bricolage Grotesque (SIL OFL 1.1, `design/fonts/bricolage-grotesque/`) is the display face on
   both platforms (`type.family.display`). iOS body text stays SF Pro so Dynamic Type works
   unchanged; the web body face is Person Two's call during the migration.

### Rules kept

- Truth labels and their reserved colours: the four truth colours are never used for buttons,
  charts, brand or decoration. Chips carry an icon, a word and a 2 px border (solid for known
  states, dashed for Unknown and Not verified); colour is never the only cue.
- Never a number the server did not send (§16.4). The asking rings show only nodes the server
  reported; no invented counts, reviews or proof.
- A web answer never looks like a human answer: hatched fill, dashed border, "from the web" copy;
  never promoted to Confirmed, Recent or Estimated.
- Test mode is disclosed on every screen (the ink tab under the status bar).
- WCAG AA contrast, verified by test rather than assumed; 3:1 for control borders (1.4.11).
- 44 pt minimum touch targets.
- Reduce Motion: no springs, loops or travel. Rings become static, sheets and cards cross-fade over
  `motion.fast`, and keys show the pressed state by colour only.
- No gradients, gradient text, glassmorphism, grain, pill buttons, emoji in headings or untouched
  kit defaults (§16.1, §16.2). No fake proof or generated people (§16.4).
- One radius never fits all: radius still rises with the size of the element.

## Consequences

- `design/tokens.json` changes values under the same keys (paper, ink, rule, truth, alert) and adds
  `color.signal`, `elevation.keyEdge`, `elevation.keyEdgePressed`, `elevation.cardEdge`,
  `type.family.display`, `motion.press`, `motion.spring.key`, `motion.spring.sheet` and
  `motion.rings`. Every screen that reads tokens changes colour at once on both platforms; the
  frozen Phase 0 and 1 screens follow through their aliases without code edits.
- The app icon becomes the ink mark on Signal pink (dark: Signal-pink mark on ink). The mark and
  logotype stay ink.
- iOS must bundle the font (UIAppFonts) and add key, card, ring and sheet components; screen work
  follows in `ios/Plug/Features`.
- Person Two migrates the web: load `web/src/app/fonts/bricolage-grotesque-variable.ttf` with
  `next/font/local`, adopt the new tokens, rebuild buttons and cards as keys, and re-run the §16.8
  design gate and browser tests on every page. Until that lands, the web shows the new colours on
  the old components.
- Risk: pink plus thick outlines can read as playful for money-adjacent asks, and neo-brutalism is
  trend-adjacent. The discipline above (pink only for actions and brand, truth system untouched) is
  what keeps it from ageing quickly or undercutting trust.
- Error red and Signal pink are near in hue (29 against 1). Errors always carry an icon and the
  word "Error", and pink is never used as text on light surfaces.
- No gate is passed by this decision; the §16.8 design gate runs on each rebuilt screen.
