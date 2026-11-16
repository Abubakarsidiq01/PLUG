# Design Map

Source: https://teenage.engineering (homepage, 1440x900, captured 2026-11-15). The homepage was a single-product campaign at capture time, so the measurements describe the site frame (nav, grid, footer) more than a catalogue. Inspiration only: do not copy logo, name, pictograms, imagery or copy.

## Spacing Scale
- One unit: u = viewport width / 196 = 7.347px at 1440 (scales with width)
- Multiples in use: 1u 7.347, 2u 14.694, 3u 22.041, 4.5u 33.061, 9u 66.122px
- Grid row gap 2u; list gap 3u; footer padding 4.5u x 9u
- Section breaks: none; the page is one continuous black field

## Font Hierarchy
- te-20 (custom): every UI and body string (~241 uses)
- TechnoType: one-off uppercase campaign block (6 uses)
- ~28px / 100: nav section words (~approx from screenshot)
- 19.1px (2.6u) / 100 / 22.04px (3u): body, footer links
- 16px / 100: nav sub-links
- 9px: mission micro-text block
- 39.67px (5.4u) / 400: campaign display, uppercase
- Weights: 100 (51 of 58 text nodes), 300, 400, 700 rare. Nav and footer all lowercase

## Color Palette
- #000000 background, 100% of painted area
- #F1F2F2 text primary
- #E5E5E5 text secondary
- No CSS accent colour. Orange appears only inside product photographs

## Image Ratios
- Hero product renders 1:1, rendered full-bleed at 1440px, swapped as a scroll image sequence (4 frames sampled)

## Component Tokens
- Radius: 7.347px (1u) on 2 elements; 0 everywhere else
- Shadows: none
- Grid: 12 columns x 107.7px, row gap 2u, full bleed
- Nav: 5 columns, each = single-stroke pictogram (~42x84px box, ~1px line) + lowercase word + 2-3 sub-links visible at rest; no dropdowns
- Motion: background-color/color 150-200ms ease; opacity 500ms ease-out for image crossfade; transform 200ms ease-in. No keyframes or running animations
- prefers-reduced-motion: yes. :focus-visible: yes

---

# Taste DNA

### One unit owns every length
- **Trigger**: When setting spacing, radius and type for a page that must hold from phone to wall display
- **Decision**: One width-derived unit (1/196 of the viewport) with multiples 1, 2, 3, 4.5, 9 over a fixed 4/8px scale with breakpoint overrides
- **Reason**: When gaps, corners and type move together, the layout keeps its proportions on any screen and reads as one drawn object
- **Evidence**: radius 1u; row gap 2u; list gap 3u; footer 4.5u x 9u; body 2.6u on a 3u line

### Brand carried by line pictograms, not colour
- **Trigger**: When navigation must also carry identity
- **Decision**: A single-stroke pictogram beside each lowercase section word, over a coloured logo bar, icon font or dropdown menu
- **Reason**: A set of drawings with one stroke weight is recognisable at a glance and cannot be mistaken for a kit, and it costs no colour
- **Evidence**: 5 nav columns of pictogram + word + sub-links; sub-links always visible; palette is three neutrals only

### No chrome around the product
- **Trigger**: When presenting hardware on the homepage
- **Decision**: Full-bleed 1:1 renders on pure black with no cards, shadows or borders, over a framed product-card grid
- **Reason**: The object is the proof; anything drawn around it competes with what people came to see
- **Evidence**: 0 box-shadows; 1 radius value on 2 elements; #000000 is 100% of painted area; hero images 1:1 at 1440px

### Thin, lowercase voice
- **Trigger**: When setting the typographic tone for an engineering company
- **Decision**: Weight 100 lowercase text in one custom face over bold uppercase technical labelling
- **Reason**: A quiet lowercase voice makes precise engineering feel approachable rather than intimidating
- **Evidence**: weight 100 on 51 of 58 text nodes; nav and footer lowercase; letter-spacing normal; caps only in the one-off campaign face
