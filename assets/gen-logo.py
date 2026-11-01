#!/usr/bin/env python3
"""Draws the Claude Tandem logo: two Clawds on a tandem bike.

  python3 assets/gen-logo.py      writes assets/logo.svg, logo-icon.svg, logo-icon-small.svg
"""
import os

O, D, CREAM = "#D9773F", "#B4572A", "#F6F0E6"
HERE = os.path.dirname(os.path.abspath(__file__))

# Clawd, as Claude Code draws him in block characters:  ▐▛███▜▌ / ▝▜█████▛▘ / ▘▘ ▝▝
CLAWD = ["000111111111111000",   # top of head
         "000110111111011000",   # eyes
         "011111111111111110",   # arms
         "000111111111111000",
         "000010100001010000"]   # legs


# The bike is drawn on Clawd's own pixel grid, so riders and frame are one piece of block art.
# Each line is traced point by point, inking a brush two cells wide and one tall at each step:
# Clawd's cells are taller than wide, so that makes every stroke about square, whatever its angle.
PW, PH = 3.0, 5.6                  # Clawd's pixel: his block characters are taller than wide
GX, GY = 2.0, 2.2                  # grid origin, chosen so both riders land on whole cells


def trace(points):
    out = set()
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        n = int(max(abs(bx - ax), abs(by - ay)) * 4) + 1
        for k in range(n + 1):
            x, y = ax + (bx - ax) * k / n, ay + (by - ay) * k / n
            i, j = int((x - GX) // PW), int((y - GY) // PH)
            out |= {(i, j), (i + 1, j)}
    return out


def circle(cx, cy, r):
    import math
    return trace([(cx + r * math.cos(t / 90 * math.pi), cy + r * math.sin(t / 90 * math.pi)) for t in range(181)])


def rects(cs):
    return "".join(f'<rect x="{GX+i*PW:.1f}" y="{GY+j*PH:.1f}" width="{PW+.05:.2f}" height="{PH+.05:.2f}"/>'
                   for i, j in sorted(cs))


def bike(c, anim=False):
    cells = (circle(50, 100, 27) | circle(192, 100, 27) |
             trace([(48, 100), (62, 58), (170, 58), (190, 100)]) |  # stay, one bar for both riders, fork
             trace([(81, 58), (81, 47)]) | trace([(135, 58), (135, 47)]) |    # seat posts
             trace([(170, 58), (170, 41), (182, 41)]))                       # bars
    return f'<g fill="{c}" shape-rendering="crispEdges">{rects(cells)}</g>'


def clawd(x, c):
    pw, ph = PW, PH
    x0, y0 = x - len(CLAWD[0]) * pw / 2, 47 - len(CLAWD) * ph
    rects = "".join(f'<rect x="{x0+i*pw:.1f}" y="{y0+r*ph:.1f}" width="{pw+.05:.2f}" height="{ph+.05:.2f}"/>'
                    for r, row in enumerate(CLAWD) for i, v in enumerate(row) if v == "1")
    return f'<g class="bob" fill="{c}" shape-rendering="crispEdges">{rects}</g>'


ANIM = ('<style>.go rect{animation:f .45s steps(1) infinite}.go rect+rect{animation-delay:-.15s}.go rect+rect+rect{animation-delay:-.3s}'
        '@keyframes f{33%{opacity:0}}'
        '.bob{animation:b .6s steps(1) infinite}.bob+.bob{animation-delay:-.3s}'
        '@keyframes b{50%{transform:translateY(-2px)}}</style>')
riders = clawd(80, D) + clawd(134, O)       # the stoker a shade darker: two accounts, one ride
speed = (f'<g class="go" fill="{O}" opacity=".45" shape-rendering="crispEdges">'
         f'<rect x="5" y="69.4" width="12" height="5.6"/><rect x="-1" y="80.6" width="12" height="5.6"/><rect x="5" y="91.8" width="9" height="5.6"/></g>')


def write(name, vb, body):
    with open(os.path.join(HERE, name), "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}">{body}</svg>\n')


# the README's: wheels turning, riders pedalling; reads on light and dark
write("logo.svg", "-4 0 248 140", ANIM + speed + bike(O, True) + riders)
# app icon, on its own cream ground
write("logo-icon.svg", "0 0 256 256", f'<rect width="256" height="256" rx="58" fill="{CREAM}"/>'
      f'<g transform="translate(2 50) scale(1.05)">{bike(O) + riders}</g>')
# 32px and below the riders blur: the bare bike
write("logo-icon-small.svg", "0 0 256 256", f'<rect width="256" height="256" rx="58" fill="{CREAM}"/>'
      f'<g transform="translate(-4 52) scale(1.1)">{bike(O)}</g>')
