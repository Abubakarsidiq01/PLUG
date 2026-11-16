"""Builds the PLUG brand SVG masters. Usage: python3 design/brand/build-masters.py design/brand "#15110F" "#FFF4EC" "#FF2E8B" (ink.900, paper, signal.500)"""
import math, re, sys, pathlib

if len(sys.argv) != 5 or not all(re.fullmatch(r"#[0-9A-Fa-f]{6}", c) for c in sys.argv[2:5]):
    sys.exit('usage: build-masters.py <out-dir> <ink #RRGGBB> <paper #RRGGBB> <signal #RRGGBB>, e.g. design/brand "#15110F" "#FFF4EC" "#FF2E8B"')
out = pathlib.Path(sys.argv[1]); INK, PAPER, SIGNAL = sys.argv[2], sys.argv[3], sys.argv[4]

# The mark: a P (stem + bowl, cap height 144 on a 256 grid, stem descends 48 below the bowl)
# whose counter holds a dot: you, held by the P. Centred optically (x 50..206, y 32..224).
OUTER = "M50 32H134A72 72 0 0 1 134 176H96V224H50Z"
def hole(r): return f"M134 {104 - r}A{r} {r} 0 1 1 134 {104 + r}A{r} {r} 0 1 1 134 {104 - r}Z"
MARK = (OUTER + hole(44), 21)      # ring 28, gap 23, dot 21
SMALL = (OUTER + hole(41), 23)     # 24 px and below: thicker ring, bigger dot, gap 18

def mark_body(fill, small=False):
    d, r = SMALL if small else MARK
    return f'<path fill="{fill}" fill-rule="evenodd" d="{d}"/><circle fill="{fill}" cx="134" cy="104" r="{r}"/>'

def pt(cx, cy, R, deg):
    a = math.radians(deg); return f"{cx + R * math.cos(a):.1f} {cy + R * math.sin(a):.1f}"

# LUG, drawn to the mark: cap height 144 (y 32..176), stems 44, rounds overshoot by 2.
L = "M0 32H44V136H100V176H0Z"
U = "M0 32H44V112A22 22 0 0 0 88 112V32H132V112A66 66 0 0 1 0 112Z"
G_RING = f"M{pt(74, 104, 74, -45)}A74 74 0 1 0 {pt(74, 104, 74, 0)}L{pt(74, 104, 30, 0)}A30 30 0 1 1 {pt(74, 104, 30, -45)}Z"
G_BAR = "M90 104H148V140H90Z"

def word_body(fill, x0):
    return (f'<g fill="{fill}"><path transform="translate({x0} 0)" d="{L}"/>'
            f'<path transform="translate({x0 + 124} 0)" d="{U}"/>'
            f'<g transform="translate({x0 + 280} 0)"><path d="{G_RING}"/><path d="{G_BAR}"/></g></g>')

def svg(vb, body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" role="img" aria-label="{title}">'
            f'<title>{title}</title>{body}</svg>\n')

files = {
    "plug-mark.svg": svg("0 0 256 256", mark_body(INK), "PLUG"),
    "plug-mark-small.svg": svg("0 0 256 256", mark_body(INK, small=True), "PLUG"),
    "plug-mark-reversed.svg": svg("0 0 256 256", f'<rect width="256" height="256" fill="{INK}"/>' + mark_body(PAPER), "PLUG"),
    "plug-mark-mono.svg": svg("0 0 256 256", mark_body("#000000"), "PLUG"),
    # Logotype: the mark is the P, then LUG. 28 units between P and L, 24 between letters.
    "plug-logotype.svg": svg("34 0 674 256", mark_body(INK) + word_body(INK, 234), "PLUG"),
    "plug-logotype-reversed.svg": svg("34 0 674 256", f'<rect x="34" width="674" height="256" fill="{INK}"/>' + mark_body(PAPER) + word_body(PAPER, 234), "PLUG"),
    "plug-logotype-mono.svg": svg("34 0 674 256", mark_body("#000000") + word_body("#000000", 234), "PLUG"),
    # App icon masters (1024), mark centred in the iOS safe area (ADR-015): ink mark on Signal
    # pink (light), Signal-pink mark on ink (dark). Ink on Signal is 5.38:1; never white on Signal.
    "app-icon.svg": svg("0 0 1024 1024", f'<rect width="1024" height="1024" fill="{SIGNAL}"/><g transform="translate(140.8 140.8) scale(2.9)">{mark_body(INK)}</g>', "PLUG"),
    "app-icon-dark.svg": svg("0 0 1024 1024", f'<rect width="1024" height="1024" fill="{INK}"/><g transform="translate(140.8 140.8) scale(2.9)">{mark_body(SIGNAL)}</g>', "PLUG"),
    "app-icon-tinted.svg": svg("0 0 1024 1024", f'<rect width="1024" height="1024" fill="#000000"/><g transform="translate(140.8 140.8) scale(2.9)">{mark_body("#FFFFFF")}</g>', "PLUG"),
}
for name, text in files.items():
    (out / name).write_text(text)
print("wrote", ", ".join(files))
