# PLUG brand

The PLUG mark is "Ask P" (direction D, chosen by the owner on 2026-11-17): an open P that is also a question mark, so the mark is the app's core action, asking. The P is forest green (`brand.green`) and the dot under it is brass (`brand.brass`): the asker. The logotype sets "plug" in espresso beside it.

These SVG files are the masters. Do not redraw the mark, add effects to it, or put a raster copy in front of a vector one.

## Files

| File | Use |
| --- | --- |
| `plug-mark.svg` | The mark, 24 px and above |
| `plug-mark-small.svg` | The small-size cut, at 24 px and below: a shorter stem and a bigger dot (gap 33), so the dot stays apart from the stem at 16 px. The favicon uses it |
| `plug-mark-mono.svg`, `plug-mark-reversed.svg` | One colour (black), and cream P with the brass dot on espresso |
| `plug-logotype.svg` | The logotype: the mark, then "plug" in Bricolage Grotesque (OFL), outlined. Cropped to its ink plus 8 units. This is the primary logo |
| `plug-logotype-mono.svg`, `plug-logotype-reversed.svg` | One colour, and cream on espresso |
| `app-icon.svg`, `app-icon-dark.svg`, `app-icon-tinted.svg` | App icon masters for the iOS light (cream P, brass dot on forest green), dark (the same on espresso) and tinted (white on black, the system tints it) appearances |
| `app-icon/AppIcon-*.png` | Every iOS icon size (20 to 1024), exported |
| `neighbourhood.svg` | Line illustration, in `rule.300` (not shown in the app) |
| `build-masters.py` | Rebuilds the SVG masters: `uv run python design/brand/build-masters.py design/brand "#2B1D14" "#FFF4EC" "#1F4D3A" "#A9793A"` (ink.900, paper, brand.green, brand.brass) |

Export to the apps with `node design/generate-brand.mjs` (both targets), `--web` (favicon.ico, icon.svg, apple-icon, PWA icons, the icon size set) or `--ios` (asset catalog). The script refuses any colour that is not a token.

## Construction

Everything sits on a 256-unit grid. One stroke width (36) and one centre.

- The stem runs from x 67 to 103 and from y 91 down to 161.
- The bowl is a 270 degree arc centred at (129, 91), outer radius 62 and inner radius 26, ending in a short spur back up to y 117.
- The dot has radius 21 at (85, 204), 22 units under the stem. The small cut ends the stem at 150 and uses radius 24 at (85, 207).
- In the logotype the word sits on a baseline at y 177, from x 236.

## Clear space

Keep clear space on every side equal to the dot's diameter (42 units). Nothing else goes inside it.

## Minimum size

| Artwork | Smallest | Below that |
| --- | --- | --- |
| Mark | 24 px tall (screen), 6 mm (print) | Use `plug-mark-small.svg`, down to 16 px |
| Logotype | 20 px tall (screen), 5 mm (print) | Use the mark alone |

## Colour

- The mark: forest green `#1F4D3A` P with a brass `#A9793A` dot, on cream `#FFF4EC` or card.
- On forest green or espresso: a cream P with the brass dot. These are the light and dark app icons.
- The word "plug" is espresso `#2B1D14` on light surfaces and cream on dark ones.
- One colour: black or white, P and dot together.
- Never a truth colour, a gradient, a shadow, an outline or glass on the mark.

## Motion

The iOS launch is a plain fade from the mark on cream. Under Reduce Motion the app simply appears. The mark does not loop.

## Misuse

Do not:

- stretch, rotate or outline the mark;
- set "PLUG" in a font next to the mark;
- separate the dot from the P, or use the dot alone as a decoration or bullet (it means a person);
- put the mark on a photo or busy background;
- use the old v3 blue P (`#0B57E3`).

## Trademark

The mark has not been searched. Run a trademark and reverse-image search before public launch.
