# PLUG brand

The PLUG mark is a P whose counter holds a dot: you, held by the P, with the people near you in the ring around you. It is ink on cream. Since the Signal visual system (ADR-015, proposed) PLUG has one brand colour, Signal pink, used behind the mark on the app icon and on brand surfaces, never inside the mark.

These SVG files are the masters. Do not redraw the mark, add effects to it, or put a raster copy in front of a vector one.

## Files

| File | Use |
| --- | --- |
| `plug-mark.svg` | The mark, 24 px and above |
| `plug-mark-small.svg` | The small-size cut, at 24 px and below: a thicker ring, a bigger dot and a narrower gap, so the counter stays open at 16 px. The favicon uses it |
| `plug-mark-mono.svg`, `plug-mark-reversed.svg` | One colour (black), and paper on ink |
| `plug-logotype.svg` | The logotype: the mark stands in for the letter P, followed by LUG drawn to match it. This is the primary logo |
| `plug-logotype-mono.svg`, `plug-logotype-reversed.svg` | One colour, and paper on ink |
| `app-icon.svg`, `app-icon-dark.svg`, `app-icon-tinted.svg` | App icon masters for the iOS light (ink mark on Signal pink), dark (Signal-pink mark on ink) and tinted (white on black, the system tints it) appearances |
| `app-icon/AppIcon-*.png` | Every iOS icon size (20 to 1024), exported |
| `neighbourhood.svg` | Line illustration on the welcome screen, in `rule.300` |
| `build-masters.py` | Rebuilds the SVG masters: `python3 design/brand/build-masters.py design/brand "#15110F" "#FFF4EC" "#FF2E8B"` (ink.900, paper, signal.500) |

Export to the apps with `node design/generate-brand.mjs` (both targets), `--web` (favicon.ico, icon.svg, apple-icon, PWA icons, the icon size set) or `--ios` (asset catalog). The script refuses any colour that is not a token.

There is no stacked lockup. The mark already is the P, so stacking it above the word would read "P PLUG". Use the logotype, or the mark alone where the space is square.

## Construction

Everything sits on a 256-unit grid.

- The stem runs from x 50 to 96 (46 wide) and from y 32 to 224. The bowl is a half-circle of radius 72 centred at (134, 104), on a cap height of 144 (y 32 to 176). The stem drops 48 below the bowl, a descender that carries on the old cable tail.
- The counter is a circle of radius 44 and the dot a circle of radius 21, both at (134, 104).
- In LUG, stems are 44 and the cap height is 144. Rounds overshoot the baseline by 2. The G's bar runs from y 104 to 140 and ends square as a spur. The gaps are 28 from P to L and 24 between letters.

## Clear space

Keep clear space on every side equal to the dot's diameter (42 units, 16% of the mark's height). Nothing else (text, edges, other marks) goes inside it.

## Minimum size

| Artwork | Smallest | Below that |
| --- | --- | --- |
| Mark | 24 px tall (screen), 6 mm (print) | Use `plug-mark-small.svg`, down to 16 px |
| Logotype | 20 px tall (screen), 5 mm (print) | Use the mark alone |

## Colour

- The mark and logotype: ink `#15110F` (`ink.900`) on cream `#FFF4EC` (`paper`) or card `#FFFFFF`. The logotype is always ink (or reversed, or one colour), never pink.
- On Signal pink `#FF2E8B` (`signal.500`): the mark in ink only (5.38:1). This is the light app icon.
- Reversed: cream on ink. The dark app icon is the Signal-pink mark on ink.
- One colour: black or white.
- Never white or cream text, or a white mark, on Signal pink (3.5:1, below AA).

Never use a truth colour, a gradient, a shadow, an outline or glass on the mark.

## Motion

The mark has one animation, under 1.1 s (`motion.reveal`), played once on the iOS launch splash and in the web hero:

1. The dot appears (0 to 240 ms).
2. A ring grows from it and fades (200 to 600 ms).
3. The P closes around it (450 to 1100 ms).

It says: you, then the people around you, connected by PLUG. Under Reduce Motion (iOS) or `prefers-reduced-motion` (web), the final frame shows immediately. The mark does not loop, and nothing else in PLUG animates on load.

## Misuse

Do not:

- stretch, rotate or outline the mark;
- set "PLUG" in a font next to the mark;
- use the dot or ring as a decoration, a bullet or a loader (a circle means a person);
- put the mark on a photo or busy background;
- use the old v3 blue P (`#0B57E3`).

## Trademark

The mark has not been searched. Run a trademark and reverse-image search before public launch.
