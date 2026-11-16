# toogoodtogo.com (en-us)

Captured 2026-11-15 at 1440x900, one page. Cookie banner declined before capture. Screenshots kept outside the repo. Reference only: do not copy logos, names, photos, illustrations or copy.

# Design Map

## Spacing Scale
- Base 8px. Observed: 4, 8, 12, 16, 24, 32, 40, 56, 120px.
- Most frequent: 32px (24), 8px (22), 24px (18), 16px (16), 120px (11).
- Section padding: 120px top and bottom. Footer bottom padding 400px under the wordmark.
- Grid gap: 56px rows, 16px columns.

## Font Hierarchy
- Footer wordmark: ~200px, display, 900, uppercase.
- h1 hero: 72px / 72px line height, display condensed, 900, uppercase, tracking normal.
- Statement: 44px, display, 900.
- h2: 32px / 48px, body face, 400 (the most frequent size: 31 nodes).
- h3: 24px / 31.2px, display, 900, uppercase.
- Body: 16px / 24px, 400. Buttons 16px 500. Nav 14px. Legal 12px.
- Two families: condensed display (101 nodes) and a humanist body face (363 nodes). Weights 900, 500, 400 only.

## Color Palette
- #F9F3F0 warm cream surface, 71.3% of painted area.
- #00615F teal brand surface, 18%. #005250 deeper teal footer, 9.3%.
- #012625 text on light. #252D2D dark CTA when the nav sits on cream.
- #5F6D6D secondary text. #DEE3E3 muted text on teal.
- Spot only (under 1%): #67D695 mint, #FFFB9B pale yellow.
- Neutrals tinted toward teal (#5F6D6D, #DEE3E3) and warm (#F9F3F0), not pure gray.

## Image Ratios
- Hero: full bleed 1440x840 (~1.71:1), photo of a person on a teal backdrop.
- Product tiles: 1:1 at 442px, 286px, 282px.
- Bag cut-out: 1.39:1 at 1020x736.
- All images 0px radius.

## Component Tokens
- Radius: 0px photos, 120px all buttons (pill), 100% circles.
- Shadows: none anywhere.
- Buttons: large 51px tall (16px/24px padding), small 41px (12px/16px). White on teal, teal on cream.
- Grid: one 3-column grid, 321.5 / 637 / 321.5px (1:2:1).
- Nav: ~64px, transparent over hero, turns solid; background-color + backdrop-filter 240ms cubic-bezier(0,0,0.4,1).
- Buttons: background-color + color 300ms cubic-bezier(0.42,0,0.58,1). Opacity fades 500ms ease-in-out.
- :focus-visible present. prefers-reduced-motion present.
- Alignment: hero, CTA band and footer centred.

---

# Taste DNA

### Two surfaces, no containers
- **Trigger**: When grouping many content blocks on a long marketing page.
- **Decision**: Chose full-bleed swaps between a warm cream and a deep teal over cards, borders or shadows.
- **Reason**: A whole-width colour change reads as a new chapter at a glance, without the noise of boxed tiles.
- **Evidence**: 0 card candidates, 0 box-shadows; cream 71.3% and teal 27.3% of painted area; every section padded 120px top and bottom.

### A shouting voice used sparingly
- **Trigger**: When the brand needed energy without making long text tiring.
- **Decision**: Chose a condensed 900-weight uppercase display face for three roles only (h1, h3, wordmark) over one face for everything.
- **Reason**: A loud short line gets noticed; the plain body face keeps 16px/24px reading text easy.
- **Evidence**: display 101 nodes vs body 363; h1 72/72 900 uppercase; h2 drops to the body face at 32/48 weight 400; tracking normal everywhere.

### Real food, real people, square corners
- **Trigger**: When proving the product is about actual local shops.
- **Decision**: Chose unrounded photos of people and food in 1:1 tiles over illustrations or rounded thumbnails.
- **Reason**: A raw rectangular photo reads as a record of a real place; a rounded one reads as an app asset.
- **Evidence**: every img radius 0px; 1:1 tiles at 442 and 282px; 1440x840 person hero; mid-page collage of overlapping rectangles.

### Colour change is the only motion
- **Trigger**: When adding feedback to nav and buttons.
- **Decision**: Chose 240-300ms colour and opacity fades over transform, bounce or scale effects.
- **Reason**: The page sells a calm daily habit; nothing should jump.
- **Evidence**: transitions touch background-color, color, opacity and filter only; 240ms cubic-bezier(0,0,0.4,1) on nav; reduced-motion query present.
