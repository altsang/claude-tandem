#!/usr/bin/env python3
"""Render the README's animated mockups as self-contained SVGs.

Pure CSS keyframes — no script, no SMIL, no GIF — so GitHub plays them in an <img>.
Each element is shown or hidden on one shared loop, commands "type" through a
widening clip, and the pointer moves by animated translate. Claude's windows are
drawn schematically (Claude's Dock icon simplified, placeholder accounts). Terminal lines are the
tool's real output, shortened where marked.

    python3 assets/gen-mockups.py      # writes the three SVGs beside this file
"""
import html, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
UI = "-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif"
MONO = "ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace"
TEAL, BLUE, GRAPH, AMBER = "#18A8B4", "#2350C8", "#3A3A40", "#B25E00"
CLAUDE_TILE = "#DB6B46"   # the Claude app icon's terracotta, behind its starburst (glyph="spark")


class Scene:
    def __init__(self, w, h, total):
        self.w, self.h, self.total = w, h, total
        self.kf, self.body, self.n = [], [], 0

    def _id(self, p):
        self.n += 1
        return f"{p}{self.n}"

    def pct(self, t):
        return 100.0 * t / self.total

    # visibility: hidden, then shown from t_on (until t_off, else to the end of the loop)
    def vis(self, t_on, t_off=None):
        name, e = self._id("v"), 0.2
        p1 = self.pct(t_on)
        if t_off is None:
            k = f"@keyframes {name}{{0%,{p1:.2f}%{{opacity:0}}{p1+e:.2f}%,100%{{opacity:1}}}}"
        else:
            p2 = self.pct(t_off)
            k = (f"@keyframes {name}{{0%,{p1:.2f}%{{opacity:0}}{p1+e:.2f}%,{p2:.2f}%{{opacity:1}}"
                 f"{p2+e:.2f}%,100%{{opacity:0}}}}")
        self.kf.append(k)
        return f'style="opacity:0;animation:{name} {self.total}s linear infinite"'

    def add(self, svg, t_on=None, t_off=None):
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
        stops = "".join(f"{self.pct(t):.2f}%{{transform:translate({x}px,{y}px)}}" for t, x, y in points)
        first, last = points[0], points[-1]
        self.kf.append(f"@keyframes {k}{{0%{{transform:translate({first[1]}px,{first[2]}px)}}{stops}"
                       f"100%{{transform:translate({last[1]}px,{last[2]}px)}}}}")
        self.body.append(f'<g style="animation:{k} {self.total}s ease-in-out infinite">{svg}</g>')

    def write(self, name):
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" '
               f'width="{self.w}" height="{self.h}" font-family="{UI}">\n<style>\n'
               + "\n".join(self.kf) + "\n</style>\n" + "\n".join(self.body) + "\n</svg>\n")
        path = os.path.join(HERE, name)
        open(path, "w").write(svg)
        print(f"wrote {name}  {len(svg)/1000:.1f} KB  {self.w}x{self.h}")


def esc(s): return html.escape(s)

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
    # a window behind, for depth
    w_, _ = window(sc, 40, 70, 420, 300, "you@personal.com", "Max")
    sc.add(w_)
    # the dropdown
    dx, dy, dw = 560, 28, 320
    rows = []
    rows.append(t(dx + 14, dy + 22, "Claude profiles on Madoka", 10.5, "#5F5F66", 600))
    def prow(y, letter, color, name, sub, sub2, sub2c):
        return (badge(dx + 26, y + 16, 11, letter, color)
                + t(dx + 46, y + 13, name, 12.5, weight=700)
                + t(dx + 46, y + 28, sub, 10.5, "#5F5F66")
                + t(dx + 46 + len(sub) * 5.6, y + 28, sub2, 10.5, sub2c))
    rows.append(prow(dy + 32, "A", GRAPH, "default", "you@personal.com · Max  ·  ", "Open", "#1F7A3A"))
    base = (f'<rect x="{dx}" y="{dy}" width="{dw}" height="258" rx="10" fill="#FFFFFF" stroke="#D2D2D7"></rect>'
            + "".join(rows)
            + f'<line x1="{dx+10}" y1="{dy+118}" x2="{dx+dw-10}" y2="{dy+118}" stroke="#E5E5EA"></line>'
            + "".join(t(dx + 14, dy + 140 + i * 22, s, 12) for i, s in enumerate(
                ["New Profile…", "Sync Claude Code Sessions", "Run Doctor"]))
            + f'<line x1="{dx+10}" y1="{dy+202}" x2="{dx+dw-10}" y2="{dy+202}" stroke="#E5E5EA"></line>'
            + t(dx + 14, dy + 224, "Open at Login", 12) + t(dx + dw - 16, dy + 224, "✓", 12, anchor="end")
            + t(dx + 14, dy + 246, "Quit Claude Tandem", 12))
    sc.add(base, 1.7, 6.2)
    work_row = (prow(dy + 72, "W", TEAL, "work", "you@company.com · Team  ·  ", "4 earlier sessions", BLUE)
                + t(dx + dw - 16, dy + 94, "›", 14, "#8E8E93", anchor="end"))
    sc.add(work_row, 1.7, 3.1)
    sc.add(f'<rect x="{dx+6}" y="{dy+70}" width="{dw-12}" height="44" rx="6" fill="{BLUE}"></rect>'
           + badge(dx + 26, dy + 88, 11, "W", TEAL)
           + t(dx + 46, dy + 85, "work", 12.5, "#FFFFFF", 700)
           + t(dx + 46, dy + 100, "you@company.com · Team  ·  4 earlier sessions", 10.5, "#DCE6FF")
           + t(dx + dw - 16, dy + 94, "›", 14, "#FFFFFF", anchor="end"), 3.1, 6.2)
    # the profile's submenu, opening to the left
    sx, sy, sw = 254, 98, 300
    items = ["Show Claude", "Open Claude Code in Terminal", "Quit Claude", None,
             "Hand Off a Project  ›", "Receive a Project  ›", None, "Bring In Earlier Sessions (4)…", None,
             "Rename…", "Change Badge…", "Show Badge in the Dock  ✓"]
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
    sc.moving(POINTER, [(0.0, 470, 300), (1.4, icon_x, 10), (2.4, icon_x - 40, 60),
                        (3.0, 760, 104), (4.2, 500, 112), (4.9, 470, bring_y + 8),
                        (6.0, 470, bring_y + 8), (7.6, 450, ay + 176), (9.4, 450, ay + 176),
                        (11.0, 700, 380)])
    sc.write("menubar-demo.svg")


profiles()
handoff_accounts()
menubar()
