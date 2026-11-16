# Reference summary B: what survives PLUG's bans

Captured 2026-11-15 at 1440x900, homepages only. No site blocked automated capture. The teenage.engineering homepage was a single-product campaign at the time, so its notes cover the site frame (nav, grid, footer). Screenshots stay outside the repo. Nothing here copies logos, names, illustrations or copy.

## are.na: restraint
1. Headline at reading size. Their h1 is 19.2px/400, the same size as section titles, and only weight (400 to 700) separates them. Five sizes in total (10, 12.5, 14.4, 16, 19.2). For PLUG: titles at most about 1.2x body, with hierarchy carried by weight.
2. A left-aligned text column of about 640px (27% from the left edge, not centred), separated by hairlines (#DEDEDE) instead of cards. Pure greys only (#F7F7F7, #EDEDED, #333, #696969).
3. Motion of 150 to 240ms on opacity and transform, curve cubic-bezier(0.16, 1, 0.3, 1). Secondary button: grey fill, no border, 3px radius, about 34px tall.
- Do not borrow: the saturated navy primary button and footer slab. PLUG's primary is ink.

## teenage.engineering: ownable system
1. One unit sets every length. Theirs is viewport/196 (7.35px). Spacing uses only 1, 2, 3, 4.5 and 9 units, and the corner radius is 1 unit. For PLUG: a 4pt grid limited to a few named multiples, with radius tied to the unit.
2. Brand carried by a custom single-stroke line icon set (one stroke weight, about 1px at a 42x84 box) placed beside lowercase words. This gives identity without any colour.
3. No frame around the subject: no shadows, one radius value, full-bleed 1:1 imagery. Sub-links stay visible, with no dropdowns.
- Do not borrow: the second display typeface in all caps, or weight-100 text at 16px on black (fails legibility).

## mercury.com: trust and calm motion
1. Three speeds on one curve: 150ms for colour, 300ms for state changes, 500ms for exits, all on cubic-bezier(0, 0, 0.2, 1). Accordions animate grid-template-rows over 300ms, and every animation is gated on reduced motion.
2. Every claim has a visible footnote: a superscript marker, a plain disclosure line of 12 to 14px, and a numbered source list. For PLUG this becomes "who said it, when", sitting beside each truth label.
3. Small weight steps (360, 400, 420, 480) instead of a jump from 400 to 700. Body text is 16/24, headings use a line height of 1.10 to 1.15, and any hero motion ends on a still frame with no loops.
- Do not borrow: the 670ms translate-and-fade reveals on scroll. Also skip the periwinkle pill buttons and the frosted email field.
