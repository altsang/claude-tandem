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


def wheel(cx, cy, r, c, anim):
    spokes = "".join(f'<line x1="{cx}" y1="{cy-r+5}" x2="{cx}" y2="{cy+r-5}" transform="rotate({a} {cx} {cy})"/>'
                     for a in (0, 60, 120))
    cls = ' class="spin"' if anim else ""
    return (f'<g{cls} stroke="{c}" stroke-width="2.5" opacity=".55">{spokes}</g>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" stroke="{c}" stroke-width="7" fill="none"/>'
            f'<circle cx="{cx}" cy="{cy}" r="3.5" fill="{c}"/>')


def bike(c, anim=False):
    return (wheel(50, 100, 30, c, anim) + wheel(192, 100, 30, c, anim) +
            f'<g fill="none" stroke="{c}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">'
            f'<path d="M50 100 L82 58 L98 100 Z"/>'                    # rear triangle
            f'<path d="M82 58 L136 58 L146 100 L98 100"/>'             # top tube, front seat tube, boom
            f'<path d="M136 58 L170 52 M146 100 L170 52 L192 100"/>'   # front tube, down tube, fork
            f'<path d="M170 52 L166 38 L180 36"/>'                     # captain's bars
            f'<path d="M136 58 L134 50 M82 58 L80 50"/>'               # seat posts
            f'<path d="M72 48 H90 M126 48 H144"/>'                     # saddles
            f'</g><circle cx="98" cy="100" r="7" fill="{c}"/><circle cx="146" cy="100" r="7" fill="{c}"/>')


def clawd(x, c):
    pw, ph = 3.0, 5.6
    x0, y0 = x - len(CLAWD[0]) * pw / 2, 47 - len(CLAWD) * ph
    rects = "".join(f'<rect x="{x0+i*pw:.1f}" y="{y0+r*ph:.1f}" width="{pw+.05:.2f}" height="{ph+.05:.2f}"/>'
                    for r, row in enumerate(CLAWD) for i, v in enumerate(row) if v == "1")
    return f'<g class="bob" fill="{c}" shape-rendering="crispEdges">{rects}</g>'


ANIM = ('<style>.spin{transform-box:fill-box;transform-origin:center;animation:s 1.4s linear infinite}'
        '@keyframes s{to{transform:rotate(360deg)}}'
        '.bob{animation:b .7s ease-in-out infinite alternate}.bob+.bob{animation-delay:-.35s}'
        '@keyframes b{to{transform:translateY(-1.5px)}}</style>')
riders = clawd(80, D) + clawd(134, O)       # the stoker a shade darker: two accounts, one ride
speed = (f'<g stroke="{O}" stroke-width="4" stroke-linecap="round" opacity=".45">'
         f'<path d="M4 70 H16"/><path d="M0 84 H12"/><path d="M6 98 H14"/></g>')


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
