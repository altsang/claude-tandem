#!/usr/bin/env python3
"""tandem-ledger — what is where, across every Mac and profile.

    tandem-ledger.py where    <root> <mac> <confdir> [profiles.json] [drive-state]
    tandem-ledger.py presence <root> <mac> <confdir> <profiles.json> <version> [drive-state]

`presence` publishes this Mac's card to _handoff/presence/<Mac>/<ts>.json (and deletes
this Mac's older cards: one writer per folder, so nothing is ever edited in place).
`where` merges every card with every shared project's ownership events, intents and
requests, and prints one JSON document. Called by bin/tandem; the app reads `tandem where
--json`. Reads only — except presence, which writes its own card.

Nothing here goes in .handoff/events/: every shipped engine reads the newest event there as
the owner, so intents, requests and presence live in sibling folders older versions ignore.
"""
import datetime
import glob
import json
import os
import sys
import time

UTC = datetime.timezone.utc
SCHEMA = 1   # bump on an incompatible change to the JSON; additions keep it


def now_ts():
    return datetime.datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")


def ts_epoch(at):
    try:
        return datetime.datetime.strptime(at, "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC).timestamp()
    except Exception:
        return None


def iso(epoch):
    return datetime.datetime.fromtimestamp(epoch, UTC).strftime("%Y-%m-%dT%H:%M:%SZ") if epoch else None


def iso_all(x):
    """Every timestamp in JSON output as ISO 8601 UTC. Ownership events and cards name files with
    the compact form (20261101T172643Z), and that stays on disk; the API speaks one format."""
    if isinstance(x, dict):
        return {k: (iso(ts_epoch(v)) if isinstance(v, str) and k in ("at", "item_at") and ts_epoch(v) else iso_all(v))
                for k, v in x.items()}
    if isinstance(x, list):
        return [iso_all(v) for v in x]
    return x


def touch_dir(d):
    """iCloud does not push to an idle Mac: listing a folder is what makes it deliver."""
    try:
        return os.listdir(d)
    except OSError:
        return []


def read_json(f):
    """A synced file can be DATALESS — right size, no content, and a read returns empty with
    no error. A whole-file binary read pulls it; then parse. None if it still won't."""
    try:
        st = os.stat(f)
        if st.st_size > 0 and st.st_blocks == 0:
            with open(f, "rb") as fh:
                while fh.read(1 << 20):
                    pass
        with open(f) as fh:
            return json.load(fh)
    except Exception:
        return None


def event_name(fn):
    """{ts}-{side}-{verb}.json — a side can contain '-' (Ji-su), so split from both ends."""
    stem = fn[:-5]
    first, last = stem.find("-"), stem.rfind("-")
    if first < 0 or last <= first:
        return None
    return {"at": stem[:first], "side": stem[first + 1:last], "verb": stem[last + 1:]}


# ---- profiles and their local projects (this Mac) ----------------------------------

def spaces_file(userdata):
    base = os.path.join(userdata, "local-agent-mode-sessions")
    try:
        acct = json.load(open(os.path.join(userdata, "config.json"))).get("lastKnownAccountUuid")
    except Exception:
        acct = None
    pat = os.path.join(base, acct, "*", "spaces.json") if acct else os.path.join(base, "*", "*", "spaces.json")
    fs = [f for f in glob.glob(pat) if "skills-plugin" not in f]
    return max(fs, key=os.path.getmtime) if fs else None


def local_projects(profile_id):
    ud = os.path.expanduser("~/Library/Application Support/Claude" + ("" if profile_id == "default" else "-" + profile_id))
    f = spaces_file(ud)
    if not f:
        return []
    try:
        d = json.load(open(f))
    except Exception:
        return []
    out = []
    for s in d.get("spaces", []):
        paths = [x.get("path") for x in (s.get("folders") or []) if x.get("path")]
        out.append({"name": s.get("name", ""), "folders": paths})
    return out


def held_here(confdir, pid):
    """Projects this profile locked itself out of with --hold (the stash `release` restores)."""
    if not confdir:
        return []
    d = os.path.join(confdir, "held" if pid == "default" else "held-" + pid)
    return sorted(f[:-5] for f in touch_dir(d) if f.endswith(".json"))


def my_sides(mac, profiles, confdir=None):
    sides = []
    for p in profiles:
        pid = p.get("id", "default")
        sides.append({
            "side": mac if p.get("default") else f"{mac}@{pid}",
            "profile": pid,
            "name": p.get("name", pid),
            "email": p.get("email"),
            "plan": p.get("plan"),
            "open": bool(p.get("open")),
            "color": p.get("color"),
            "projects": local_projects(pid),
            "held": held_here(confdir, pid),
        })
    return sides


def drive(state_line):
    if not state_line:
        return None
    parts = (state_line.split("\t") + ["", "", ""])[:3]
    age = int(parts[2]) if parts[2].isdigit() else None
    return {"state": parts[0], "last_sync": parts[1], "minutes": age,
            "stalled": parts[0] != "idle" and age is not None and age >= 10}


# ---- presence -------------------------------------------------------------------------

def cmd_presence(root, mac, confdir, profiles_file, version, drive_line=""):
    profiles = json.load(open(profiles_file))
    d = os.path.join(root, "_handoff", "presence", mac)
    os.makedirs(d, exist_ok=True)
    ts = now_ts()
    card = {"mac": mac, "at": ts, "version": version, "drive": drive(drive_line),
            "sides": [{k: v for k, v in s.items()} for s in my_sides(mac, profiles)]}
    # project folders are this Mac's paths — useless elsewhere, and private enough to leave out
    for s in card["sides"]:
        s["projects"] = [p["name"] for p in s["projects"]]
    path = os.path.join(d, f"{ts}.json")
    tmp = os.path.join(d, f".{ts}.tmp")
    with open(tmp, "w") as fh:
        json.dump(card, fh, indent=2)
    os.rename(tmp, path)
    for f in glob.glob(os.path.join(d, "*.json")):
        if f != path:
            try:
                os.remove(f)   # only ever this Mac's own cards
            except OSError:
                pass
    print(path)


def read_presence(root, confdir=None):
    """Each Mac's newest card that parses. A Mac writes its new card and then deletes the old
    one, so for a minute or two another Mac can list only a card iCloud hasn't delivered yet:
    nothing readable, and the Mac would show as "No card". The last card read from each Mac is
    kept in <confdir>/cards/ and stands in until the new one arrives; its age comes from its
    own timestamp, so "seen N min ago" stays true."""
    out = {}
    base = os.path.join(root, "_handoff", "presence")
    cache = os.path.join(confdir, "cards") if confdir else None
    macs = set(touch_dir(base))
    if cache:
        macs |= {f[:-5] for f in touch_dir(cache) if f.endswith(".json")}
    for m in macs:
        d = os.path.join(base, m)
        fs = sorted(f for f in touch_dir(d) if f.endswith(".json"))
        card = None
        for f in reversed(fs):   # newest that parses
            card = read_json(os.path.join(d, f))
            if card:
                break
        if cache:
            kept = os.path.join(cache, m + ".json")
            if card:
                try:
                    os.makedirs(cache, exist_ok=True)
                    tmp = kept + ".tmp"
                    with open(tmp, "w") as fh:
                        json.dump(card, fh)
                    os.rename(tmp, kept)
                except OSError:
                    pass
            elif fs:   # the Mac still has a card on the drive, just not one readable here yet
                card = read_json(kept)
        if card:
            card["age_minutes"] = int((time.time() - (ts_epoch(card.get("at", "")) or 0)) / 60)
            out[m] = card
    return out


# ---- where ----------------------------------------------------------------------------

def newest_doc(folder):
    best = None
    for f in touch_dir(folder):
        if f.startswith("HANDOFF") and f.endswith(".md"):
            try:
                mt = os.path.getmtime(os.path.join(folder, f))
            except OSError:
                continue
            if not best or mt > best[1]:
                best = (f, mt)
    return best


def pending_records(folder, since, kind):
    """intents/ or requests/ files newer than the newest ownership event: the next event consumes them."""
    out = []
    d = os.path.join(folder, ".handoff", kind)
    for f in sorted(touch_dir(d)):
        if not f.endswith(".json"):
            continue
        p = os.path.join(d, f)
        rec = read_json(p) or {}
        at = ts_epoch(rec.get("at", "")) if rec.get("at") else None
        if at is None:
            try:
                at = os.path.getmtime(p)
            except OSError:
                continue
        if since is None or at > since:
            rec.update({"file": f, "at": iso(at)})
            out.append(rec)
    return out


def project(root, name, settling):
    folder = os.path.join(root, "Projects", name)
    touch_dir(folder)
    touch_dir(os.path.join(folder, ".handoff"))
    ev_dir = os.path.join(folder, ".handoff", "events")
    evs = sorted(f for f in touch_dir(ev_dir) if f.endswith(".json"))
    p = {"name": name, "holder": None, "state": "unrecorded", "last": None, "events": len(evs), "history": []}
    since = None
    if evs:
        e = read_json(os.path.join(ev_dir, evs[-1]))
        if e is None:
            meta = event_name(evs[-1]) or {}
            p["state"] = "unreadable"   # on the drive but dataless — a delivery problem, not "none"
            p["last"] = {"verb": meta.get("verb"), "machine": meta.get("side"), "at": meta.get("at"), "file": evs[-1]}
            since = ts_epoch(meta.get("at", ""))
        else:
            verb = e.get("verb")
            p["holder"] = e.get("to") if verb == "handoff" else e.get("machine")
            p["state"] = "sent" if verb == "handoff" else "held"
            note, doc = e.get("note") or "", e.get("handoff_doc") or ""
            # Engines up to v8 read the state with `IFS=$'\t' read`, which collapses an empty
            # note, so a claim after a note-less handoff records the brief's name as its note.
            # (the doc field then holds the event count the same read shifted along)
            if (not doc or doc.isdigit()) and note.startswith("HANDOFF") and note.endswith(".md"):
                note, doc = "", note
            p["last"] = {"verb": verb, "machine": e.get("machine"), "to": e.get("to"), "at": e.get("at"),
                         "note": note, "doc": doc, "file": evs[-1]}
            since = ts_epoch(e.get("at", ""))
        for f in evs[-8:]:
            meta = event_name(f)
            if meta:
                p["history"].append(meta)
    doc = newest_doc(folder)
    if doc:
        p["doc"] = {"name": doc[0], "modified": iso(doc[1]), "stale": bool(since and doc[1] < since)}
    p["intents"] = pending_records(folder, since, "intents")
    p["requests"] = pending_records(folder, since, "requests")
    p["settling"] = [s for s in settling if s.get("project") == name]
    return p


def cmd_where(root, mac, confdir, profiles_file="", drive_line=""):
    profiles = []
    if profiles_file and os.path.exists(profiles_file):
        try:
            profiles = json.load(open(profiles_file))
        except Exception:
            profiles = []
    settling = []
    for f in sorted(glob.glob(os.path.join(confdir, "settle", "*.json"))):
        rec = read_json(f)
        if rec:
            rec["file"] = os.path.basename(f)
            settling.append(rec)
    touch_dir(os.path.join(root, "_handoff"))
    names = sorted((n for n in touch_dir(os.path.join(root, "Projects"))
                    if not n.startswith(".") and os.path.isdir(os.path.join(root, "Projects", n))),
                   key=str.lower)
    projects = [project(root, n, settling) for n in names]
    shared = set(names)

    presence = read_presence(root, confdir)
    me = {"mac": mac, "this": True, "at": now_ts(), "age_minutes": 0, "drive": drive(drive_line),
          "sides": my_sides(mac, profiles, confdir)}
    for s in me["sides"]:
        s["projects"] = [x["name"] for x in s["projects"]]
    if mac in presence:
        me["version"] = presence[mac].get("version")
    machines = [me] + [dict(c, this=False) for m, c in sorted(presence.items()) if m != mac]

    # Macs that appear in ownership events but publish no card: an older Tandem, or not running
    known = {m["mac"] for m in machines}
    for p in projects:
        for h in p["history"] + ([{"side": p["holder"]}] if p["holder"] else []):
            m = (h.get("side") or "").split("@")[0]
            if m and m not in known:
                known.add(m)
                machines.append({"mac": m, "this": False, "silent": True, "sides": []})
    for m in machines:
        if m.get("silent"):
            seen = sorted({h.get("side") for p in projects for h in p["history"] + [{"side": p["holder"]}]
                           if (h.get("side") or "").split("@")[0] == m["mac"]})
            m["sides"] = [{"side": x, "profile": x.split("@")[1] if "@" in x else "default", "projects": []} for x in seen]

    # projects a handoff can't reach yet: defined on one side, not in the shared tree
    only_here = []
    for m in machines:
        for s in m.get("sides", []):
            for lp in s.get("projects", []):
                n = lp
                if n and n not in shared:
                    only_here.append({"project": n, "side": s["side"], "mac": m["mac"], "name": s.get("name")})

    d = {"schema": SCHEMA, "me": mac, "root": root, "at": now_ts(), "projects": projects,
         "machines": machines, "unshared": only_here}
    d["inbox"] = inbox(d, confdir)
    if os.environ.get("TANDEM_LEDGER_INBOX"):
        if os.environ.get("TANDEM_LEDGER_TEXT"):
            show_inbox(d)
        else:
            json.dump(iso_all({"schema": SCHEMA, "me": mac, "root": root, "inbox": d["inbox"]}), sys.stdout, indent=2)
            print()
        return
    if os.environ.get("TANDEM_LEDGER_TEXT"):
        show(d)
    else:
        json.dump(iso_all(d), sys.stdout, indent=2)
        print()


# ---- the inbox: what is waiting for a profile on this Mac --------------------------
#
# One implementation for every client: `tandem inbox`, `tandem watch` and the app all read
# this list, so they agree on what is waiting and on each item's key.

def load_list(path):
    try:
        v = json.load(open(path))
        return v if isinstance(v, list) else []
    except Exception:
        return []


def resolve(d, to, frm):
    """An intent's free-text "to" (written by a Cowork session) matched to a known side:
    exactly, case-insensitively; or Mac@profile-name. None when it names nothing known."""
    if not to or not to.strip():
        return None
    t = to.strip()
    sides = []
    for m in d["machines"]:
        for s in m.get("sides", []):
            if s["side"] != frm:
                sides.append((m["mac"], s))
    for _, s in sides:
        if s["side"].lower() == t.lower():
            return s["side"]
    if "@" in t:
        mac, name = t.split("@", 1)
        for m, s in sides:
            if m.lower() == mac.lower() and (s.get("name") or "").lower() == name.lower():
                return s["side"]
    return None


def inbox(d, confdir):
    me = next((m for m in d["machines"] if m.get("this")), {"sides": []})
    mine = {s["side"]: s for s in me.get("sides", [])}
    dismissed = set(load_list(os.path.join(confdir, "dismissed.json")))
    out = []

    def item(kind, p, side, other=None, note=None, at=None, key="", **extra):
        s = mine.get(side, {})
        rec = {"kind": kind, "key": key, "project": p["name"], "side": side,
               "profile": s.get("profile"), "profile_name": s.get("name"), "profile_open": bool(s.get("open")),
               "other": other, "note": note or "", "at": at}
        rec.update(extra)
        out.append(rec)

    for p in d["projects"]:
        last = p.get("last") or {}
        if p["state"] == "sent" and p.get("holder") in mine:
            item("arrival", p, p["holder"], last.get("machine"), last.get("note"), last.get("at"),
                 "in:%s/%s" % (p["name"], last.get("file", "")), doc=last.get("doc") or None)
        # a brief or a request is for the side holding the project; a project never handed
        # off belongs to whichever profile here defines it
        holder = p.get("holder") or next((sd for sd, s in mine.items() if p["name"] in (s.get("projects") or [])), None)
        if holder in mine and (p["state"] != "sent" or not p.get("holder")):
            for i in p.get("intents", []):
                key = "intent:%s/%s" % (p["name"], i["file"])
                if key not in dismissed:
                    item("brief", p, holder, i.get("to"), i.get("note"), i.get("at"), key,
                         doc=i.get("doc") or (p.get("doc") or {}).get("name"), to=resolve(d, i.get("to"), holder))
            for r in p.get("requests", []):
                key = "req:%s/%s" % (p["name"], r["file"])
                if r.get("from") != holder and key not in dismissed:
                    item("request", p, holder, r.get("from"), r.get("note"), r.get("at"), key)
        for st in p.get("settling", []):
            if st.get("side") in mine:
                item("settling", p, st["side"], None, ", ".join(st.get("needs", [])), st.get("at"),
                     "settle:%s/%s" % (p["name"], st["side"]), needs=st.get("needs", []))
        # something this Mac sent, claimed on the other side: news, not a task
        h = p.get("history", [])
        if last.get("verb") == "claim" and len(h) >= 2 and h[-2]["verb"] == "handoff" \
                and h[-2]["side"] in mine and p.get("holder") not in mine:
            item("delivered", p, h[-2]["side"], p.get("holder"), None, last.get("at"),
                 "done:%s/%s" % (p["name"], last.get("file", "")))
    return out


def show_inbox(d):
    items = [i for i in d["inbox"] if i["kind"] != "delivered"]
    if not items:
        print("nothing waiting on %s" % d["me"])
    for i in items:
        p, who = i["project"], i.get("profile_name") or i["side"]
        if i["kind"] == "arrival":
            print("↓ %s — from %s, for %s (%s)" % (p, i["other"], who, i["side"]))
            print("    tandem %sreceive \"%s\" --defer" % (prof(i), p))
        elif i["kind"] == "brief":
            print("↑ %s — brief %s ready to send to %s" % (p, i.get("doc") or "", i.get("to") or "“%s” (unknown — name a side)" % i["other"]))
            print("    tandem %ssend \"%s\" --to %s%s" % (prof(i), p, i.get("to") or "SIDE", (" --note \"%s\"" % i["note"]) if i["note"] else ""))
        elif i["kind"] == "request":
            print("? %s asks for %s, held by %s" % (i["other"], p, i["side"]))
            print("    run /handoff in its Cowork session, then: tandem %ssend \"%s\" --to %s" % (prof(i), p, i["other"]))
        elif i["kind"] == "settling":
            print("⏸ %s — received; waits for %s's Claude to quit: %s" % (p, who, i["note"]))
            print("    tandem %ssettle \"%s\"" % (prof(i), p))
        print("    key: %s" % i["key"])


def prof(i):
    return "" if i.get("profile") in (None, "default") else "--profile %s " % i["profile"]


STATES = {"held": "held by", "sent": "on its way to", "unrecorded": "never handed off",
          "unreadable": "newest event not readable yet (dataless)"}


def show(d):
    me = d["me"]

    def who(side):
        if not side:
            return ""
        return side + ("  (this Mac)" if side.split("@")[0] == me else "")

    print("Macs")
    for m in d["machines"]:
        if m.get("this"):
            bits = ["this Mac"]
        elif m.get("silent"):
            bits = ["known from handoffs; publishes no card — older Tandem, or not running"]
        else:
            bits = ["seen %s min ago" % m.get("age_minutes", "?")]
        if m.get("drive"):
            bits.append("iCloud " + str(m["drive"].get("state")))
        if m.get("version"):
            bits.append("Tandem " + m["version"])
        print("  %s  (%s)" % (m["mac"], " · ".join(bits)))
        for s in m.get("sides", []):
            print("      %-22s %-12s %-28s %s" % (s["side"], s.get("name") or "", s.get("email") or ("" if m.get("silent") else "not signed in"),
                                                 "open" if s.get("open") else ""))
    print("\nShared projects")
    for p in d["projects"]:
        last = p.get("last") or {}
        print("  " + p["name"])
        print("      %s %s   (%s %s)" % (STATES.get(p["state"], p["state"]), who(p["holder"]),
                                          last.get("verb") or "", last.get("at") or ""))
        if last.get("note"):
            print("      note: " + last["note"])
        for i in p.get("intents", []):
            print("      ↑ brief ready to send to %s: %s" % (i.get("to") or "?", i.get("doc") or ""))
        for r in p.get("requests", []):
            print("      ? %s asks for it (%s)" % (r.get("from"), r.get("at")))
        for s in p.get("settling", []):
            print("      ⏸ %s finishes when Claude quits: %s" % (s.get("side"), " ".join(s.get("needs", []))))
    if d["unshared"]:
        print("\nOnly on one Mac — not in the shared tree, so a handoff can't reach them")
        for u in d["unshared"]:
            print("  %-44s %s" % (u["project"], u["side"]))


# ---- watch: the app's background half, headless ----------------------------------------

WATCH_USAGE = """usage: tandem watch [--once] [--json] [--interval N] [--on-event CMD] [--no-act]

  --once          one pass, then exit (cron, CI, a script's poll loop)
  --json          one JSON object per line: {"event": ..., "at": ..., ...the inbox item}
  --interval N    seconds between passes (default: tandem config get watch-interval)
  --on-event CMD  run CMD for each event, the event's JSON on stdin and TANDEM_EVENT set
  --no-act        report only: never receive, send or settle, whatever the settings say
  --notify        also post a macOS notification for each event (for a Mac without the app)

Events: arrival · brief · request · delivered (announced once each), and what watch did about
them: received · receive-failed · sent · send-failed · settled · settle-failed."""


def cmd_watch(tandem, confdir, *argv):
    import subprocess
    args = list(argv)
    if "-h" in args or "--help" in args:
        print(WATCH_USAGE)
        return

    def opt(name, default=None):
        if name in args:
            i = args.index(name)
            return args[i + 1] if i + 1 < len(args) else default
        return default
    once, as_json, act = "--once" in args, "--json" in args, "--no-act" not in args
    hook = opt("--on-event")
    notify = "--notify" in args

    def run(*a):
        r = subprocess.run([tandem] + list(a), capture_output=True, text=True)
        return r.returncode, r.stdout, r.stderr

    def config():
        rc, out, _ = run("config", "--json")
        try:
            return json.loads(out)
        except Exception:
            return {}

    seen_file = os.path.join(confdir, "watch-seen.json")
    seen = load_list(seen_file)

    def emit(event, item=None, **extra):
        rec = dict(item or {})
        rec.update(extra)
        if "at" in rec:
            rec["item_at"] = rec.pop("at")   # when it happened; "at" is when watch saw it
        rec["event"], rec["at"] = event, now_ts()
        rec = iso_all(rec)
        if as_json:
            print(json.dumps(rec), flush=True)
        else:
            what = rec.get("project", "")
            detail = {"arrival": "arrived from %s for %s" % (rec.get("other"), rec.get("side")),
                      "brief": "brief ready to send to %s" % (rec.get("to") or rec.get("other")),
                      "request": "%s asks for it" % rec.get("other"),
                      "delivered": "received by %s" % rec.get("other")}.get(event, rec.get("detail", ""))
            print("%s  %-14s %s  %s" % (rec["at"], event, what, detail), flush=True)
        if notify:
            title = "%s — %s" % (rec.get("project", "Claude Tandem"), event.replace("-", " "))
            body = {"arrival": "from %s for %s · tandem receive" % (rec.get("other"), rec.get("side")),
                    "brief": "ready to send to %s · tandem send" % (rec.get("to") or rec.get("other")),
                    "request": "%s asks for it" % rec.get("other"),
                    "delivered": "received by %s" % rec.get("other")}.get(event, rec.get("detail", ""))
            esc = lambda x: str(x).replace("\\", "\\\\").replace('"', '\\"')
            subprocess.run(["osascript", "-e", 'display notification "%s" with title "%s"' % (esc(body), esc(title))],
                           capture_output=True)
        if hook:
            env = dict(os.environ, TANDEM_EVENT=event)
            try:
                subprocess.run(hook, shell=True, input=json.dumps(rec), text=True, env=env, timeout=300)
            except Exception as e:
                print("on-event failed: %s" % e, file=sys.stderr)

    def recent(at, days=3):
        t = ts_epoch(at or "") or (datetime.datetime.strptime(at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC).timestamp()
                                   if at and "-" in at else None)
        return t is None or time.time() - t < days * 86400

    def as_profile(item):
        p = item.get("profile")
        return [] if p in (None, "default") else ["--profile", p]

    def last_error(out, err):
        lines = [l for l in (err + out).splitlines() if l.startswith("error")]
        rest = (err or out).strip().splitlines()
        return lines[0] if lines else (rest[-1] if rest else "")

    last_presence = 0
    while True:
        cfg = config()
        if time.time() - last_presence > 300:
            run("presence")
            last_presence = time.time()
        rc, out, err = run("inbox", "--json")
        try:
            items = json.loads(out)["inbox"]
        except Exception:
            print("watch: could not read the inbox: %s" % (err.strip() or out[:200]), file=sys.stderr)
            items = []
        for it in items:
            if it["kind"] == "settling":
                if act and not it.get("profile_open"):
                    rc, o, e = run(*(as_profile(it) + ["settle", it["project"]]))
                    if rc == 0:
                        emit("settled", it)
                    elif rc not in (3, 75):
                        emit("settle-failed", it, detail=last_error(o, e))
                continue
            if it["key"] in seen or not recent(it.get("at"), 1 if it["kind"] == "delivered" else 3):
                continue
            seen.append(it["key"])
            emit(it["kind"], it)
            if not act:
                continue
            if it["kind"] == "arrival" and cfg.get("on-arrival") == "auto":
                rc, o, e = run(*(as_profile(it) + ["receive", it["project"], "--defer"]))
                if rc == 0:
                    emit("received", it)
                elif rc != 75:
                    emit("receive-failed", it, detail=last_error(o, e))
            elif it["kind"] == "brief" and cfg.get("on-brief") == "auto" and it.get("to"):
                a = as_profile(it) + ["send", it["project"], "--to", it["to"]]
                if it.get("note"):
                    a += ["--note", it["note"]]
                if it.get("doc"):
                    a += ["--doc", it["doc"]]
                rc, o, e = run(*a)
                if rc == 0:
                    emit("sent", it)
                elif rc != 75:
                    emit("send-failed", it, detail=last_error(o, e))
        try:
            tmp = seen_file + ".tmp"
            json.dump(seen[-400:], open(tmp, "w"))
            os.replace(tmp, seen_file)
        except OSError:
            pass
        if once:
            return
        try:
            interval = int(opt("--interval") or cfg.get("watch-interval") or 60)
        except ValueError:
            interval = 60
        time.sleep(max(10, interval))


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "watch":
        cmd_watch(*sys.argv[2:])
        sys.exit(0)
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "where":
        cmd_where(*args)
    elif cmd == "presence":
        cmd_presence(*args)
    else:
        sys.exit(__doc__)
