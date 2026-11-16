# citymapper.com

Captured 2026-11-15 at 1440x900, one page. The cookie banner offered no reject option, so it was left unanswered. Screenshots kept outside the repo. Reference only: do not copy logos, names, the mascot, illustrations or copy.

Note: the marketing page is mascot-heavy. The "live nearby info" the owner likes lives mostly in the app; the page shows it only inside small app screenshots (departure times with slow/fast labels).

# Design Map

## Spacing Scale
- Base 4px. Observed: 4, 8, 12, 16, 20, 30, 40, 64px.
- Most frequent: 4px (38), 16px (37), 8px (29), 20px (29), 12px (14), 64px (9).
- Tiles stack ~30px apart. News grid gap 20px.

## Font Hierarchy
- h1: 44px / 48.4px, 700.
- h2 and h3 tile titles: 40px / 44px, 700.
- GO button: 24px, 700, uppercase, tracking normal.
- Lead body: 20px / 28px, 400, max-width 400px.
- Card body: 18.72px, 400. UI and buttons: 16px, 700. Small: 13-14px.
- One family (rounded sans, 772 nodes). Two weights: 700 and 400.

## Color Palette
- #FFFFFF page, 63%. #F6F6F6 neutral tile, 19%.
- #37AB2F brand green, 8%: one feature tile, the GO button, pill CTAs, one word of the h1.
- #417193 slate blue, 3%: journey planner panel.
- #383838 text, #4A4A4A secondary and footer.
- Neutrals pure gray (#F6F6F6, #383838); hairline tinted navy rgba(0,17,34,0.06).

## Image Ratios
- Mascot illustrations: 1:1 and 1.15:1.
- News thumbnails: 1.9:1 at 300px wide.

## Component Tokens
- Radius: 20px tiles (17 uses), 8px inputs and small buttons, 6px nav chips, 45-96px pill CTAs, 50% icon circles.
- Shadows: none as depth. A 0.5px ring (0 -0.5px 0 0.5px rgba(0,17,34,0.06)) acts as a border. One 4px lip rgba(0,17,34,0.133) under a pressed control.
- Content column 940px. News grid 3 x 300px, 20px gap.
- Planner: two 50px inputs, swap control between them, Now / Arrive / Leave as three bare words, GO button.
- Motion: colour 100ms; transform 200ms cubic-bezier(0.2,0.8,0.1,1); transform 150ms on chips; top 200ms.
- :focus-visible present. No prefers-reduced-motion query found.

---

# Taste DNA

### The tool is the hero
- **Trigger**: When choosing what fills the first viewport of a transport brand.
- **Decision**: Chose a working journey form (start, end, time mode, go) at y=318px over a hero photo or a tagline-only banner.
- **Reason**: A person who came to get somewhere wants to type, not read about the app first.
- **Evidence**: planner panel 940px wide, #417193, radius 20px, inside the first 900px; two 50px inputs at 8px radius with a swap control; time mode as three bare words, not a dropdown.

### Bold carries the hierarchy, one family carries everything
- **Trigger**: When building a loud voice without a second display font.
- **Decision**: Chose one rounded sans in two weights (700/400) over a display/body pairing.
- **Reason**: Heavy weight at large size is enough to shout, and one family keeps a dense app UI coherent.
- **Evidence**: 772 nodes in one family vs 12 system-ui; weights 700 (41) and 400 (34) only; 44px and 40px heads vs 16-20px body, ratio ~2.2; tracking normal on every size.

### Flat tiles with a hairline, no drop shadow
- **Trigger**: When stacking six content blocks of different kinds.
- **Decision**: Chose flat filled tiles at 20px radius with a 0.5px navy-tinted ring over floating shadowed cards.
- **Reason**: A fill change plus a hairline separates blocks without suggesting they can be lifted.
- **Evidence**: 0 drop shadows; ring rgba(0,17,34,0.06); radius 20px used 17 times; tiles 940px wide, ~30px apart; inputs inside tiles at 8px (smaller nested radius).

### Utility-speed feedback
- **Trigger**: When adding hover and press states.
- **Decision**: Chose 100ms colour changes and 150-200ms transforms on a fast-out curve over 300ms+ fades.
- **Reason**: A transit user taps in a hurry; feedback must land before the finger lifts.
- **Evidence**: colour 100ms; transform 200ms cubic-bezier(0.2,0.8,0.1,1); transform 150ms on chips. No reduced-motion query: a gap, not something to copy.
