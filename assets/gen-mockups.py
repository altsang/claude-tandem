#!/usr/bin/env python3
"""Render the README's animated mockups as self-contained SVGs.

Pure CSS keyframes — no script, no SMIL, no GIF — so GitHub plays them in an <img>.
Each element is shown or hidden on one shared loop, commands "type" through a
widening clip, and the pointer moves by animated translate. Claude's windows are
drawn schematically (Claude's Dock icon simplified, placeholder accounts). Terminal lines are the
tool's real output, shortened where marked.

    python3 assets/gen-mockups.py               # writes the five SVGs beside this file
    FRAME=8.5 OUT=/tmp/x python3 assets/gen-mockups.py   # one still moment of each, to check by eye
"""
import html, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("OUT", HERE)
UI = "-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif"
MONO = "ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace"
TEAL, BLUE, GRAPH, AMBER = "#18A8B4", "#2350C8", "#3A3A40", "#B25E00"
CLAUDE_TILE = "#DB6B46"   # the Claude app icon's terracotta, behind its starburst (glyph="spark")


FRAME = os.environ.get("FRAME")   # FRAME=<seconds>: render that one moment, unanimated, to check by eye


class Scene:
    def __init__(self, w, h, total):
        self.w, self.h, self.total = w, h, total
        self.kf, self.body, self.n = [], [], 0
        self.frame = float(FRAME) if FRAME else None

    def _id(self, p):
        self.n += 1
        return f"{p}{self.n}"

    def pct(self, t):
        return 100.0 * t / self.total

    # visibility: hidden, then shown from t_on (until t_off, else to the end of the loop)
    def vis(self, t_on, t_off=None):
        name, e = self._id("v"), 0.2
        if self.frame is not None:
            on = t_on <= self.frame and (t_off is None or self.frame < t_off)
            return f'opacity="{1 if on else 0}"'
        p1 = self.pct(t_on)
        if t_on <= 0 and t_off is not None:   # on screen as the loop starts: no fade-in, no flicker
            p2 = self.pct(t_off)
            self.kf.append(f"@keyframes {name}{{0%,{p2:.2f}%{{opacity:1}}{p2+e:.2f}%,100%{{opacity:0}}}}")
            return f'style="opacity:1;animation:{name} {self.total}s linear infinite"'
        if t_off is None:
            k = f"@keyframes {name}{{0%,{p1:.2f}%{{opacity:0}}{p1+e:.2f}%,100%{{opacity:1}}}}"
        else:
            p2 = self.pct(t_off)
            k = (f"@keyframes {name}{{0%,{p1:.2f}%{{opacity:0}}{p1+e:.2f}%,{p2:.2f}%{{opacity:1}}"
                 f"{p2+e:.2f}%,100%{{opacity:0}}}}")
        self.kf.append(k)
        return f'style="opacity:0;animation:{name} {self.total}s linear infinite"'

    def add(self, svg, t_on=None, t_off=None):
        if t_on is None and t_off is not None:
            t_on = 0.0                      # shown from the start, until t_off
        if t_on is None:
            self.body.append(svg)
        else:
            self.body.append(f'<g {self.vis(t_on, t_off)}>{svg}</g>')

    # a command typed character by character, then left on screen until t_off
    def typed(self, x, y, text, t, t_off=None, size=12, color="#E6EDF3", cw=None):
        cw = cw or size * 0.6022
        n = len(text)
        dur = min(1.6, 0.03 * n)
        cid, k = self._id("c"), self._id("k")
        if self.frame is not None:
            shown = max(0, min(n, int(n * (self.frame - t) / dur))) if dur else n
            self.add(t_(x, y, text[:shown], size, color, family=MONO), t - 0.05, t_off)
            return
        p1, p2 = self.pct(t), self.pct(t + dur)
        self.kf.append(f"@keyframes {k}{{0%,{p1:.2f}%{{width:0}}{p2:.2f}%,100%{{width:{n*cw:.1f}px}}}}")
        clip = (f'<clipPath id="{cid}"><rect x="{x}" y="{y-size-2}" height="{size+6}" width="0" '
                f'style="animation:{k} {self.total}s steps({n},end) infinite"></rect></clipPath>')
        txt = (f'<text x="{x}" y="{y}" font-family="{MONO}" font-size="{size}" fill="{color}" '
               f'xml:space="preserve" clip-path="url(#{cid})">{html.escape(text)}</text>')
        self.add(clip + txt, t - 0.05, t_off)

    # a group moved through (t, x, y) points: the pointer
    def moving(self, svg, points):
        k = self._id("m")
        if self.frame is not None:
            f = self.frame
            prev = points[0]
            for pt in points:
                if pt[0] >= f:
                    span = pt[0] - prev[0]
                    a = (f - prev[0]) / span if span else 1
                    x, y = prev[1] + (pt[1] - prev[1]) * a, prev[2] + (pt[2] - prev[2]) * a
                    break
                prev = pt
            else:
                x, y = points[-1][1], points[-1][2]
            self.body.append(f'<g transform="translate({x:.1f},{y:.1f})">{svg}</g>')
            return
        stops = "".join(f"{self.pct(t):.2f}%{{transform:translate({x}px,{y}px)}}" for t, x, y in points)
        first, last = points[0], points[-1]
        self.kf.append(f"@keyframes {k}{{0%{{transform:translate({first[1]}px,{first[2]}px)}}{stops}"
                       f"100%{{transform:translate({last[1]}px,{last[2]}px)}}}}")
        self.body.append(f'<g style="animation:{k} {self.total}s ease-in-out infinite">{svg}</g>')

    def write(self, name):
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" '
               f'width="{self.w}" height="{self.h}" font-family="{UI}">\n<style>\n'
               + "\n".join(self.kf) + "\n</style>\n" + "\n".join(self.body) + "\n</svg>\n")
        if self.frame is not None:
            name = name.replace(".svg", f"@{self.frame:g}.svg")
            svg = svg.replace("<style>\n\n</style>\n", "")
        path = os.path.join(OUT, name)
        open(path, "w").write(svg)
        print(f"wrote {name}  {len(svg)/1000:.1f} KB  {self.w}x{self.h}")


def esc(s): return html.escape(s)

def t_(*a, **k): return t(*a, **k)

def t(x, y, s, size=12, fill="#1D1D1F", weight=400, anchor="start", family=UI):
    return (f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{fill}" '
            f'text-anchor="{anchor}" font-family="{family}" xml:space="preserve">{esc(s)}</text>')

def badge(cx, cy, r, letter, color, ring="#FFFFFF"):
    return (f'<circle cx="{cx}" cy="{cy}" r="{r+1.5}" fill="{ring}"></circle>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{color}"></circle>'
            + t(cx, cy + r * 0.38, letter, size=r * 1.1, fill="#FFFFFF", weight=700, anchor="middle"))

def icon_sprite():
    """The menu-bar sprite, read from the app itself so the mockups can't drift from it."""
    src = open(os.path.join(HERE, "..", "macos", "ClaudeTandem", "main.swift")).read()
    block = re.search(r"static let iconSprite = \[(.*?)\]", src, re.S).group(1)
    return re.findall(r'"([.#]+)"', block)

def menubar_icon(cx, cy, bw=1.0, bh=1.5, fill="#1D1D1F"):
    rows = icon_sprite()
    x0, y0 = cx - len(rows[0]) * bw / 2, cy - len(rows) * bh / 2
    cells = "".join(f'<rect x="{x0+i*bw:.2f}" y="{y0+j*bh:.2f}" width="{bw}" height="{bh}"></rect>'
                    for j, row in enumerate(rows) for i, c in enumerate(row) if c == "#")
    return f'<g fill="{fill}" shape-rendering="crispEdges">{cells}</g>'

def desktop(sc, h_bar=24):
    sc.add(f'<rect width="{sc.w}" height="{sc.h}" rx="14" fill="#E7E9EE"></rect>')
    sc.add(f'<rect width="{sc.w}" height="{h_bar}" fill="#F7F7F9" opacity="0.92"></rect>'
           + t(16, 16, "Claude", 12, weight=700) + t(sc.w - 16, 16, "Fri 9:41", 12, anchor="end"))
    # Claude Tandem's menu-bar icon: the app's own sprite, centred on x
    x = sc.w - 92
    sc.add(menubar_icon(x, h_bar / 2))
    return x

def window(sc, x, y, w, h, account, plan, badge_letter=None, badge_color=None):
    side = 134
    s = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="#FFFFFF" stroke="#C9CBD1"></rect>',
         f'<path d="M{x} {y+10}a10 10 0 0 1 10-10h{w-20}a10 10 0 0 1 10 10v18H{x}Z" fill="#EDEEF1"></path>']
    for i, c in enumerate(("#FF5F57", "#FEBC2E", "#28C840")):
        s.append(f'<circle cx="{x+16+i*15}" cy="{y+14}" r="4.5" fill="{c}"></circle>')
    s.append(t(x + w / 2, y + 18, "Claude", 12, "#3A3A40", 600, "middle"))
    s.append(f'<rect x="{x}" y="{y+28}" width="{side}" height="{h-28}" fill="#F4F5F7"></rect>'
             f'<path d="M{x} {y+h-10}a10 10 0 0 0 10 10h{side-10}v-10Z" fill="#F4F5F7"></path>')
    for i, item in enumerate(("New chat", "Projects", "Code")):
        s.append(t(x + 14, y + 52 + i * 22, item, 11.5, "#3A3A40"))
    # the account chip — the one thing that tells two windows apart
    cy = y + h - 44
    s.append(f'<rect x="{x+8}" y="{cy}" width="{side-16}" height="36" rx="7" fill="#FFFFFF" stroke="#E2E3E8"></rect>')
    if badge_letter:
        s.append(badge(x + 22, cy + 18, 8, badge_letter, badge_color))
        tx = x + 36
    else:
        tx = x + 16
    fs = 8.4 if badge_letter else 9.5   # leave room for the badge
    s.append(t(tx, cy + 15, account, fs, "#1D1D1F", 600))
    s.append(t(tx, cy + 28, plan, fs, "#5F5F66"))
    return "".join(s), (x + side + 16, y + 44)   # content origin

def terminal(sc, x, y, w, h, title="Terminal"):
    s = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="9" fill="#14171C" stroke="#2B2F36"></rect>',
         f'<path d="M{x} {y+9}a9 9 0 0 1 9-9h{w-18}a9 9 0 0 1 9 9v13H{x}Z" fill="#1F232A"></path>']
    for i, c in enumerate(("#FF5F57", "#FEBC2E", "#28C840")):
        s.append(f'<circle cx="{x+14+i*13}" cy="{y+11}" r="4" fill="{c}"></circle>')
    s.append(t(x + w / 2, y + 15, title, 10.5, "#8B949E", anchor="middle"))
    return "".join(s)

# The Claude app icon's starburst, simplified: (angle°, length as a fraction of the tile) per ray,
# uneven like the real one.
SPARK = [(-4, .37), (24, .27), (52, .36), (83, .30), (112, .38), (143, .26),
         (172, .36), (203, .30), (236, .38), (262, .27), (293, .35), (322, .29)]

def spark(cx, cy, size, fill="#FEFCFB"):
    import math
    out = []
    for a, l in SPARK:
        r, w = math.radians(a), size * 0.032
        ex, ey = cx + math.cos(r) * size * l, cy + math.sin(r) * size * l
        px, py = -math.sin(r) * w, math.cos(r) * w
        out.append(f'<path d="M{cx+px:.2f} {cy+py:.2f}L{ex+px*.35:.2f} {ey+py*.35:.2f}'
                   f'L{ex-px*.35:.2f} {ey-py*.35:.2f}L{cx-px:.2f} {cy-py:.2f}Z" '
                   f'stroke="{fill}" stroke-width="{size*0.02:.2f}" stroke-linejoin="round"></path>')
    return f'<g fill="{fill}">{"".join(out)}<circle cx="{cx}" cy="{cy}" r="{size*0.06:.2f}"></circle></g>'

def tile(cx, cy, size, color, glyph="spark"):
    s = [f'<rect x="{cx-size/2}" y="{cy-size/2}" width="{size}" height="{size}" rx="{size*0.23}" fill="{color}"></rect>']
    if glyph == "spark":
        s.append(spark(cx, cy, size))
    elif glyph == "bubble":   # a generic chat bubble, not Claude's mark
        r = size * 0.22
        s.append(f'<rect x="{cx-r*1.3}" y="{cy-r}" width="{r*2.6}" height="{r*1.8}" rx="{r*0.7}" fill="#FFFFFF"></rect>'
                 f'<path d="M{cx-r*0.6} {cy+r*0.75} l-{r*0.5} {r*0.6} l{r*1.0} -{r*0.6}Z" fill="#FFFFFF"></path>')
    elif glyph == "term":
        s.append(t(cx, cy + size * 0.12, ">_", size * 0.36, "#FFFFFF", 700, "middle", MONO))
    elif glyph == "folder":
        s.append(f'<rect x="{cx-size*0.28}" y="{cy-size*0.14}" width="{size*0.56}" height="{size*0.36}" rx="3" fill="#FFFFFF" opacity="0.9"></rect>')
    return "".join(s)

def dock(sc, y, items):
    """items: list of (kind, t_on, extras) — drawn left to right, centred."""
    size, gap = 40, 12
    wtot = len(items) * size + (len(items) - 1) * gap + 28
    x0 = (sc.w - wtot) / 2
    sc.add(f'<rect x="{x0}" y="{y}" width="{wtot}" height="{size+18}" rx="16" fill="#FFFFFF" opacity="0.72" stroke="#D4D6DC"></rect>')
    return [x0 + 14 + i * (size + gap) + size / 2 for i in range(len(items))], y + 9 + size / 2, size

POINTER = ('<path d="M0 0 L0 17 L4.6 12.6 L7.6 19.6 L10.4 18.4 L7.4 11.6 L13.4 11.6 Z" '
           'fill="#111111" stroke="#FFFFFF" stroke-width="1.2" stroke-linejoin="round"></path>')


# ============================================================ 1. two accounts
def profiles():
    sc = Scene(900, 560, 17.0)
    desktop(sc)
    # window A: the account you already had
    wa, (ax, ay) = window(sc, 24, 40, 414, 286, "you@personal.com", "Max")
    sc.add(wa)
    sc.add(t(ax, ay + 4, "Morning brief", 13, weight=700) +
           f'<rect x="{ax}" y="{ay+16}" width="250" height="9" rx="4.5" fill="#E7E8EC"></rect>'
           f'<rect x="{ax}" y="{ay+32}" width="210" height="9" rx="4.5" fill="#E7E8EC"></rect>'
           f'<rect x="{ax}" y="{ay+48}" width="232" height="9" rx="4.5" fill="#E7E8EC"></rect>')
    # terminal: create the profile, open it
    sc.add(terminal(sc, 24, 340, 852, 132, "tandem — zsh"))
    tx, ty, lh = 40, 372, 17
    p = lambda r: ty + r * lh
    sc.add(t(tx, p(0), "$", 12, "#57AB5A", family=MONO), 0.6, 8.6)
    sc.typed(tx + 14, p(0), "tandem profile create work", 0.8, 8.6)
    sc.add(t(tx, p(1), "  ✓ config: ~/.claude-work   ✓ desktop data: …/Claude-work", 12, "#8B949E", family=MONO), 2.0, 8.6)
    sc.add(t(tx, p(2), "  ✓ shared skills, settings.json, CLAUDE.md, plugins, agents, commands", 12, "#8B949E", family=MONO), 2.3, 8.6)
    sc.add(t(tx, p(3), "$", 12, "#57AB5A", family=MONO), 2.9, 8.6)
    sc.typed(tx + 14, p(3), "tandem profile desktop work", 3.0, 8.6)
    sc.add(t(tx, p(4), "  ✓ opened Claude as 'work'", 12, "#57AB5A", family=MONO), 4.1, 8.6)
    # then: list
    sc.add(t(tx, p(0), "$", 12, "#57AB5A", family=MONO), 8.7)
    sc.typed(tx + 14, p(0), "tandem profile list", 8.8)
    sc.add(t(tx, p(1), "PROFILE    CODE (terminal)              DESKTOP             OPEN", 12, "#8B949E", family=MONO), 9.6)
    sc.add(t(tx, p(2), "default    you@personal.com (max)       account c9390ef8    yes", 12, "#E6EDF3", family=MONO), 9.8)
    sc.add(t(tx, p(3), "work       you@company.com (team)       account d37cdc9d    yes", 12, "#E6EDF3", family=MONO), 10.0)
    # window B: sign-in, then signed in
    sc.add(f'<rect x="462" y="40" width="414" height="286" rx="10" fill="#FFFFFF" stroke="#C9CBD1"></rect>'
           + t(669, 160, "Sign in to Claude", 15, weight=700, anchor="middle")
           + f'<rect x="579" y="178" width="180" height="32" rx="8" fill="#1D1D1F"></rect>'
           + t(669, 199, "Continue with email", 12, "#FFFFFF", 600, "middle")
           + t(669, 232, "use a private browser window", 10.5, "#5F5F66", anchor="middle"), 4.4, 6.4)
    wb, (bx, by) = window(sc, 462, 40, 414, 286, "you@company.com", "Team", "W", TEAL)
    sc.add(wb + t(bx, by + 4, "Q4 launch plan", 13, weight=700)
           + f'<rect x="{bx}" y="{by+16}" width="236" height="9" rx="4.5" fill="#E7E8EC"></rect>'
           + f'<rect x="{bx}" y="{by+32}" width="196" height="9" rx="4.5" fill="#E7E8EC"></rect>', 6.4)
    # dock: one Claude, then a second one wearing the profile's badge
    xs, cy, size = dock(sc, 488, ["finder", "claude", "claude-w", "term"])
    sc.add(tile(xs[0], cy, size, "#5B8DEF", "folder"))
    sc.add(tile(xs[1], cy, size, CLAUDE_TILE) + f'<circle cx="{xs[1]}" cy="{cy+size/2+5}" r="2" fill="#3A3A40"></circle>')
    sc.add(tile(xs[3], cy, size, "#2B2F36", "term") + f'<circle cx="{xs[3]}" cy="{cy+size/2+5}" r="2" fill="#3A3A40"></circle>')
    sc.add(tile(xs[2], cy, size, CLAUDE_TILE) + f'<circle cx="{xs[2]}" cy="{cy+size/2+5}" r="2" fill="#3A3A40"></circle>', 4.4)
    sc.add(badge(xs[2] + 13, cy + 13, 8, "W", TEAL), 6.8)
    sc.write("profiles-demo.svg")


# ============================================================ 2. to the other account
def handoff_accounts():
    sc = Scene(900, 540, 20.0)
    desktop(sc)
    wa, (ax, ay) = window(sc, 24, 36, 414, 282, "you@personal.com", "Max")
    sc.add(wa + t(ax, ay + 4, "Film Kit", 13, weight=700))
    sc.add(f'<rect x="{ax}" y="{ay+14}" width="250" height="40" rx="7" fill="#FFF4E5" stroke="#F0C68A"></rect>'
           + t(ax + 10, ay + 30, "Approaching your usage limit", 11, AMBER, 700)
           + t(ax + 10, ay + 45, "— hand off now, while /handoff can run", 10.5, "#6B3A00"), 0.6)
    sc.add(f'<rect x="{ax+150}" y="{ay+64}" width="100" height="26" rx="13" fill="#E9EAEE"></rect>', 1.3)
    sc.typed(ax + 164, ay + 81, "/handoff", 1.4, size=12, color="#1D1D1F")
    sc.add(t(ax, ay + 112, "Wrote HANDOFF_film_kit.md:", 11.5, weight=600)
           + t(ax, ay + 128, "task · status · next steps · gotchas", 11.5, "#5F5F66"), 2.4)
    wb, (bx, by) = window(sc, 462, 36, 414, 282, "you@company.com", "Team", "W", TEAL)
    sc.add(wb + t(bx, by + 4, "Film Kit", 13, weight=700, fill="#9A9AA2"))
    sc.add(f'<rect x="{bx+44}" y="{by+18}" width="204" height="44" rx="12" fill="#E9EAEE"></rect>'
           + t(bx + 56, by + 36, "Pasted · HANDOFF_film_kit.md", 11, weight=600)
           + t(bx + 56, by + 52, "task · status · next steps …", 10.5, "#5F5F66"), 10.4)
    sc.add(t(bx, by + 86, "Read it — picking up at the edit pass.", 11.5)
           + t(bx, by + 102, "The project's memory came across too.", 11.5, "#5F5F66"), 11.6)
    # terminal: send, then receive as the other account (output shortened)
    sc.add(terminal(sc, 24, 332, 852, 196, "tandem — zsh"))
    tx, ty, lh = 40, 364, 17
    p = lambda r: ty + r * lh
    M = dict(size=12, family=MONO)
    sc.add(t(tx, p(0), "$", fill="#57AB5A", **M), 3.0)
    sc.typed(tx + 14, p(0), 'tandem send "Film Kit" --to Madoka@work', 3.1)
    sc.add(t(tx, p(1), "sending 'Film Kit': Madoka -> Madoka@work", fill="#E6EDF3", **M), 4.6)
    sc.add(t(tx, p(2), "  memory: 12 file(s) -> .handoff/memory/", fill="#8B949E", **M), 4.9)
    sc.add(t(tx, p(3), "  ✓ all 14 files uploaded to the drive in 6s", fill="#57AB5A", **M), 5.6)
    sc.add(t(tx, p(5), "$", fill="#57AB5A", **M), 6.6)
    sc.typed(tx + 14, p(5), 'tandem --profile work receive "Film Kit"', 6.7)
    sc.add(t(tx, p(6), "  ✓ all 14 files delivered and verified by md5", fill="#57AB5A", **M), 8.3)
    sc.add(t(tx, p(7), "  merged memory from Madoka: 12 added, 0 clash", fill="#8B949E", **M), 8.7)
    sc.add(t(tx, p(8), "claimed by Madoka@work · HANDOFF_film_kit.md copied — ⌘V in Cowork", fill="#C9A4FF", **M), 9.2)
    sc.write("accounts-handoff-demo.svg")


# ============================================================ 3. the menu bar
def menubar():
    sc = Scene(900, 470, 15.0)
    icon_x = desktop(sc)
    sc.add(f'<circle cx="{icon_x+10}" cy="7" r="3.2" fill="#F5A623" stroke="#F7F7F9"></circle>')   # something waits
    # a window behind, for depth
    w_, _ = window(sc, 40, 70, 420, 300, "you@personal.com", "Max")
    sc.add(w_)
    # the dropdown
    dx, dy, dw = 536, 28, 344
    # the inbox comes first (the icon wears a dot while something waits), then the profiles
    head = t(dx + 14, dy + 22, "Waiting for you", 10.5, "#5F5F66", 600) + t(dx + 14, dy + 44, "↓ Receive Film Kit as work — from default on Ji-su", 12)
    def prow(y, letter, color, name, sub, sub2, sub2c):
        return (badge(dx + 26, y + 16, 11, letter, color)
                + t(dx + 46, y + 13, name, 12.5, weight=700)
                + t(dx + 46, y + 28, sub, 10.5, "#5F5F66")
                + t(dx + 46 + len(sub) * 5.6, y + 28, sub2, 10.5, sub2c))
    py = dy + 62
    base = (f'<rect x="{dx}" y="{dy}" width="{dw}" height="262" rx="10" fill="#FFFFFF" stroke="#D2D2D7"></rect>'
            + head
            + f'<line x1="{dx+10}" y1="{dy+56}" x2="{dx+dw-10}" y2="{dy+56}" stroke="#E5E5EA"></line>'
            + t(dx + 14, py + 16, "Claude profiles on Madoka", 10.5, "#5F5F66", 600)
            + prow(py + 24, "A", GRAPH, "default", "you@personal.com · Max  ·  ", "Open", "#1F7A3A")
            + f'<line x1="{dx+10}" y1="{py+114}" x2="{dx+dw-10}" y2="{py+114}" stroke="#E5E5EA"></line>'
            + t(dx + 14, py + 136, "Open Claude Tandem…", 12)
            + t(dx + 14, py + 158, "Settings…", 12) + t(dx + dw - 16, py + 158, "⌘,", 12, "#8E8E93", anchor="end")
            + f'<line x1="{dx+10}" y1="{py+168}" x2="{dx+dw-10}" y2="{py+168}" stroke="#E5E5EA"></line>'
            + t(dx + 14, py + 188, "Quit Claude Tandem", 12) + t(dx + dw - 16, py + 188, "⌘Q", 12, "#8E8E93", anchor="end"))
    sc.add(base, 1.7, 6.2)
    work_row = (prow(py + 64, "W", TEAL, "work", "you@company.com · Team  ·  ", "4 earlier sessions", BLUE)
                + t(dx + dw - 16, py + 86, "›", 14, "#8E8E93", anchor="end"))
    sc.add(work_row, 1.7, 3.1)
    sc.add(f'<rect x="{dx+6}" y="{py+62}" width="{dw-12}" height="44" rx="6" fill="{BLUE}"></rect>'
           + badge(dx + 26, py + 80, 11, "W", TEAL)
           + t(dx + 46, py + 77, "work", 12.5, "#FFFFFF", 700)
           + t(dx + 46, py + 92, "you@company.com · Team  ·  4 earlier sessions", 10.5, "#DCE6FF")
           + t(dx + dw - 16, py + 86, "›", 14, "#FFFFFF", anchor="end"), 3.1, 6.2)
    # the profile's submenu, opening to the left
    sx, sy, sw = 206, 132, 320
    items = ["Show Claude", "Open Claude Code in Terminal", "Quit Claude", None,
             "Receive Film Kit — from default on Ji-su", "Hand Off  ›", None,
             "Bring In Earlier Sessions (4)…", "Show in Claude Tandem…"]
    s = [f'<rect x="{sx}" y="{sy}" width="{sw}" height="{28 + len(items) * 20}" rx="10" fill="#FFFFFF" stroke="#D2D2D7"></rect>',
         t(sx + 14, sy + 20, "Madoka@work — id work", 10.5, "#5F5F66", 600)]
    y = sy + 30
    for it in items:
        if it is None:
            s.append(f'<line x1="{sx+10}" y1="{y+4}" x2="{sx+sw-10}" y2="{y+4}" stroke="#E5E5EA"></line>'); y += 10; continue
        s.append(t(sx + 14, y + 14, it, 12)); y += 22
    sc.add("".join(s), 3.5, 6.2)
    bring_y = sy + 30 + 22 * 5 + 10 * 2   # the "Bring In" row: 5 rows and 2 separators above it
    sc.add(f'<rect x="{sx+6}" y="{bring_y}" width="{sw-12}" height="21" rx="5" fill="{BLUE}"></rect>'
           + t(sx + 14, bring_y + 14, "Bring In Earlier Sessions (4)…", 12, "#FFFFFF"), 5.0, 6.2)
    # the wizard's question
    ax, ay, aw = 250, 110, 400
    alert = (f'<rect x="{ax}" y="{ay}" width="{aw}" height="232" rx="14" fill="#FFFFFF" stroke="#C9CBD1"></rect>'
             + badge(ax + aw / 2, ay + 34, 16, "W", TEAL)
             + t(ax + aw / 2, ay + 76, "Bring work’s earlier work in?", 14, weight=700, anchor="middle")
             + t(ax + aw / 2, ay + 98, "This account was used in your regular Claude", 11, "#3A3A40", anchor="middle")
             + t(ax + aw / 2, ay + 113, "before it had a profile. 4 Claude Code sessions:", 11, "#3A3A40", anchor="middle")
             + t(ax + aw / 2, ay + 132, "AI Video Editing Kit · Apify evaluation · …", 11, "#5F5F66", anchor="middle")
             + t(ax + aw / 2, ay + 148, "Copied — your regular Claude keeps its own.", 11, "#5F5F66", anchor="middle")
             + f'<rect x="{ax+20}" y="{ay+164}" width="{aw-40}" height="26" rx="7" fill="{BLUE}"></rect>'
             + t(ax + aw / 2, ay + 181, "Copy Them", 12, "#FFFFFF", 600, "middle")
             + f'<rect x="{ax+20}" y="{ay+196}" width="{(aw-50)/2}" height="24" rx="7" fill="#E9EAEE"></rect>'
             + t(ax + 20 + (aw - 50) / 4, ay + 212, "Not Now", 11.5, anchor="middle")
             + f'<rect x="{ax+30+(aw-50)/2}" y="{ay+196}" width="{(aw-50)/2}" height="24" rx="7" fill="#E9EAEE"></rect>'
             + t(ax + 30 + 3 * (aw - 50) / 4, ay + 212, "Never for This Profile", 11.5, anchor="middle"))
    sc.add(alert, 6.5, 9.4)
    sc.add(f'<rect x="300" y="196" width="300" height="56" rx="12" fill="#1D1D1F" opacity="0.92"></rect>'
           + t(450, 220, "Done", 13, "#FFFFFF", 700, "middle")
           + t(450, 238, "4 sessions are now in work’s Code tab.", 11, "#E5E5EA", anchor="middle"), 9.6)
    # the pointer: to the icon, click, down to work, into the submenu, Bring In, Copy Them
    sc.moving(POINTER, [(0.0, 470, 300), (1.4, icon_x, 10), (2.4, icon_x - 40, 100),
                        (3.0, 760, py + 84), (4.2, 520, py + 84), (4.9, 470, bring_y + 8),
                        (6.0, 470, bring_y + 8), (7.6, 450, ay + 176), (9.4, 450, ay + 176),
                        (11.0, 700, 380)])
    sc.write("menubar-demo.svg")


# ============================================================ shared: Claude Tandem's own window
def tandem_window(x, y, w, h, title, selected, side_w=128, badge_n=0, profiles=(("A", GRAPH, "default"), ("W", TEAL, "work")),
                  subtitle="", refresh=True, setup_left=0):
    """The app's window: a sidebar (Get Started while unfinished, Handoffs, Macs, the profiles) and a content
    area whose title bar names the page, sums it up, and holds its ↻ Check Now. Settings is its own window."""
    s = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="#FFFFFF" stroke="#C9CBD1"></rect>',
         f'<path d="M{x} {y+10}a10 10 0 0 1 10-10h{side_w-10}v{h}h-{side_w-10}a10 10 0 0 1 -10-10Z" fill="#F1F2F5"></path>']
    for i, c in enumerate(("#FF5F57", "#FEBC2E", "#28C840")):
        s.append(f'<circle cx="{x+16+i*15}" cy="{y+16}" r="4.5" fill="{c}"></circle>')
    s.append(t(x + side_w + 16, y + (17 if subtitle else 21), title, 13, "#1D1D1F", 700))
    if subtitle:
        s.append(t(x + side_w + 16, y + 31, subtitle, 10, "#6E6E73"))
    if refresh:
        s.append(f'<circle cx="{x+w-22}" cy="{y+20}" r="11" fill="#EDEEF1"></circle>' + t(x + w - 22, y + 24.5, "↻", 12, "#3A3A40", 600, "middle"))
    rows = ([("setup", "☑", "Get Started")] if setup_left else []) + [("handoffs", "⇄", "Handoffs"), ("macs", "▭", "Macs")]
    yy = y + 46
    for key, ic, label in rows:
        if key == selected:
            s.append(f'<rect x="{x+8}" y="{yy-14}" width="{side_w-16}" height="21" rx="6" fill="#DCDDE2"></rect>')
        s.append(t(x + 20, yy + 1, ic, 11, BLUE, 700, "middle") + t(x + 32, yy + 1, label, 11.5, "#1D1D1F", 600 if key == selected else 400))
        if key == "setup":
            s.append(t(x + side_w - 22, yy + 1, str(setup_left), 9.5, "#8E8E93", 600, "middle"))
        if key == "handoffs" and badge_n:
            s.append(f'<rect x="{x+side_w-34}" y="{yy-10}" width="18" height="14" rx="7" fill="#C7C8CE"></rect>'
                     + t(x + side_w - 25, yy + 1, str(badge_n), 9.5, "#1D1D1F", 700, "middle"))
        yy += 24
    s.append(t(x + 14, yy + 6, "Profiles", 9.5, "#8E8E93", 600)); yy += 26
    plans = {"default": "Max", "work": "Team"}
    for letter, color, name in profiles:
        wide = side_w >= 180   # room for the status in words under the name
        s.append(badge(x + 24, yy - (0 if wide else 4), 9 if wide else 8, letter, color) + t(x + 40, yy - (3 if wide else 0), name, 11.5, weight=600 if wide else 400)
                 + (t(x + 40, yy + 10, plans.get(name, "Pro") + " · Claude open", 9.5, "#6E6E73") if wide else "")
                 + f'<circle cx="{x+side_w-16}" cy="{yy-4}" r="3" fill="#34C759"></circle>')
        yy += 32 if wide else 24
    return "".join(s), (x + side_w + 16, y + 44)

def step_icon(cx, cy, state):
    if state == "done":
        return (f'<circle cx="{cx}" cy="{cy}" r="6" fill="#34C759"></circle>'
                f'<path d="M{cx-3} {cy} l2.2 2.3 l4-4.4" fill="none" stroke="#FFFFFF" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"></path>')
    if state == "wait":
        return (f'<circle cx="{cx}" cy="{cy}" r="5.5" fill="none" stroke="#E08A00" stroke-width="1.3"></circle>'
                f'<rect x="{cx-2.3}" y="{cy-2.5}" width="1.5" height="5" fill="#E08A00"></rect><rect x="{cx+0.8}" y="{cy-2.5}" width="1.5" height="5" fill="#E08A00"></rect>')
    return f'<circle cx="{cx}" cy="{cy}" r="5.5" fill="none" stroke="#A1A1A8" stroke-width="1.3" stroke-dasharray="2 1.6"></circle>'

def job(sc, x, y, w, title, steps, t0, t_end, progress=None):
    """A job card as the Handoffs page shows it: title, then one line per step as the CLI reports it.
    steps: (label, detail, t_done, final_state)."""
    sc.add(t(x, y, "In progress", 10, "#8E8E93", 600)
           + f'<rect x="{x-8}" y="{y+8}" width="{w}" height="{30 + len(steps) * 19 + (16 if progress else 0)}" rx="8" fill="#F6F6F8" stroke="#E2E3E8"></rect>', t0)
    sc.add(t(x + 16, y + 28, title, 11.5, weight=700), t0)
    sc.add(f'<circle cx="{x+4}" cy="{y+24}" r="5" fill="none" stroke="#A1A1A8" stroke-width="1.5" stroke-dasharray="7 4"></circle>', t0, t_end)
    sc.add(step_icon(x + 4, y + 24, "done"), t_end)
    for i, (label, detail, td, state) in enumerate(steps):
        yy = y + 48 + i * 19
        sc.add(step_icon(x + 10, yy - 4, "pending") + t(x + 22, yy, label, 10.5, "#8E8E93"), t0, td)
        sc.add(step_icon(x + 10, yy - 4, state) + t(x + 22, yy, label + (f" — {detail}" if detail else ""), 10.5,
                                                    "#1D1D1F"), td)
    if progress:
        yy = y + 48 + len(steps) * 19
        for (frac, txt, a, b) in progress:
            sc.add(f'<rect x="{x+22}" y="{yy-7}" width="90" height="6" rx="3" fill="#E2E3E8"></rect>'
                   f'<rect x="{x+22}" y="{yy-7}" width="{90*frac:.0f}" height="6" rx="3" fill="{BLUE}"></rect>'
                   + t(x + 120, yy, txt, 9.5, "#5F5F66", family=MONO), a, b)

def note(x, y, w, title, body, button=None):
    """A macOS notification banner from Claude Tandem, with its action button."""
    h = 66 if button else 54
    s = (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="#FBFBFD" stroke="#D2D2D7"></rect>'
         f'<rect x="{x+10}" y="{y+11}" width="28" height="28" rx="7" fill="#1D1D1F"></rect>'
         + menubar_icon(x + 24, y + 25, 0.8, 1.2, "#FFFFFF")
         + t(x + 46, y + 21, title, 11, weight=700) + t(x + 46, y + 37, body, 10, "#3A3A40"))
    if button:
        bw = len(button) * 6.4 + 22
        s += (f'<rect x="{x+w-bw-10}" y="{y+h-22}" width="{bw}" height="16" rx="5" fill="#E3E4E8"></rect>'
              + t(x + w - bw / 2 - 10, y + h - 10.5, button, 9.5, "#1D1D1F", 600, "middle"))
        return s, (x + w - bw / 2 - 10, y + h - 14)
    return s, None


# ============================================================ 4. a handoff through the app — no terminal
def handoff_app():
    sc = Scene(900, 600, 26.0)
    sc.add(f'<rect width="900" height="600" rx="14" fill="#E7E9EE"></rect>')
    for x0, mac in ((0, "Madoka"), (452, "Ji-su")):
        sc.add(f'<rect x="{x0+4}" y="4" width="444" height="592" rx="11" fill="#DDE0E6"></rect>'
               f'<rect x="{x0+4}" y="4" width="444" height="22" rx="11" fill="#F7F7F9"></rect>'
               + t(x0 + 18, 19, mac, 11.5, weight=700) + menubar_icon(x0 + 400, 15) + t(x0 + 438, 19, "9:41", 10.5, anchor="end"))

    # ---- Madoka: the session writes the brief
    wa, (ax, ay) = window(sc, 14, 36, 424, 250, "you@personal.com", "Max")
    sc.add(wa + t(ax, ay + 4, "Film Kit", 13, weight=700))
    sc.add(f'<rect x="{ax+150}" y="{ay+16}" width="100" height="26" rx="13" fill="#E9EAEE"></rect>', 0.6)
    sc.typed(ax + 164, ay + 33, "/handoff", 0.7, size=12, color="#1D1D1F")
    sc.add(t(ax, ay + 66, "Wrote HANDOFF_film_kit.md", 11.5, weight=600)
           + t(ax, ay + 82, "and left a note for Tandem: to Ji-su", 11, "#5F5F66"), 1.7)

    # Tandem asks to send it
    n1, b1 = note(140, 32, 300, "Send Film Kit to default on Ji-su?", "/handoff wrote HANDOFF_film_kit.md", "Send…")
    sc.add(n1, 2.8, 4.4)
    # the send sheet
    sx, sy = 70, 110
    sheet = (f'<rect x="{sx}" y="{sy}" width="310" height="150" rx="12" fill="#FFFFFF" stroke="#C9CBD1"></rect>'
             + t(sx + 18, sy + 28, "Hand off Film Kit", 14, weight=700)
             + t(sx + 18, sy + 54, "From", 11, "#5F5F66") + t(sx + 70, sy + 54, "default on this Mac", 11)
             + t(sx + 18, sy + 76, "To", 11, "#5F5F66")
             + f'<rect x="{sx+66}" y="{sy+63}" width="150" height="19" rx="5" fill="#F1F2F5" stroke="#D2D2D7"></rect>'
             + t(sx + 74, sy + 77, "default on Ji-su   ⌄", 11)
             + t(sx + 18, sy + 100, "Note", 11, "#5F5F66") + t(sx + 70, sy + 100, "edit pass next", 11)
             + f'<rect x="{sx+176}" y="{sy+116}" width="56" height="22" rx="6" fill="#E9EAEE"></rect>'
             + t(sx + 204, sy + 131, "Cancel", 11, anchor="middle")
             + f'<rect x="{sx+240}" y="{sy+116}" width="56" height="22" rx="6" fill="{BLUE}"></rect>'
             + t(sx + 268, sy + 131, "Send", 11, "#FFFFFF", 600, "middle"))
    sc.add(sheet, 4.5, 6.0)
    send_btn = (sx + 268, sy + 128)

    # Madoka's Tandem window: the send, step by step
    tw, (tx, ty) = tandem_window(14, 296, 424, 292, "Handoffs", "handoffs")
    sc.add(tw)
    idle = lambda x, y: (t(x, y + 8, "Waiting for you", 10, "#8E8E93", 600)
                         + f'<rect x="{x-8}" y="{y+16}" width="266" height="30" rx="8" fill="#F6F6F8" stroke="#E2E3E8"></rect>'
                         + t(x + 4, y + 35, "Nothing waiting.", 10.5, "#5F5F66"))
    sc.add(idle(tx + 8, ty), None, 6.1)
    job(sc, tx + 8, ty + 8, 266, "Hand off Film Kit → default on Ji-su", [
        ("Brief", "HANDOFF_film_kit.md", 6.5, "done"),
        ("Files ready, manifest and memory snapshot", "", 7.2, "done"),
        ("Ownership event", "Ji-su", 7.8, "done"),
        ("Uploaded to the drive", "", 9.6, "done"),
    ], 6.1, 9.6, progress=[(6/14, " 6/14 files uploaded", 8.0, 8.8),
                           (1.0, "14/14 files uploaded", 8.8, None)])
    n2, _ = note(140, 32, 300, "Film Kit is on its way to default on Ji-su", "Every file is uploaded. You’ll hear when it’s received.")
    sc.add(n2, 10.0, 12.0)

    # ---- Ji-su: told, one click, verified
    wb, (bx, by) = window(sc, 466, 36, 424, 250, "you@personal.com", "Max")
    sc.add(wb)
    sc.add(t(bx, by + 4, "Morning brief", 13, weight=700)
           + f'<rect x="{bx}" y="{by+16}" width="220" height="9" rx="4.5" fill="#E7E8EC"></rect>'
           + f'<rect x="{bx}" y="{by+32}" width="180" height="9" rx="4.5" fill="#E7E8EC"></rect>', None, 17.6)
    n3, b3 = note(592, 32, 300, "Film Kit arrived from default on Madoka", "For default on this Mac · edit pass next", "Receive")
    sc.add(n3, 11.2, 12.9)
    tw2, (ux, uy) = tandem_window(466, 296, 424, 292, "Handoffs", "handoffs", profiles=(("A", GRAPH, "default"),))
    sc.add(tw2)
    sc.add(idle(ux + 8, uy), None, 13.0)
    job(sc, ux + 8, uy + 8, 266, "Receive Film Kit as default on this Mac", [
        ("Ownership event", "Madoka", 13.3, "done"),
        ("Every file verified (md5)", "", 14.3, "done"),
        ("Project defined here", "not needed", 14.7, "done"),
        ("Claimed", "", 15.0, "done"),
        ("Memory merged", "when Claude quits", 15.4, "wait"),
        ("Brief", "HANDOFF_film_kit.md", 15.7, "done"),
    ], 13.0, 15.7)
    ob = (ux + 8 + 258 - 50, uy + 8 + 176)
    sc.add(f'<rect x="{ob[0]-50}" y="{ob[1]-12}" width="100" height="22" rx="6" fill="{BLUE}"></rect>'
           + t(ob[0], ob[1] + 3, "Open in Claude", 11, "#FFFFFF", 600, "middle"), 15.9)
    # Claude on Ji-su, with the brief pasted
    sc.add(f'<rect x="{bx}" y="{by-14}" width="270" height="200" fill="#FFFFFF"></rect>'
           + t(bx, by + 4, "Film Kit", 13, weight=700)
           + f'<rect x="{bx+40}" y="{by+16}" width="220" height="44" rx="12" fill="#E9EAEE"></rect>'
           + t(bx + 52, by + 34, "Pasted · HANDOFF_film_kit.md", 11, weight=600)
           + t(bx + 52, by + 50, "task · status · next steps …", 10.5, "#5F5F66")
           + t(bx, by + 84, "Read it — picking up at the edit pass.", 11.5), 17.6)
    # and Madoka hears it landed
    n4, _ = note(140, 32, 300, "Film Kit was received", "default on Ji-su verified every file and holds it now.")
    sc.add(n4, 18.6)

    sc.moving(POINTER, [(0.0, 300, 420), (3.6, b1[0], b1[1]), (4.4, b1[0], b1[1]), (5.4, send_btn[0], send_btn[1]),
                        (6.0, send_btn[0], send_btn[1]), (10.6, 640, 200), (12.2, b3[0], b3[1]), (12.9, b3[0], b3[1]),
                        (16.6, ob[0], ob[1]), (17.6, ob[0], ob[1]), (19.0, 760, 230)])
    sc.write("handoff-app-demo.svg")


# ============================================================ 5. the window: what is where
def window_tour():
    sc = Scene(900, 500, 16.0)
    desktop(sc)
    X, Y, Wd, Hd = 30, 38, 840, 448
    content_x = X + 190 + 20
    for sel, a, b in (("handoffs", 0, 7.4), ("macs", 7.4, None)):
        w_, _ = tandem_window(X, Y, Wd, Hd, "Handoffs" if sel == "handoffs" else "Macs", sel, side_w=190,
                              badge_n=1 if sel == "handoffs" else 0,
                              subtitle="1 waiting · 3 shared" if sel == "handoffs" else "2 Macs · 2 online")
        sc.add(w_, a, b)
    # once received: nothing waits, so the subtitle and the sidebar count change
    sc.add(f'<rect x="{X+190+14}" y="{Y+23}" width="140" height="12" fill="#FFFFFF"></rect>' + t(X + 190 + 16, Y + 31, "3 shared", 10, "#6E6E73"), 3.6, 7.4)
    cx, cw = content_x, Wd - 190 - 40

    # ---- Handoffs
    def box(y, h): return f'<rect x="{cx}" y="{y}" width="{cw}" height="{h}" rx="9" fill="#F6F6F8" stroke="#E2E3E8"></rect>'
    hp = (t(cx + 8, Y + 98, "Waiting for you", 11, "#5F5F66", 600) + box(Y + 106, 54)
          + f'<circle cx="{cx+16}" cy="{Y+126}" r="4" fill="#34C759"></circle>'
          + t(cx + 28, Y + 130, "Film Kit — from default on Ji-su", 12.5, weight=700)
          + t(cx + 28, Y + 148, "For work on this Mac · sent 2 minutes ago · brief HANDOFF_film_kit.md", 10.5, "#5F5F66")
          + f'<rect x="{cx+cw-84}" y="{Y+120}" width="72" height="24" rx="7" fill="{BLUE}"></rect>'
          + t(cx + cw - 48, Y + 136, "Receive", 11.5, "#FFFFFF", 600, "middle")
          + t(cx + 8, Y + 186, "Shared projects", 11, "#5F5F66", 600) + box(Y + 194, 172))
    rows = [("Film Kit", "On its way to work on this Mac · sent 2 minutes ago by Ji-su", "", BLUE),
            ("Quicken Reconciliation", "With default on Ji-su · since 3 days ago", "“THW done, 7 securities left”", "#1D1D1F"),
            ("Adobe Stock Plan", "With default on this Mac · since 5 days ago", "“vest schedule checked through Q3”", "#1D1D1F")]
    yy = Y + 214
    for name, sub, quote, col in rows:
        hp += (t(cx + 16, yy + 2, "▱", 13, "#8E8E93") + t(cx + 36, yy + 2, name, 12.5, col, 700)
               + t(cx + 36, yy + 18, sub, 10.5, "#5F5F66") + (t(cx + 36, yy + 33, quote, 10, "#3A3A40") if quote else "")
               + t(cx + cw - 22, yy + 4, "⋯", 14, "#5F5F66", anchor="middle"))
        yy += 54 if quote else 42
    hp += (box(Y + 380, 34) + t(cx + 14, Y + 402, "›  Only on one Mac — 4 projects a handoff can’t reach yet", 11.5, weight=600)
           + f'<rect x="{cx+cw-170}" y="{Y+386}" width="160" height="22" rx="6" fill="#EDEEF1"></rect>'
           + t(cx + cw - 90, Y + 401, "Move to the Shared Drive  ⌄", 10.5, anchor="middle"))
    UP = 30   # the page heading is the title bar's now: content starts higher
    def lift(svg): return f'<g transform="translate(0,-{UP})">{svg}</g>'
    sc.add(lift(hp), 0, 7.4)
    done = (f'<rect x="{cx}" y="{Y+88}" width="{cw}" height="74" fill="#FFFFFF"></rect>'
            + t(cx + 8, Y + 98, "In progress", 11, "#5F5F66", 600) + box(Y + 106, 54)
            + step_icon(cx + 16, Y + 126, "done")
            + t(cx + 28, Y + 130, "Receive Film Kit as work on this Mac", 12.5, weight=700)
            + t(cx + 28, Y + 148, "Every file verified (md5) · Claimed · Memory merged · Brief HANDOFF_film_kit.md", 10.5, "#5F5F66")
            + f'<rect x="{cx+cw-112}" y="{Y+120}" width="100" height="24" rx="7" fill="{BLUE}"></rect>'
            + t(cx + cw - 62, Y + 136, "Open in Claude", 11.5, "#FFFFFF", 600, "middle")
            + f'<rect x="{cx+30}" y="{Y+205}" width="{cw-80}" height="34" fill="#F6F6F8"></rect>'
            + t(cx + 36, Y + 216, "Film Kit", 12.5, "#1D1D1F", 700)
            + t(cx + 36, Y + 232, "With work on this Mac · since just now", 10.5, "#5F5F66"))
    sc.add(lift(done), 3.6, 7.4)
    sc.add(f'<rect x="{X+190-36}" y="{Y+34}" width="22" height="18" fill="#DCDDE2"></rect>', 3.6, 7.4)   # the badge clears

    # ---- Macs
    def card(x, y, w, mac, status, dot, ver, drive, sides):
        h = 104 + len(sides) * 62
        s = (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="9" fill="#F6F6F8" stroke="#E2E3E8"></rect>'
             + f'<circle cx="{x+16}" cy="{y+22}" r="4.5" fill="{dot}"></circle>'
             + t(x + 28, y + 27, mac, 16, weight=800) + t(x + 28, y + 44, status, 10.5, "#5F5F66")
             + t(x + 14, y + 70, "Tandem", 10.5, "#5F5F66") + t(x + 90, y + 70, ver, 10.5)
             + t(x + 14, y + 88, "iCloud Drive", 10.5, "#5F5F66") + t(x + 90, y + 88, drive, 10.5))
        yy = y + 112
        for letter, color, name, side, acct, holds, coming in sides:
            s += (f'<line x1="{x+12}" y1="{yy-10}" x2="{x+w-12}" y2="{yy-10}" stroke="#E2E3E8"></line>'
                  + badge(x + 22, yy + 4, 8, letter, color) + t(x + 36, yy + 8, name, 11.5, weight=700)
                  + t(x + 36 + len(name) * 7 + 8, yy + 8, side, 9.5, "#8E8E93", family=MONO)
                  + t(x + w - 14, yy + 8, "Claude open", 9.5, "#1F7A3A", anchor="end")
                  + t(x + 36, yy + 24, acct, 10.5, "#5F5F66") + t(x + 36, yy + 39, holds, 10.5))
            if coming:
                s += t(x + 36, yy + 54, coming, 10.5, BLUE)
            yy += 62
        return s
    mp = (t(cx, Y + 80, "Each Mac running Tandem publishes a card every few minutes.", 11, "#5F5F66")
          + f'<circle cx="{cx+330}" cy="{Y+76}" r="5.5" fill="none" stroke="#8E8E93"></circle>' + t(cx + 330, Y + 79, "i", 8, "#8E8E93", 700, "middle")
          + card(cx, Y + 104, (cw - 14) / 2, "Madoka", "This Mac", "#34C759", "1.1.1", "In sync",
                 [("A", GRAPH, "default", "Madoka", "you@personal.com · Max", "Holds Adobe Stock Plan", None),
                  ("W", TEAL, "work", "Madoka@work", "you@company.com · Team", "Holds Film Kit", None)])
          + card(cx + (cw - 14) / 2 + 14, Y + 104, (cw - 14) / 2, "Ji-su", "Online · seen 1 min ago", "#34C759", "1.1.1", "In sync",
                 [("A", GRAPH, "default", "Ji-su", "you@personal.com · Max", "Holds Quicken Reconciliation", None)]))
    sc.add(lift(mp), 7.4)
    sc.moving(POINTER, [(0.0, 600, 470), (2.0, cx + cw - 48, Y + 134 - UP), (3.4, cx + cw - 48, Y + 134 - UP), (4.8, cx + cw - 120, Y + 300 - UP),
                        (6.6, X + 60, Y + 72), (7.6, X + 60, Y + 72), (10.0, cx + 300, Y + 400 - UP), (16.0, cx + 300, Y + 400 - UP)])
    sc.write("window-demo.svg")


profiles()
handoff_accounts()
menubar()
handoff_app()
window_tour()
