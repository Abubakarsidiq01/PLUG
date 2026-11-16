# transitapp.com

Captured 2026-11-15 at 1440x900, one page. 9996px tall, so viewport, mid and footer shots (kept outside the repo). No consent banner. Framer site: some blocks stay hidden until scrolled, so DOM counts are partial. Reference only: do not copy logos, names, photos, stickers, the custom font or copy.

# Design Map

## Spacing Scale
- Base 8px. Observed: 4, 8, 12, 16, 24, 32, 40, 48, 64, 80, 128px (10px and 19px are builder noise).
- Most frequent: 8px (80), 40px (56), 16px (47), 32px (38).
- Section gap: 128px, all 6 measured. Footer padding 80px, column gap 60px.

## Font Hierarchy
- h1: 72px / 72px, 800.
- h2: 60px / 60px, 800.
- h3: 40px / 48px, 800.
- Feature title and ETA figure: 24px / 28px, 800. Lead: 24px / 32px, 400.
- Small title: 20px / 24px, 800. Body: 17-18px, 400.
- Data labels: 13px. Micro: 10-11px, 800.
- One custom rounded family, weights 800 / 700 / 600 / 400. Tracking normal.

## Color Palette
- #FDF5F2 warm page, 67.6%. #FFEEE6 warmer card, 15.1%. #FFFFFF panels, 6.6%.
- #12452B deep green text (83 nodes), used in place of black.
- #993300 text on warm review cards.
- #27A559 primary action.
- Data colours: #024A99 blue stop sign, #A800B0 magenta route, orange countdown tile. #6887AB muted data text.
- Decorative: sky photo and a gradient announcement pill (both banned in PLUG).

## Image Ratios
- Hero: collage of cut-out photos on a sky, ~2.33:1 strip.
- Phone screenshot: 0.58:1. Stickers: ~1:1.

## Component Tokens
- Radius: 32px cards (54 uses), 8px inner controls (36 uses), 16px, 49px pills, 80px.
- Shadow: 0 4px 16px rgba(0,51,105,0.08), navy-tinted, only on floating hero trip cards.
- Content width 1282px inside 1440px. Centred hero; two-column feature rows with 56px icon squircles.
- Motion: hero objects 1800ms and 2500ms cubic-bezier(0.44,0,0.56,1), once; reviews ticker 82.4s linear infinite; appear-on-scroll present.
- :focus-visible present. No prefers-reduced-motion query found.

---

# Taste DNA

### The number is the headline
- **Trigger**: When showing live trip data inside marketing art.
- **Decision**: Chose a huge numeral with a tiny unit and an explicit clock time (a big "3" over "minutes"; "36 minutes" over "Arrive at 17:20") over a sentence or a progress bar alone.
- **Reason**: A rider glances for one figure; the clock time lets them check it against the world, which is what makes it believable.
- **Evidence**: countdown tile ~40px numeral over 13px unit, ratio ~3:1; ETA card 24px/800 over 13px/400; route drawn as coloured dotted segments that carry meaning.

### Warm tint instead of white and black
- **Trigger**: When choosing neutrals for a long friendly page.
- **Decision**: Chose warm-tinted surfaces (#FDF5F2, #FFEEE6) and deep green text (#12452B) over pure white and #000.
- **Reason**: Tinted neutrals feel human and cut glare, while the deep green still reads as near-black.
- **Evidence**: #FDF5F2 on 67.6% of painted area; #12452B on 83 text nodes; no pure black text measured.

### Tight stacked display, loose body
- **Trigger**: When setting multi-line headlines in one family.
- **Decision**: Chose line-height 1.0 on 60-72px ExtraBold over the usual 1.2.
- **Reason**: Tightly stacked heavy lines read as one block, leaving the airy 17-18px body to explain.
- **Evidence**: h1 72/72; h2 60/60; 1.2 only from 40px down (40/48); weights 800 and 400 dominate.

### Big rhythm, no rules
- **Trigger**: When separating ~9 sections on a 10,000px page.
- **Decision**: Chose one fixed 128px gap between every section over dividers or alternating backgrounds.
- **Reason**: A constant pause teaches the reader where a topic ends without extra marks.
- **Evidence**: 6 of 6 measured gaps = 128px; one hairline only, above the footer; 32px card radius with 8px inner controls.
