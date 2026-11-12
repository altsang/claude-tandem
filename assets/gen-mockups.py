#!/usr/bin/env python3
"""Render the README's animated mockups as self-contained SVGs.

Pure CSS keyframes — no script, no SMIL, no GIF — so GitHub plays them in an <img>.
Each element is shown or hidden on one shared loop, commands "type" through a
widening clip, and the pointer moves by animated translate. Claude's windows are
drawn schematically (Claude's Dock icon simplified, placeholder accounts). Terminal lines are the
tool's real output, shortened where marked.

    python3 assets/gen-mockups.py               # writes the six SVGs beside this file (gen-demo.py writes the seventh)
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
    sc.add(t(tx, p(4), "$", fill="#57AB5A", **M), 6.6)
    sc.typed(tx + 14, p(4), 'tandem --profile work receive "Film Kit"', 6.7)
    sc.add(t(tx, p(5), "  ✓ all 14 files delivered and verified by md5", fill="#57AB5A", **M), 8.3)
    sc.add(t(tx, p(6), "  from another account: Claude makes it a project in this one when it opens", fill="#8B949E", **M), 8.6)
    sc.add(t(tx, p(7), "  merged memory from Madoka: 12 added, 0 clash", fill="#8B949E", **M), 8.9)
    sc.add(t(tx, p(8), "claimed by Madoka@work · HANDOFF_film_kit.md copied — ⌘V in Claude", fill="#C9A4FF", **M), 9.3)
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
    work_row = (prow(py + 64, "W", TEAL, "work", "you@company.com · Team  ·  ", "4 earlier sessions to bring in", BLUE)
                + t(dx + dw - 16, py + 86, "›", 14, "#8E8E93", anchor="end"))
    sc.add(work_row, 1.7, 3.1)
    sc.add(f'<rect x="{dx+6}" y="{py+62}" width="{dw-12}" height="44" rx="6" fill="{BLUE}"></rect>'
           + badge(dx + 26, py + 80, 11, "W", TEAL)
           + t(dx + 46, py + 77, "work", 12.5, "#FFFFFF", 700)
           + t(dx + 46, py + 92, "you@company.com · Team  ·  4 earlier sessions to bring in", 10.5, "#DCE6FF")
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
    """The app's window: a sidebar (Get Started while unfinished, Inbox, Projects, Macs, the profiles) and a content
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
    rows = ([("setup", "☑", "Get Started")] if setup_left else []) + [("handoffs", "⊟", "Inbox"), ("projects", "▦", "Projects"), ("macs", "▭", "Macs")]
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
    """A job card as the Inbox shows it: title, then one line per step as the CLI reports it.
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
    lines = body.split("\n")   # a body may run to a second line
    h = (66 if button else 54) + 13 * (len(lines) - 1)
    s = (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="#FBFBFD" stroke="#D2D2D7"></rect>'
         f'<rect x="{x+10}" y="{y+11}" width="28" height="28" rx="7" fill="#1D1D1F"></rect>'
         + menubar_icon(x + 24, y + 25, 0.8, 1.2, "#FFFFFF")
         + t(x + 46, y + 21, title, 11, weight=700)
         + "".join(t(x + 46, y + 37 + 13 * i, ln, 10, "#3A3A40") for i, ln in enumerate(lines)))
    if button:
        bw = len(button) * 6.4 + 22
        s += (f'<rect x="{x+w-bw-10}" y="{y+h-22}" width="{bw}" height="16" rx="5" fill="#E3E4E8"></rect>'
              + t(x + w - bw / 2 - 10, y + h - 10.5, button, 9.5, "#1D1D1F", 600, "middle"))
        return s, (x + w - bw / 2 - 10, y + h - 14)
    return s, None


# ============================================================ 4. a handoff through the app — no terminal
def two_computers(sc, split):
    """Puts the scene's two halves on two computers: the left half on a desktop monitor
    (Madoka), the right half on a laptop (Ji-su), with a gap between them, so it can't be
    read as one screen running two Macs. The scene is drawn once and shown twice, each
    copy clipped to its half; the pointer and every timeline carry over unchanged."""
    body = "\n".join(sc.body)
    L, R = (34, 22), (100, 22)          # where each half's content lands
    W, H = sc.w + 130, sc.h + 104
    lx, ly = L; rx, ry = R
    mon = (f'<rect x="{lx-12}" y="{ly-12}" width="{split+24}" height="{sc.h+24}" rx="16" fill="#1D1D1F"></rect>'
           f'<rect x="{lx+split/2-22}" y="{ly+sc.h+12}" width="44" height="38" fill="#B9BCC4"></rect>'
           f'<rect x="{lx+split/2-80}" y="{ly+sc.h+48}" width="160" height="9" rx="4" fill="#A9ADB6"></rect>')
    sx0 = split + rx                    # the laptop screen's left edge
    lap = (f'<rect x="{sx0-10}" y="{ry-10}" width="{sc.w-split+20}" height="{sc.h+20}" rx="14" fill="#1D1D1F"></rect>'
           f'<path d="M{sx0-26} {ry+sc.h+10}h{sc.w-split+52}v6a8 8 0 0 1 -8 8h{-(sc.w-split+36)}a8 8 0 0 1 -8 -8Z" fill="#C3C6CD"></path>'
           f'<rect x="{sx0+(sc.w-split)/2-34}" y="{ry+sc.h+10}" width="68" height="5" rx="2.5" fill="#A9ADB6"></rect>')
    sc.body = [f'<rect width="{W}" height="{H}" rx="14" fill="#F2F3F6"></rect>', mon, lap,
               f'<defs><clipPath id="half-l"><rect x="0" y="0" width="{split}" height="{sc.h}" rx="4"></rect></clipPath>'
               f'<clipPath id="half-r"><rect x="{split}" y="0" width="{sc.w-split}" height="{sc.h}" rx="4"></rect></clipPath></defs>',
               f'<g transform="translate({lx},{ly})" clip-path="url(#half-l)">{body}</g>',
               f'<g transform="translate({rx},{ry})" clip-path="url(#half-r)">{body}</g>',
               t(lx + split / 2, H - 8, "Madoka — desktop", 11, "#6E6E73", 600, "middle"),
               t(sx0 + (sc.w - split) / 2, H - 8, "Ji-su — laptop", 11, "#6E6E73", 600, "middle")]
    sc.w, sc.h = W, H


def handoff_app():
    sc = Scene(900, 600, 26.0)
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
    tw, (tx, ty) = tandem_window(14, 296, 424, 292, "Inbox", "handoffs")
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
    tw2, (ux, uy) = tandem_window(466, 296, 424, 292, "Inbox", "handoffs", profiles=(("A", GRAPH, "default"),))
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
    # Open in Claude says where the project is: Claude has no link to a local project
    n5, _ = note(526, 32, 366, "Film Kit is in Claude (default)",
                 "Open it from Projects in Claude’s sidebar,\nstart a task, and paste: the brief is on the clipboard.")
    sc.add(n5, 17.0, 19.6)
    # and Madoka hears it landed
    n4, _ = note(140, 32, 300, "Film Kit was received", "default on Ji-su verified every file and holds it now.")
    sc.add(n4, 18.6)

    sc.moving(POINTER, [(0.0, 300, 420), (3.6, b1[0], b1[1]), (4.4, b1[0], b1[1]), (5.4, send_btn[0], send_btn[1]),
                        (6.0, send_btn[0], send_btn[1]), (10.6, 640, 200), (12.2, b3[0], b3[1]), (12.9, b3[0], b3[1]),
                        (16.6, ob[0], ob[1]), (17.6, ob[0], ob[1]), (19.0, 760, 230)])
    two_computers(sc, 452)
    sc.write("handoff-app-demo.svg")


# ============================================================ 5. the window: what is where
def mark(cx, cy, kind, color):
    """A cell of the Projects grid, as CellMark draws it: has it (dot), on its way (arrow.right.circle.fill),
    old copy (ring), only here (rounded square)."""
    if kind == "has":
        return f'<circle cx="{cx}" cy="{cy}" r="6" fill="{color}"></circle>'
    if kind == "old":
        return f'<circle cx="{cx}" cy="{cy}" r="5" fill="none" stroke="{color}" stroke-opacity="0.6" stroke-width="2"></circle>'
    if kind == "coming":
        return (f'<circle cx="{cx}" cy="{cy}" r="6.5" fill="{color}"></circle>'
                f'<path d="M{cx-3.2} {cy}h6M{cx+0.4} {cy-2.8}l2.8 2.8l-2.8 2.8" fill="none" stroke="#FFFFFF" stroke-width="1.5" '
                f'stroke-linecap="round" stroke-linejoin="round"></path>')
    return f'<rect x="{cx-6}" y="{cy-6}" width="12" height="12" rx="3" fill="{color}"></rect>'   # only here


def row_icon(x, y, shared):
    """The row's SF Symbol: folder for a shared project, desktopcomputer for one only on one Mac."""
    if shared:
        return (f'<path d="M{x} {y-8}h4.2l1.6 1.8h6.7a1 1 0 0 1 1 1v7.7a1 1 0 0 1 -1 1h-11.5a1 1 0 0 1 -1-1Z" '
                f'fill="none" stroke="#8E8E93" stroke-width="1.2" stroke-linejoin="round"></path>')
    return (f'<rect x="{x}" y="{y-8.5}" width="13.5" height="9.5" rx="1.5" fill="none" stroke="#8E8E93" stroke-width="1.2"></rect>'
            f'<path d="M{x+4.5} {y+3.5}h4.5M{x+6.75} {y+1}v2.5" stroke="#8E8E93" stroke-width="1.2" stroke-linecap="round"></path>')


HERE_TINT = "#F2F6FE"   # this Mac's columns: the accent at 5%


def text_width(s, size):
    """The width of a line, to place what follows it. Measured in Helvetica, the widest of the fonts the SVG may fall
    back to (rsvg, Windows' Arial); a rough estimate where the font is missing."""
    try:
        from PIL import ImageFont
        return ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", size * 4).getlength(s) / 4
    except Exception:
        return len(s) * size * 0.43


def group_by_button(x, y):
    """The Projects page's Group By menu button (rectangle.3.group), left of Check Now."""
    return (f'<circle cx="{x}" cy="{y}" r="11" fill="#EDEEF1"></circle>'
            f'<rect x="{x-6}" y="{y-5}" width="12" height="4" rx="1" fill="none" stroke="#3A3A40" stroke-width="1.1"></rect>'
            f'<rect x="{x-6}" y="{y+1}" width="5" height="4" rx="1" fill="none" stroke="#3A3A40" stroke-width="1.1"></rect>'
            f'<rect x="{x+1}" y="{y+1}" width="5" height="4" rx="1" fill="none" stroke="#3A3A40" stroke-width="1.1"></rect>')


def projects_grid(cx, cw, Y, cols, rows, legend_w, selected=None):
    """The Projects page's grid: profile names over their columns, each column's Mac, the two sections, the legend.
    rows: (name, shared, {column: kind}); cols: centres, default on Madoka, Ji-su, then work on Madoka, Ji-su."""
    pc = [GRAPH, GRAPH, TEAL, TEAL]
    g = []
    for (c0, c1), name, col in (((cols[0], cols[1]), "default", GRAPH), ((cols[2], cols[3]), "work", TEAL)):
        g.append(t((c0 + c1) / 2, Y + 68, name, 12, weight=700, anchor="middle")
                 + f'<rect x="{c0-28}" y="{Y+74}" width="{c1-c0+56}" height="2" rx="1" fill="{col}"></rect>')
    for i, c in enumerate(cols):
        g.append(t(c, Y + 92, "Madoka" if i % 2 == 0 else "Ji-su", 10.5, BLUE if i % 2 == 0 else "#6E6E73", anchor="middle"))
    def section(y, label): g.append(t(cx + 8, y, label, 11, "#5F5F66", 600)
                                    + f'<line x1="{cx+8}" y1="{y+7}" x2="{cx+cw}" y2="{y+7}" stroke="#E2E3E8"></line>')
    tops = {}
    def row(top, name, shared, cells):
        sel = name == selected
        if sel:
            g.append(f'<rect x="{cx+4}" y="{top+2}" width="{cw-4}" height="28" rx="6" fill="#DCE5FA"></rect>')
        g.append(row_icon(cx + 14, top + 20, shared) + t(cx + 36, top + 20, name, 12.5, weight=600 if sel else 400)
                 + "".join(f'<rect x="{c-26}" y="{top+4}" width="52" height="24" rx="6" fill="{HERE_TINT}"></rect>'
                           for c in cols[::2] if not sel))
        for i, kind in cells.items():
            g.append(mark(cols[i], top + 16, kind, pc[i]))
        tops[name] = top
    shared = [r for r in rows if r[1]]; only = [r for r in rows if not r[1]]
    y = Y + 122
    section(y, f"Shared · moves between places · {len(shared)}")
    for r in shared:
        y += 8 if r is shared[0] else 0
        row(y, *r); y += 32
    y += 26
    section(y, f"Only on one Mac · {len(only)}"); y += 8
    for r in only:
        row(y, *r); y += 32
    lx, ly = cx + 8, y + 26
    for kind, label, w in (("has", "Has it", 62), ("coming", "On its way", 84), ("old", "Old copy, locked", 116), ("only", "Only here", 70)):
        g.append(mark(lx + 6, ly - 4, kind, "#8E8E93") + t(lx + 18, ly, label, 10.5, "#5F5F66")); lx += w
    lines = ["Drag a project’s mark to another profile or Mac to move it there. A project only on this Mac is shared first.",
             "Projects that exist only on claude.ai aren’t listed: they’re on every Mac signed in to that account already."]
    if legend_w < 600:      # the window is narrower with the inspector open: the legend wraps
        lines = ["Drag a project’s mark to another profile or Mac to move it there.", "A project only on this Mac is shared first.",
                 "Projects that exist only on claude.ai aren’t listed: they’re on every", "Mac signed in to that account already."]
    yy = ly + 22
    for i, ln in enumerate(lines):
        g.append(t(cx + 8, yy, ln, 10.5, "#5F5F66"))
        if i == len(lines) - 1:
            ix = cx + 8 + text_width(ln, 10.5) + 10
            g.append(f'<circle cx="{ix}" cy="{yy-3.5}" r="5.5" fill="none" stroke="#8E8E93"></circle>' + t(ix, yy, "i", 8, "#8E8E93", 700, "middle"))
        yy += 15 if legend_w < 600 and i % 2 == 0 else 19
    return "".join(g), tops


def window_tour():
    sc = Scene(900, 500, 23.0)
    desktop(sc)
    X, Y, Wd, Hd = 30, 38, 840, 448
    cx, cw = X + 190 + 20, Wd - 190 - 40
    TB, TC = 6.9, 15.6          # Projects from TB, Macs from TC
    pages = (("handoffs", "Inbox", "1 waiting", 0, TB), ("projects", "Projects", "5 projects · 3 shared · 2 on one Mac", TB, TC),
             ("macs", "Macs", "2 Macs · 2 online", TC, None))
    for sel, title, sub, a, b in pages:
        w_, _ = tandem_window(X, Y, Wd, Hd, title, sel, side_w=190, badge_n=1 if sel == "handoffs" else 0, subtitle=sub)
        sc.add(w_, a, b)
    def box(y, h): return f'<rect x="{cx}" y="{y}" width="{cw}" height="{h}" rx="9" fill="#F6F6F8" stroke="#E2E3E8"></rect>'
    def btn(x, y, w, label, fill=BLUE, color="#FFFFFF"):
        return (f'<rect x="{x}" y="{y}" width="{w}" height="24" rx="7" fill="{fill}"></rect>'
                + t(x + w / 2, y + 16, label, 11.5, color, 600, "middle"))

    # ---- Inbox: Film Kit waits; Receive; then Open in Claude says where the project is
    sc.add(t(cx + 8, Y + 68, "Waiting for you", 11, "#5F5F66", 600) + box(Y + 76, 54), 0, TB)
    sc.add(f'<circle cx="{cx+16}" cy="{Y+96}" r="4" fill="#34C759"></circle>'
           + t(cx + 28, Y + 100, "Film Kit — from default on Ji-su", 12.5, weight=700)
           + t(cx + 28, Y + 118, "For work on this Mac · sent 2 minutes ago · brief HANDOFF_film_kit.md", 10.5, "#5F5F66")
           + btn(cx + cw - 84, Y + 90, 72, "Receive"), 0, 2.4)
    sc.add(t(cx + 14, Y + 108, "Nothing waiting.", 11.5, "#5F5F66"), 2.4, TB)
    sc.add(f'<rect x="{X+190-36}" y="{Y+34}" width="22" height="18" fill="#DCDDE2"></rect>'                 # the badge clears
           + f'<rect x="{X+190+14}" y="{Y+23}" width="200" height="12" fill="#FFFFFF"></rect>'
           + t(X + 190 + 16, Y + 31, "Nothing waiting", 10, "#6E6E73"), 2.4, TB)
    sc.add(t(cx + 8, Y + 156, "In progress", 11, "#5F5F66", 600) + box(Y + 164, 54)
           + t(cx + 28, Y + 188, "Receive Film Kit as work on this Mac", 12.5, weight=700), 2.4, TB)
    sc.add(f'<circle cx="{cx+16}" cy="{Y+184}" r="5" fill="none" stroke="#A1A1A8" stroke-width="1.5" stroke-dasharray="7 4"></circle>'
           + t(cx + 28, Y + 206, "Every file verified (md5) · claiming…", 10.5, "#5F5F66"), 2.4, 3.6)
    sc.add(step_icon(cx + 16, Y + 184, "done")
           + t(cx + 28, Y + 206, "Every file verified (md5) · Claimed · Memory merged · Brief HANDOFF_film_kit.md", 10.5, "#5F5F66")
           + btn(cx + cw - 112, Y + 178, 100, "Open in Claude"), 3.6, TB)
    n_open, _ = note(cx + cw - 360, 30, 360, "Film Kit is in Claude (work)",
                     "Open it from Projects in Claude’s sidebar, start a task,\nand paste: the brief is on the clipboard.")
    sc.add(n_open, 5.0, 6.8)

    # ---- Projects: every project against every place; drag a mark to move it
    cols = [cx + 262, cx + 318, cx + 390, cx + 446]          # default: Madoka, Ji-su · work: Madoka, Ji-su
    grid, tops = projects_grid(cx, cw, Y, cols, (
        ("Adobe Stock Plan", True, {}),                     # its marks change as it moves
        ("Film Kit", True, {1: "old", 2: "has"}),
        ("Quicken Reconciliation", True, {0: "old", 1: "has"}),
        ("Garden Notes", False, {0: "only"}),
        ("Q4 Launch Plan", False, {2: "only"})), cw)
    sc.add(grid + group_by_button(X + Wd - 50, Y + 20), TB, TC)
    R = [tops["Adobe Stock Plan"]]
    ay = R[0] + 16
    d0, d1, drop, sent = TB + 1.7, TB + 2.0, TB + 3.0, TB + 5.0       # press, start moving, drop, Send
    sc.add(mark(cols[0], ay, "has", GRAPH), TB, d1)
    sc.add(f'<g opacity="0.3">{mark(cols[0], ay, "has", GRAPH)}</g>', d1, sent)               # while dragged and while asked
    sc.add(mark(cols[1], ay, "old", GRAPH), TB, drop)
    sc.add(f'<rect x="{cols[1]-26}" y="{R[0]+4}" width="52" height="24" rx="6" fill="#C9DAFB"></rect>'
           + mark(cols[1], ay, "old", GRAPH), d1 + 0.5, drop)                                   # the place it can go lights up
    sc.add(mark(cols[1], ay, "old", GRAPH), drop, sent)
    sc.add(mark(cols[0], ay, "old", GRAPH) + mark(cols[1], ay, "coming", GRAPH), sent)
    sc.moving(mark(0, 0, "has", GRAPH), [(d1, cols[0], ay), (drop, cols[1], ay)])               # the mark under the pointer
    sc.body[-1] = f'<g {sc.vis(d1, drop)}>{sc.body[-1]}</g>'
    # the drop opens the send sheet, the same one Hand Off… opens
    sx, sy = cx + 150, Y + 120
    sheet = (f'<rect x="{sx}" y="{sy}" width="320" height="150" rx="12" fill="#FFFFFF" stroke="#C9CBD1"></rect>'
             + t(sx + 18, sy + 28, "Hand off Adobe Stock Plan", 14, weight=700)
             + t(sx + 18, sy + 54, "From", 11, "#5F5F66") + t(sx + 70, sy + 54, "default on this Mac", 11)
             + t(sx + 18, sy + 76, "To", 11, "#5F5F66")
             + f'<rect x="{sx+66}" y="{sy+63}" width="150" height="19" rx="5" fill="#F1F2F5" stroke="#D2D2D7"></rect>'
             + t(sx + 74, sy + 77, "default on Ji-su   ⌄", 11)
             + t(sx + 18, sy + 100, "Note", 11, "#5F5F66") + t(sx + 70, sy + 100, "vest schedule checked through Q3", 11)
             + f'<rect x="{sx+186}" y="{sy+116}" width="56" height="22" rx="6" fill="#E9EAEE"></rect>'
             + t(sx + 214, sy + 131, "Cancel", 11, anchor="middle")
             + f'<rect x="{sx+250}" y="{sy+116}" width="56" height="22" rx="6" fill="{BLUE}"></rect>'
             + t(sx + 278, sy + 131, "Send", 11, "#FFFFFF", 600, "middle"))
    sc.add(f'<rect x="{X+190}" y="{Y+44}" width="{Wd-190}" height="{Hd-45}" fill="#1D1D1F" opacity="0.12"></rect>' + sheet, drop + 0.2, sent)
    n_sent, _ = note(cx + cw - 360, 30, 360, "Adobe Stock Plan is on its way to default on Ji-su",
                     "Every file is uploaded. You’ll hear when it’s received.")
    sc.add(n_sent, sent + 1.4, TC - 0.4)

    # ---- Macs
    def card(x, y, w, mac, status, dot, ver, drive, sides):
        h = 104 + sum(86 if side[6] else 72 for side in sides)
        s = (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="9" fill="#F6F6F8" stroke="#E2E3E8"></rect>'
             + f'<circle cx="{x+w-18}" cy="{y+22}" r="4.5" fill="{dot}"></circle>'
             + t(x + 14, y + 27, mac, 16, weight=800) + t(x + 14, y + 44, status, 10.5, "#5F5F66")
             + t(x + 14, y + 70, "Tandem", 10.5, "#5F5F66") + t(x + 90, y + 70, ver, 10.5)
             + t(x + 14, y + 88, "iCloud Drive", 10.5, "#5F5F66") + t(x + 90, y + 88, drive, 10.5))
        yy = y + 112
        for letter, color, name, side, acct, holds, coming, defined in sides:
            s += (f'<line x1="{x+12}" y1="{yy-10}" x2="{x+w-12}" y2="{yy-10}" stroke="#E2E3E8"></line>'
                  + badge(x + 22, yy + 4, 8, letter, color) + t(x + 36, yy + 8, name, 11.5, weight=700)
                  + t(x + 36 + len(name) * 7 + 8, yy + 8, side, 9.5, "#8E8E93", family=MONO)
                  + t(x + w - 14, yy + 8, "Claude open", 9.5, "#1F7A3A", anchor="end")
                  + t(x + 36, yy + 24, acct, 10.5, "#5F5F66") + t(x + 36, yy + 39, holds, 10.5))
            if coming:
                s += t(x + 36, yy + 54, coming, 10.5, BLUE)
            s += t(x + 36, yy + (68 if coming else 54), defined, 9.5, "#8E8E93")
            yy += 86 if coming else 72
        return s
    mp = (t(cx, Y + 66, "Each Mac running Tandem publishes a card every few minutes.", 11, "#5F5F66")
          + f'<circle cx="{cx+356}" cy="{Y+62}" r="5.5" fill="none" stroke="#8E8E93"></circle>' + t(cx + 356, Y + 65, "i", 8, "#8E8E93", 700, "middle")
          + card(cx, Y + 80, (cw - 14) / 2, "Madoka", "This Mac", "#34C759", "1.3.0", "In sync",
                 [("A", GRAPH, "default", "Madoka", "you@personal.com · Max", "Holds no shared project", None, "3 projects defined in its Claude"),
                  ("W", TEAL, "work", "Madoka@work", "you@company.com · Team", "Holds Film Kit", None, "2 projects defined in its Claude")])
          + card(cx + (cw - 14) / 2 + 14, Y + 80, (cw - 14) / 2, "Ji-su", "Online · seen 1 min ago", "#34C759", "1.3.0", "In sync",
                 [("A", GRAPH, "default", "Ji-su", "you@personal.com · Max", "Holds Quicken Reconciliation",
                   "On its way here: Adobe Stock Plan", "3 projects defined in its Claude")]))
    sc.add(mp, TC)

    # the pointer: Receive, Open in Claude, Projects, drag Adobe Stock Plan to Ji-su, Send, Macs
    recv = (cx + cw - 48, Y + 102)
    openc = (cx + cw - 62, Y + 190)
    side_projects, side_macs = (X + 60, Y + 66), (X + 56, Y + 90)
    send = (sx + 278, sy + 128)
    sc.moving(POINTER, [(0.0, 600, 470), (1.7, *recv), (2.5, *recv), (4.2, *openc), (5.0, *openc),
                        (6.2, *side_projects), (6.9, *side_projects), (TB + 1.4, cols[0], ay), (d1, cols[0], ay),
                        (drop, cols[1], ay), (drop + 0.6, cols[1], ay), (TB + 4.3, *send), (sent, *send),
                        (TB + 6.6, cx + 420, Y + 330), (TC - 0.9, *side_macs), (TC, *side_macs),
                        (TC + 2.2, cx + 300, Y + 400), (23.0, cx + 300, Y + 400)])
    sc.write("window-demo.svg")

# ============================================================ 6. the Projects page, still: the grid and the inspector
def projects_still():
    """The Projects page as it stands after the tour's drag: Adobe Stock Plan selected, on its way to Ji-su,
    and the inspector open on it, with its own small grid (profiles down, Macs across) and its history."""
    sc = Scene(1000, 540, 1.0)
    desktop(sc)
    X, Y, Wd, Hd = 30, 38, 940, 488
    iw = 272                                   # the inspector's width
    ix = X + Wd - iw
    cx = X + 190 + 20
    cw = ix - 16 - cx
    w_, _ = tandem_window(X, Y, Wd, Hd, "Projects", "projects", side_w=190, subtitle="5 projects · 3 shared · 2 on one Mac")
    cols = [cx + 210, cx + 266, cx + 334, cx + 390]
    grid, tops = projects_grid(cx, cw, Y, cols, (
        ("Adobe Stock Plan", True, {0: "old", 1: "coming"}),
        ("Film Kit", True, {1: "old", 2: "has"}),
        ("Quicken Reconciliation", True, {0: "old", 1: "has"}),
        ("Garden Notes", False, {0: "only"}),
        ("Q4 Launch Plan", False, {2: "only"})), cw, selected="Adobe Stock Plan")
    ins = [f'<path d="M{ix} {Y+44}H{X+Wd-0.5}V{Y+Hd-10}a10 10 0 0 1 -10 10H{ix}Z" fill="#FAFAFB"></path>',
           f'<line x1="{ix}" y1="{Y+44}" x2="{ix}" y2="{Y+Hd}" stroke="#E2E3E8"></line>']
    x0, y = ix + 16, Y + 76
    ins.append(t(x0, y, "Adobe Stock Plan", 15, weight=700))
    ins.append(f'<rect x="{x0}" y="{y+9}" width="50" height="17" rx="8.5" fill="#EBEBEE"></rect>' + t(x0 + 25, y + 21, "Shared", 10, "#3A3A40", 700, "middle"))
    y += 52
    ins.append(t(x0, y, "WHERE IT IS", 10, "#6E6E73", 700))
    lw, cwid, ch = 44, 84, 44
    gx = x0 + lw + 4
    for j, m in enumerate(("Madoka", "Ji-su")):
        ins.append(t(gx + j * (cwid + 4) + cwid / 2, y + 20, m, 10, "#6E6E73", anchor="middle"))
    cells = {("default", 0): ("old", "old copy"), ("default", 1): ("coming", "on its way")}
    for i, (prof, col) in enumerate((("default", GRAPH), ("work", TEAL))):
        ry = y + 28 + i * (ch + 4)
        ins.append(t(x0 + lw, ry + ch / 2 + 4, prof, 10, "#6E6E73", anchor="end"))
        for j in range(2):
            bx = gx + j * (cwid + 4)
            ins.append(f'<rect x="{bx}" y="{ry}" width="{cwid}" height="{ch}" rx="6" fill="{HERE_TINT if j == 0 else "#FFFFFF"}" stroke="#E2E3E8"></rect>')
            if (prof, j) in cells:
                kind, cap = cells[(prof, j)]
                ins.append(mark(bx + cwid / 2, ry + 16, kind, col) + t(bx + cwid / 2, ry + 35, cap, 9, "#6E6E73", anchor="middle"))
    y += 28 + 2 * (ch + 4) + 20
    for ln in ("On its way to Ji-su · default, sent just now.",):
        ins.append(t(x0, y, ln, 11.5, "#5F5F66")); y += 22
    ins.append(f'<text x="{x0}" y="{y}" font-size="11.5" font-style="italic" fill="#1D1D1F">“vest schedule checked through Q3”</text>')
    y += 32
    ins.append(t(x0, y, "HISTORY", 10, "#6E6E73", 700)); y += 20
    for when, what in (("just now", "Sent by Madoka · default"), ("3 days ago", "Received by Madoka · default"),
                       ("2 weeks ago", "Sent by Ji-su · default")):
        ins.append(t(x0, y, when, 10, "#6E6E73") + t(x0 + 84, y, what, 10)); y += 17
    sc.add(w_ + group_by_button(X + Wd - 50, Y + 20) + grid + "".join(ins))
    sc.write("projects-demo.svg")


profiles()
handoff_accounts()
menubar()
handoff_app()
window_tour()
projects_still()
