# Design Map

Source: https://www.are.na (homepage, logged out, 1440x900, captured 2026-11-15). Inspiration only: do not copy logo, name, imagery or copy.

## Spacing Scale
- Base unit 2.5px. Observed: 2.5, 5, 7.5, 10, 15, 20, 25, 35, 45, 65, 80, 130px
- Most frequent: 2.5px (42), 5px (41), 10px (39), 15px (32)
- Component gaps: 5px (button icon), 15px (article), 35px (section inner)
- Section gaps: 130px between feature blocks; 455-536px around hero and product demo
- Footer padding 65px; method: flex/grid `gap`, margins only on `p` (5px top)

## Font Hierarchy
- One family: areal (custom). No second face, no mono
- 19.2px / 400 / 27.84px: h1 hero statement
- 19.2px / 700 / 27.84px: h2 section titles (same size as h1; weight is the only step)
- 16px / 400: nav, list text
- 14.4px / 700: button labels
- 12.5px / 400 / 16.875px: captions, card meta
- 10px / 400: micro labels
- Weights: 400 (152), 700 (25), 600 (12). Letter-spacing normal everywhere

## Color Palette
- #FFFFFF page background
- #F7F7F7 surfaces and secondary button fill (57.7% of painted area)
- #EDEDED pressed / hover surface
- #DEDEDE hairline rules
- #333333 text primary, #000000 text strong, #696969 secondary, #999999 tertiary
- #00075F single accent: primary button and footer slab only (11% of area, all footer)
- Greys are pure (R=G=B), not tinted

## Image Ratios
- Product demo frame 1.46:1 at 958px
- Editorial thumbnails 1:1 at 120px, set beside text, not above it
- Community thumbnails keep natural ratio (0.75:1 to 1.69:1)

## Component Tokens
- Radius: 3px (31 uses: buttons, chips), 50% avatars, 10-18px on the product frame only
- Shadow: 0 0 34px rgba(0,0,0,0.05), product frame only (4 uses); nothing else casts a shadow
- Buttons: ~34px tall, 15px side padding, 14.4px/700, 3px radius. Primary navy fill; secondary #F7F7F7 fill, no border
- Text column: 640px wide, left edge at x=393 (27% in), left-aligned, not centred
- Grid: 3 columns x 334.5px, gap 45px vertical / 15px horizontal
- Pricing as disclosure rows: chevron + title + one-line caption, hairline above each row
- Motion: color 150ms ease; opacity/transform 180ms cubic-bezier(0.16,1,0.3,1); transform 240ms cubic-bezier(0.22,1,0.36,1)
- prefers-reduced-motion: yes. :focus-visible: yes

---

# Taste DNA

### Headline at reading size
- **Trigger**: When introducing the product above the fold
- **Decision**: A 19.2px regular-weight h1, the same size as every section title, over a 48-72px display headline
- **Reason**: A visitor addressed at reading volume reads a sentence instead of scanning a slogan. Nothing is shouted, so nothing feels sold
- **Evidence**: h1 19.2px/400 vs h2 19.2px/700; only five sizes (10, 12.5, 14.4, 16, 19.2px); letter-spacing normal on every element

### One accent, spent twice
- **Trigger**: When deciding where colour may appear on a grey-and-white page
- **Decision**: One dark navy for the primary button and the footer slab only, over tinting links, icons or section backgrounds
- **Reason**: When colour lives in one interactive place, the eye finds the next step without a banner pointing at it
- **Evidence**: #00075F on 3 elements; every other surface is pure grey; secondary button is a #F7F7F7 fill with no border

### Proof that is computed, not claimed
- **Trigger**: When showing longevity and community size
- **Decision**: A bold running day-count and an exact member count set inside prose, over stat tiles, logo walls or testimonials
- **Reason**: An exact, odd number inside a sentence reads as something measured; a rounded tile reads as marketing
- **Evidence**: hero sentence with a bold 700 duration inside 19.2px/400 text; exact count in the mission prose; no logo wall or ratings anywhere

### Short, decelerating motion
- **Trigger**: When adding hover and state transitions
- **Decision**: 150-240ms opacity/transform on an expo-out curve, over springy or scroll-triggered entrances
- **Reason**: Motion that finishes before the pointer moves on feels like response, not performance
- **Evidence**: 22 elements at 150/180ms cubic-bezier(0.16,1,0.3,1); 11 at 240ms cubic-bezier(0.22,1,0.36,1); reduced-motion and focus-visible rules present
