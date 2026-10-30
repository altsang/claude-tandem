#!/usr/bin/env python3
"""Render the two-Mac handoff as an animated SVG terminal recording.

Every printed line below is verbatim from bin/tandem + bin/coworkctl-v7.sh —
only the project name, timestamps and byte counts are filled in.
"""
import html

TOTAL   = 32.0      # loop length: ~21.5s of action, then a 10s hold to read it
FS      = 12.5      # font size
CW      = FS * 0.6022   # Menlo advance
LH      = 17.0
PAD_X   = 18.0
CHROME  = 30.0
W       = 900.0

C = dict(
    bg="#0d1117", chrome="#161b22", edge="#30363d",
    txt="#adbac7", dim="#768390", head="#e6edf3",
    ok="#57ab5a", bar="#6cb6ff", ev="#a5d6ff",
    warn="#daaa3f", cmd="#e6edf3", prompt="#57ab5a",
    doc="#c9a4ff",
)

# ---------------------------------------------------------------- transcripts
# (row, t_on, t_off|None, text, color)  — same row + t_off = a line that
# rewrites itself in place, the way the real progress bars do.

MADOKA_CMD = './bin/tandem send "Quicken Reconciliation" --to Ji-su --note "Amex feed short 2 txns" --wait'
JISU_CMD   = './bin/tandem receive "Quicken Reconciliation"'

madoka = [
    (1,  2.6, None, "sending 'Quicken Reconciliation': Madoka -> Ji-su", "head"),
    (2,  2.9, None, "  document: HANDOFF_quicken_aug.md", "dim"),
    (3,  3.2, None, "materializing (so real bytes exist to upload):", "head"),
    (4,  3.5, None, "  2 dataless file(s) — forcing download", "dim"),
    (5,  4.2, None, "  all materialized in 1s", "dim"),
    (6,  4.5, None, '  exported "Quicken Reconciliation" -> _handoff/projects/Quicken Reconciliation.20260822T171204Z.json', "dim"),
    (7,  4.7, None, "  instructions: yes", "dim"),
    (8,  4.9, None, "  manifest: 6 files, 21.6 KB", "dim"),
    (9,  5.2, None, "  memory: 20 file(s), 42.1 KB -> .handoff/memory/20260822T171204Z-Madoka/", "dim"),
    (10, 5.5, None, "event: 20260822T171205Z-Madoka-handoff.json", "ev"),
    (11, 5.9, None, "verifying the upload (this is what 'staged' never proved):", "head"),
    (12, 6.3, 7.2,  "  [██████░░░░░░░░░░░░░░]  33%  2/6 files uploaded   5s", "bar"),
    (12, 7.2, 8.4,  "  [█████████████░░░░░░░]  66%  4/6 files uploaded   15s", "bar"),
    (12, 8.4, None, "  [████████████████████] 100%  6/6 files uploaded   25s", "bar"),
    (13, 8.8, None, "  ✓ all 6 files uploaded to the drive in 25s", "ok"),
    (15, 9.3, None, "  UPLOADED. 'Ji-su' can pull it now:", "head"),
    (16, 9.6, None, '      tandem receive "Quicken Reconciliation"', "cmd"),
    (17, 9.9, None, "  Do not edit 'Quicken Reconciliation' on Madoka until it comes back.", "warn"),
    (19, 10.4, None, "waiting for Ji-su to claim it (Ctrl-C to stop)...", "head"),
    (20, 10.8, 12.4, "  20s", "dim"),
    (20, 12.4, 14.6, "  70s", "dim"),
    (20, 14.6, 18.9, "  120s", "dim"),
    (20, 18.9, None, "  130s", "dim"),
    (21, 19.2, None, "  ✓ DELIVERED — Ji-su claimed 'Quicken Reconciliation' at 20260822T171417Z", "ok"),
]

jisu = [
    (1,  13.2, None, "receiving 'Quicken Reconciliation' on Ji-su", "head"),
    (2,  13.5, None, "waiting for a handoff addressed to Ji-su...", "head"),
    (3,  13.8, 14.4, "  6s", "dim"),
    (3,  14.4, 15.0, "  12s", "dim"),
    (3,  15.0, None, "  18s", "dim"),
    (4,  15.3, None, "  handed off by Madoka at 20260822T171205Z", "dim"),
    (5,  15.6, None, "waiting for the files:", "head"),
    (6,  16.0, 16.9, "  [██████████░░░░░░░░░░]  50%  3/6 files materialized, 9/22 KB   12s", "bar"),
    (6,  16.9, None, "  [████████████████████] 100%  6/6 files materialized, 22/22 KB   31s", "bar"),
    (7,  17.3, None, "  ✓ all 6 files delivered and verified by md5 in 31s", "ok"),
    (8,  17.6, None, "  project already defined on this Mac", "dim"),
    (9,  17.9, None, "picking up 'Quicken Reconciliation' on Ji-su", "head"),
    (10, 18.1, None, "materializing:", "head"),
    (11, 18.3, None, "  all files materialized", "dim"),
    (12, 18.6, None, "event: 20260822T171417Z-Ji-su-claim.json", "ev"),
    (13, 18.9, None, "claimed by Ji-su (the other Mac sees this once iCloud carries the event over)", "txt"),
    (15, 19.4, None, "================ HANDOFF_quicken_aug.md ================", "doc"),
    (17, 19.7, None, "## Where I left off", "txt"),
    (18, 20.0, None, "Aug statements reconciled through 8/19. Amex feed is short two", "txt"),
    (19, 20.3, None, "transactions — see the note in accounts.md before you re-import.", "txt"),
    (20, 20.6, None, "  ⋮", "dim"),
    (21, 21.0, None, "  installed 20 memory file(s) from Madoka (20260822T171204Z) — 42.1 KB", "ok"),
    (23, 21.5, None, "  ✓ HANDOFF_quicken_aug.md copied to the clipboard — open 'Quicken Reconciliation' in Cowork and paste it.", "ok"),
]

MADOKA_ROWS = 22
JISU_ROWS   = 24

# ---------------------------------------------------------------- svg assembly
keyframes, body = [], []
_n = [0]

def anim(t_on, t_off=None):
    """One keyframe track: invisible, then visible from t_on (until t_off)."""
    _n[0] += 1
    name = f"a{_n[0]}"
    p1 = 100.0 * t_on / TOTAL
    e = 0.12
    if t_off is None:
        kf = f"@keyframes {name}{{0%,{p1:.2f}%{{opacity:0}}{p1+e:.2f}%,100%{{opacity:1}}}}"
    else:
        p2 = 100.0 * t_off / TOTAL
        kf = (f"@keyframes {name}{{0%,{p1:.2f}%{{opacity:0}}{p1+e:.2f}%,{p2:.2f}%{{opacity:1}}"
              f"{p2+e:.2f}%,100%{{opacity:0}}}}")
    keyframes.append(kf)
    return name

def window(x, y, w, rows, title, cmd, cmd_t, lines):
    h = CHROME + 10 + rows * LH + 8
    body.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="9" fill="{C["bg"]}" stroke="{C["edge"]}"/>')
    body.append(f'<path d="M{x} {y+9}a9 9 0 0 1 9-9h{w-18}a9 9 0 0 1 9 9v{CHROME-9}H{x}Z" fill="{C["chrome"]}"/>')
    for i, col in enumerate(("#ec6a5e", "#f4bf4f", "#61c454")):
        body.append(f'<circle cx="{x+18+i*15}" cy="{y+15}" r="5" fill="{col}"/>')
    body.append(f'<text x="{x+w/2}" y="{y+19.5}" text-anchor="middle" class="t" '
                f'fill="{C["dim"]}" font-size="11.5">{html.escape(title)}</text>')

    def rowy(r):
        return y + CHROME + 10 + r * LH + FS

    # prompt + typed command
    a = anim(cmd_t)
    body.append(f'<text x="{x+PAD_X}" y="{rowy(0)}" class="t" fill="{C["prompt"]}" '
                f'style="animation-name:{a}">$</text>')
    n = len(cmd)
    cid = f"clip{_n[0]}"
    cx = x + PAD_X + 2 * CW
    dur = min(2.0, 0.028 * n)
    _n[0] += 1
    kname = f"type{_n[0]}"
    p1 = 100.0 * cmd_t / TOTAL
    p2 = 100.0 * (cmd_t + dur) / TOTAL
    keyframes.append(f"@keyframes {kname}{{0%,{p1:.2f}%{{width:0}}{p2:.2f}%,100%{{width:{n*CW:.1f}px}}}}")
    body.append(f'<clipPath id="{cid}"><rect x="{cx}" y="{y+CHROME}" height="{LH+6}" width="0" '
                f'style="animation:{kname} {TOTAL}s steps({n},end) infinite"/></clipPath>')
    body.append(f'<text x="{cx}" y="{rowy(0)}" class="t" fill="{C["cmd"]}" clip-path="url(#{cid})" '
                f'style="animation-name:{a}">{html.escape(cmd)}</text>')
    # caret — steps across with the typing, then gone
    _n[0] += 1
    cmove, cop = f"cm{_n[0]}", f"co{_n[0]}"
    keyframes.append(f"@keyframes {cmove}{{0%,{p1:.2f}%{{x:{cx:.1f}px}}{p2:.2f}%,100%{{x:{cx+n*CW:.1f}px}}}}")
    keyframes.append(f"@keyframes {cop}{{0%,{p1:.2f}%{{opacity:0}}{p1+0.1:.2f}%,{p2:.2f}%{{opacity:.85}}"
                     f"{p2+0.1:.2f}%,100%{{opacity:0}}}}")
    body.append(f'<rect x="{cx:.1f}" y="{rowy(0)-FS+2.5:.1f}" width="{CW:.1f}" height="{FS}" fill="{C["cmd"]}" '
                f'opacity="0" style="animation:{cmove} {TOTAL}s steps({n},end) infinite,'
                f'{cop} {TOTAL}s linear infinite"/>')

    for row, t_on, t_off, text, col in lines:
        a = anim(t_on, t_off)
        body.append(f'<text x="{x+PAD_X}" y="{rowy(row)}" class="t" fill="{C[col]}" '
                    f'style="animation-name:{a}">{html.escape(text)}</text>')
    return h

Y0 = 8
h1 = window(0.5, Y0, W - 1, MADOKA_ROWS, "Madoka — desktop", MADOKA_CMD, 0.4, madoka)
GAP = 34
y2 = Y0 + h1 + GAP
a = anim(10.9)
body.append(f'<text x="{W/2}" y="{y2-13}" text-anchor="middle" class="t" fill="{C["dim"]}" '
            f'font-size="11.5" style="animation-name:{a}">⇣   shared drive   ⇣</text>')
h2 = window(0.5, y2, W - 1, JISU_ROWS, "Ji-su — laptop", JISU_CMD, 11.2, jisu)
H = y2 + h2 + 8

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W:.0f} {H:.0f}" width="{W:.0f}" height="{H:.0f}" font-size="{FS}">
<style>
.t{{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono",monospace;
white-space:pre;dominant-baseline:auto}}
text[style*="animation-name"]{{opacity:0;animation-duration:{TOTAL}s;animation-iteration-count:infinite;animation-timing-function:linear}}
{chr(10).join(keyframes)}
</style>
<rect width="100%" height="100%" fill="none"/>
{chr(10).join(body)}
</svg>
'''
import os
import os
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tandem-handoff-demo.svg")
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, "w").write(svg)
print(f"wrote {out}  {len(svg)/1000:.1f} KB  {W:.0f}x{H:.0f}")
