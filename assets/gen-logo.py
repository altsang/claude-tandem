#!/usr/bin/env python3
"""Draws the Claude Tandem logo: two Clawds on a tandem bike, as one piece of block art.

  python3 assets/gen-logo.py      writes assets/logo.svg and assets/logo-icon.svg

Everything is a hand-placed sprite, like Clawd himself: each character is one block.
a = the stoker (back), b = the captain (front), # = the bike. The menu-bar icon is a
smaller drawing of the same idea, in macos/ClaudeTandem/main.swift.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
COLOR = {"a": "#B4572A", "b": "#D9773F", "#": "#8A7F76"}   # the warm grey reads on light and dark
CREAM = "#F6F0E6"
PW, PH = 3.0, 5.6        # Clawd's block: his terminal characters are taller than wide

# Clawd, as Claude Code draws him in block characters:  ▐▛███▜▌ / ▝▜█████▛▘ / ▘▘ ▝▝
LOGO = [
    ".......aaaaaaaaaaaa.....bbbbbbbbbbbb.........",
    ".......aa.aaaaaa.aa.....bb.bbbbbb.bb.........",
    ".....aaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbb##......",   # the captain's hand on the grip
    ".......aaaaaaaaaaaa.....bbbbbbbbbbbb..#......",
    "........a.a....a.a.......b.b....b.b...#......",
    "......#################################......",   # one bar for both
    "......#...............................#......",   # a gap, so it reads as a bike, not a table
    "...#######.........................#######...",
    ".##...#...##.....................##...#...##.",
    "##....#....##...................##....#....##",
    "#.....#.....#...................#.....#.....#",   # hubs
    "##.........##...................##.........##",
    ".##.......##.....................##.......##.",
    "...#######.........................#######...",
]
SPEED = [(-5, 7, 3), (-6, 9, 4), (-5, 11, 3)]   # blocks behind the bike: column, row, length


def rects(cells):
    return "".join(f'<rect x="{i*PW:.1f}" y="{j*PH:.1f}" width="{PW+.05:.2f}" height="{PH+.05:.2f}"/>'
                   for i, j in cells)


def layer(ch, cls=""):
    cells = [(i, j) for j, row in enumerate(LOGO) for i, v in enumerate(row) if v == ch]
    return f'<g{cls} fill="{COLOR[ch]}">{rects(cells)}</g>'


def picture(anim):
    hop = ' class="hop"' if anim else ""
    speed = "".join(f'<g class="go" fill="{COLOR["b"]}" opacity=".45">{rects((c + k, r) for k in range(n))}</g>'
                    for c, r, n in SPEED) if anim else ""
    return f'<g shape-rendering="crispEdges">{speed}{layer("#")}{layer("a", hop)}{layer("b", hop)}</g>'


# animated block by block, like a game sprite: the riders hop out of step, the speed blocks blink in turn
ANIM = ('<style>.hop{animation:h .6s steps(1) infinite}.hop+.hop{animation-delay:-.3s}'
        '@keyframes h{50%{transform:translateY(-2px)}}'
        '.go{animation:s .6s steps(1) infinite}.go+.go{animation-delay:-.2s}.go+.go+.go{animation-delay:-.4s}'
        '@keyframes s{66%{opacity:0}}</style>')

W, H = len(LOGO[0]) * PW, len(LOGO) * PH


def write(name, vb, body):
    with open(os.path.join(HERE, name), "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}">{body}</svg>\n')


assert all(len(r) == len(LOGO[0]) for r in LOGO)
write("logo.svg", f"-20 -4 {W+24:.0f} {H+8:.0f}", ANIM + picture(True))
s = 200 / W
write("logo-icon.svg", "0 0 256 256", f'<rect width="256" height="256" rx="58" fill="{CREAM}"/>'
      f'<g transform="translate({128-W*s/2:.1f} {128-H*s/2:.1f}) scale({s:.3f})">{picture(False)}</g>')
