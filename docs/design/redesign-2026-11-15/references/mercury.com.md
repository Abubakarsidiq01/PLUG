# Design Map

Source: https://mercury.com (homepage, logged out, 1440x900, captured 2026-11-15). Elements at opacity 0 before their scroll reveal were skipped by the extractor, so light-section colours are partly read from screenshots (~approx). Inspiration only: do not copy logo, name, imagery or copy.

## Spacing Scale
- Base unit 4px. Observed: 2, 4, 8, 12, 16, 20, 24, 32, 40, 72, 128px
- Most frequent: 12px (62), 40px (29), 32px (51 incl. column gap), 8px (20)
- Section padding 72px and 128px; nav padding 16px 32px; button side padding 20px

## Font Hierarchy
- arcadia (text) and arcadiaDisplay (headings): one superfamily, both variable
- 65.34px / 480: large display
- 49.35px / 480 / 1.10: h1
- 42px / 480 / 1.15 / +0.42px: h2
- 28, 24, 21px / 400-480: h3, large body
- 18px / 400: lead body
- 16px / 420 / 1.5: body and UI (109 uses)
- 12px / 400 / 1.4: legal footnotes
- Weights: 420, 400, 480, 360; 700 on 3 nodes only
- Uppercase 14px +0.28px on 10 elements (wordmark, eyebrows)

## Color Palette
- #171721 dark section background
- #1E1E2A dark raised surface (disclosure strip)
- #FBFCFD light section background (~approx)
- #EDEDF3 text on dark; #C3C3CC secondary
- #5266EB accent, primary CTA only
- rgba(175,178,206,0.2) hairlines on dark

## Image Ratios
- Hero 2.67:1 full bleed (video with still start and end frames)
- Testimonials 2:1 at 1013px
- Feature tiles 3:2 at 490px, some 4:5

## Component Tokens
- Radius: 4px (108 uses, controls), 8px, 12px (media tiles), 32-40px and 9999px (pill CTAs)
- Shadow: one single-layer rgba(0,0,0,0.05) on the scrolled nav; media tiles flat
- Grid: 16 columns x 55px, 32px gutters, content ~1013px
- Motion: colour 150/300/500ms cubic-bezier(0,0,0.2,1); opacity 300ms same curve; transform 300ms cubic-bezier(0.4,0,0.2,1); accordion grid-template-rows 300ms; tab swap 300ms ease-in-out out then in; image exit fadeOutBlur 500ms; scroll reveal translateUp + fadeIn 670ms cubic-bezier(0.28,1.1,0.74,1)
- prefers-reduced-motion: yes (motion-safe: prefixes). :focus-visible: yes

---

# Taste DNA

### Three-speed motion with one shape
- **Trigger**: When animating a product that handles people's money
- **Decision**: A small fixed set of durations (150ms hover colour, 300ms state change, 500ms image exit) on one decelerating curve, over per-component springs or bounces
- **Reason**: Motion that always ends the same way, and ends quickly, feels like a steady hand; surprise motion near money reads as risk
- **Evidence**: 46 elements opacity 300ms cubic-bezier(0,0,0.2,1); colour at 300 (41), 150 (25), 500ms (11); accordion via grid-template-rows 300ms; reveals gated by motion-safe:

### Every claim carries its footnote
- **Trigger**: When making strong product claims in the hero
- **Decision**: Superscript footnote markers on claims, a plain disclosure strip inside the hero, and a numbered footnote list at the end, over unqualified headline promises
- **Reason**: People trust a claim more when they can see where its limits are written down
- **Evidence**: superscript marker on the hero subhead; ~13px disclosure strip on #1E1E2A at the hero's bottom edge; 8 numbered footnotes at 12px/16.8px

### Weight steps of 20-60, not 400 to 700
- **Trigger**: When building heading and body hierarchy
- **Decision**: Variable weights 360/400/420/480 with size doing the lifting, over a regular/bold pair
- **Reason**: Small weight steps keep headlines spoken rather than shouted, which suits a product asking for trust
- **Evidence**: weights 420 (73), 400 (64), 480 (55), 360 (20); 700 on 3 nodes; h1 49.35px/480 at 1.10; body 16px/420 at 1.5

### Hero that comes to rest
- **Trigger**: When using video in the hero
- **Decision**: A clip bracketed by a still first and last frame over an endless looping background video
- **Reason**: A scene that settles lets the reader start reading; a loop keeps pulling the eye off the words
- **Evidence**: separate start-frame and end-frame images, both 2.67:1; no infinite iteration counts in any running animation
