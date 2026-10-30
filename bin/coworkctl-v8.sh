#!/bin/bash
# coworkctl v8 — move a Cowork workload between two Macs.
#
# SHARED ROOT is configurable. Resolution order:
#   1. $MIRROR_ROOT
#   2. ~/.config/claude-macos-mirror/root   (a file containing the path)
#   3. iCloud Drive default
# It does NOT have to be the same path on both Macs. The stable path is the
# symlink at ~/Documents/Claude/Projects/<Name>, and the Cowork folder grant is
# per-machine anyway -- so Google Drive or Dropbox work even though their paths
# embed an account name.
#
# TRANSPORT: the shared drive only. Deliberately.
#
# v3 also pushed directly over SSH (0.95s, md5-verified) but writing into an
# iCloud-synced folder means TWO writers for one path -- iCloud delivering its
# copy while rsync delivers the same bytes. FileProvider forks rather than
# reconciles, and we observed real conflict copies on both Macs:
# "events 2", "peers 2.conf", "coworkctl-v3 2.sh". One writer only, now.
#
# Consequence you must respect: THIS IS NOT SYNCHRONOUS.
# Measured between these two Macs: ~54s best case, several minutes when the far
# Mac has been asleep, and stalled entirely while it naps. handoff STAGES work.
# Only pickup on the far side proves delivery. Never report staged as delivered.
#
# STATE IS APPEND-ONLY. Every transition writes a NEW event file; nothing is
# rewritten, because iCloud does not reliably propagate an in-place modification
# of a file the peer has already cached. Same reason this script is versioned
# rather than edited: write coworkctl-v5.sh, never edit v4 once it has shipped.
#
# v7: handoff takes --doc, and picks the NEWEST HANDOFF*.md rather than the
# alphabetically first. v6 used `ls HANDOFF*.md | head -1`, so a project with a
# second topic silently attached the wrong document and pickup printed it with
# nothing to indicate the mismatch.
#
# v8: ME honors MIRROR_ME, so each Claude profile on one Mac is its own side of a
# handoff (<Mac>@<profile>). Unset, it is the ComputerName exactly as before.

set -uo pipefail

default_root(){ echo "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Claude"; }
if [ -n "${MIRROR_ROOT:-}" ]; then ROOT="$MIRROR_ROOT"
elif [ -f "$HOME/.config/claude-macos-mirror/root" ]; then
  ROOT="$(sed -e 's/[[:space:]]*$//' -e '/^$/d' "$HOME/.config/claude-macos-mirror/root" | head -1)"
  ROOT="${ROOT/#\~/$HOME}"
else ROOT="$(default_root)"; fi
PROJECTS="$ROOT/Projects"
HANDOFF="$ROOT/_handoff"
# Ownership events live INSIDE each project folder, not in the shared _handoff tree.
# A Cowork session is sandboxed to the project folder it was granted -- it cannot see
# ~/workspace or _handoff/ -- so per-project state has to live where the session can
# reach it. This is what lets the /handoff skill record ownership with a plain file
# write instead of shelling out to this CLI.
events_dir(){ echo "$PROJECTS/$1/.handoff/events"; }
# MIRROR_ME is set by `mirror --profile`: one Mac running several Claude accounts is
# several sides of a handoff, named <Mac>@<profile>.
ME="${MIRROR_ME:-$(scutil --get ComputerName)}"

die(){ echo "error: $*" >&2; exit 1; }

# iCloud does not push to an idle Mac; the directory must be enumerated before a
# read. `test -f` on a missing path does NOT trigger it -- listing the parent does.
refresh(){
  ls "$HANDOFF" >/dev/null 2>&1; ls "$PROJECTS" >/dev/null 2>&1
  for d in "$PROJECTS"/*/; do
    [ -d "$d" ] || continue
    ls "$d" >/dev/null 2>&1; ls "$d/.handoff" >/dev/null 2>&1; ls "$d/.handoff/events" >/dev/null 2>&1
  done
  sleep "${1:-2}"
}

state(){
  python3 - "$(events_dir "$1")" <<'PY'
import os,sys,json,glob
fs=sorted(glob.glob(os.path.join(sys.argv[1],"*.json")))
if not fs: sys.exit(1)
e=json.load(open(fs[-1]))
owner=e.get("to") if e["verb"]=="handoff" else e["machine"]
print("\t".join([owner,e["verb"],e["at"],e.get("note","") or "",e.get("handoff_doc","") or "",str(len(fs))]))
PY
}

emit(){
  mkdir -p "$(events_dir "$1")"
  python3 - "$(events_dir "$1")" "$1" "$2" "$ME" "$3" "$4" "$5" <<'PY'
import sys,json,os,datetime
d,project,verb,machine,to,note,doc=sys.argv[1:8]
ts=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
p=os.path.join(d,f"{ts}-{machine}-{verb}.json")
json.dump({"project":project,"verb":verb,"machine":machine,"to":to,
           "note":note,"handoff_doc":doc,"at":ts},open(p,"w"),indent=2)
print(os.path.basename(p))
PY
}

# Evicted iCloud files are DATALESS, not .icloud stubs: right name, right st_size,
# but st_blocks==0 and content still remote. No stub file warns you and `du` cannot
# see it. Reading one returns empty/truncated content WITH NO ERROR. Hence this.
materialize(){
  python3 - "$1" "${2:-180}" <<'PY'
import os,sys,time
root,timeout=sys.argv[1],int(sys.argv[2])
def dataless():
    out=[]
    for dp,_,fn in os.walk(root):
        if ".handoff" in dp.split(os.sep): continue
        for f in fn:
            p=os.path.join(dp,f)
            try: st=os.lstat(p)
            except OSError: continue
            if os.path.isfile(p) and st.st_size>0 and st.st_blocks==0: out.append(p)
    return out
pending=dataless()
if not pending: print("  all files materialized"); sys.exit(0)
print(f"  {len(pending)} dataless file(s) — forcing download")
start=time.time()
while time.time()-start<timeout:
    for p in pending:
        try:
            with open(p,'rb') as fh:
                while fh.read(1<<20): pass
        except OSError: pass
    pending=dataless()
    if not pending: print(f"  all materialized in {time.time()-start:.0f}s"); sys.exit(0)
    time.sleep(3)
print(f"  WARNING: {len(pending)} still remote after {timeout}s",file=sys.stderr); sys.exit(1)
PY
}

cmd_status(){
  refresh
  echo "machine: $ME"
  echo "shared root: $ROOT"
  echo "transport: shared drive (not synchronous — expect ~1min, longer if the peer slept)"
  echo
  local any=0
  if true; then
    for d in "$PROJECTS"/*/; do
      [ -d "$d/.handoff/events" ] || continue; any=1
      local p; p="$(basename "$d")"
      if s="$(state "$p")"; then
        IFS=$'\t' read -r owner verb at note doc n <<< "$s"
        local mark=" "; [ "$owner" = "$ME" ] && mark="*"
        local who="$owner"; [ "$owner" = "$ME" ] && who="YOU"
        printf " %s %-22s owner: %-12s last: %-8s %s (%s events)\n" "$mark" "$p" "$who" "$verb" "$at" "$n"
        [ -n "$note" ] && echo "     note: $note"
      fi
    done
  fi
  [ "$any" = 0 ] && echo " (no handoffs recorded yet)"
  echo; echo "shared projects:"
  for d in "$PROJECTS"/*/; do [ -d "$d" ] && echo "  $(basename "$d")"; done
}

cmd_handoff(){
  local project="${1:-}" to="" note="" wait_ack=0 doc=""
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --to) to="$2"; shift 2;;
      --note) note="$2"; shift 2;;
      --doc) doc="$2"; shift 2;;
      --wait) wait_ack=1; shift;;
      *) die "unknown flag: $1";;
    esac
  done
  [ -n "$project" ] || die "usage: coworkctl.sh handoff <project> --to <machine> [--note ...] [--wait]"
  [ -n "$to" ] || die "--to <machine> is required"
  [ -d "$PROJECTS/$project" ] || die "'$project' is not in the shared tree"

  echo "handing off '$project': $ME -> $to"
  echo "materializing (so real bytes exist to upload):"
  materialize "$PROJECTS/$project" || echo "  (proceeding despite warnings)"

  # NEWEST doc, not the alphabetically first -- a second topic in the same project
  # otherwise attaches a stale document and pickup prints it looking perfectly normal.
  if [ -n "$doc" ]; then
    [ -f "$PROJECTS/$project/$doc" ] || die "no such handoff document: $doc"
  else
    doc="$(cd "$PROJECTS/$project" && ls -t HANDOFF*.md 2>/dev/null | head -1)"
    local ndocs; ndocs="$(cd "$PROJECTS/$project" && ls HANDOFF*.md 2>/dev/null | grep -c .)"
    [ "${ndocs:-0}" -gt 1 ] && echo "  note: $ndocs HANDOFF*.md present — using the newest, $doc"
  fi
  [ -n "$doc" ] || echo "  note: no HANDOFF*.md — files will travel without context"
  echo "event: $(emit "$project" handoff "$to" "$note" "$doc")"
  echo
  echo "STAGED — not delivered. The shared drive carries this in ~1min at best,"
  echo "longer if $to has been asleep. It lands when $to wakes."
  echo "Do not edit '$project' here until it comes back."

  if [ "$wait_ack" = 1 ]; then
    echo
    echo "waiting for $to to run pickup (Ctrl-C to stop)..."
    for i in $(seq 1 45); do
      refresh 8
      if s="$(state "$project")"; then
        IFS=$'\t' read -r owner verb at _ <<< "$s"
        [ "$verb" = "claim" ] && { echo "ACK: $owner claimed '$project' at $at"; return 0; }
      fi
    done
    echo "no ACK after ~6min — $to is probably asleep. It will pick up on wake."
  fi
}

cmd_pickup(){
  refresh
  local project="${1:-}"
  if [ -z "$project" ]; then
    local mine=()
    for d in "$PROJECTS"/*/; do
      [ -d "$d/.handoff/events" ] || continue
      local p; p="$(basename "$d")"
      if s="$(state "$p")"; then IFS=$'\t' read -r owner _ <<< "$s"; [ "$owner" = "$ME" ] && mine+=("$p"); fi
    done
    [ ${#mine[@]} -eq 0 ] && die "no project is currently handed off to $ME"
    [ ${#mine[@]} -gt 1 ] && die "several waiting: ${mine[*]} — name one"
    project="${mine[0]}"
  fi
  s="$(state "$project")" || die "no handoff recorded for '$project'"
  IFS=$'\t' read -r owner verb at note doc n <<< "$s"
  if [ "$owner" != "$ME" ]; then
    echo "WARNING: '$project' is owned by '$owner', not this machine ($ME)."
    echo "Editing it here risks iCloud conflict copies. Ctrl-C to stop; continuing in 5s."
    sleep 5
  fi
  echo "picking up '$project' on $ME"
  echo "materializing:"
  materialize "$PROJECTS/$project" || die "could not fully download — retry when iCloud settles"
  echo "event: $(emit "$project" claim "$ME" "$note" "$doc")"
  echo "claimed by $ME (the other Mac sees this once iCloud carries the event over)"
  if [ -n "$doc" ] && [ -f "$PROJECTS/$project/$doc" ]; then
    echo; echo "================ $doc ================"; echo
    cat "$PROJECTS/$project/$doc"
  fi
}

cmd_log(){
  refresh
  local project="${1:-}"; [ -n "$project" ] || die "usage: coworkctl.sh log <project>"
  for f in "$(events_dir "$project")"/*.json; do
    [ -f "$f" ] || continue
    python3 -c "import json,sys;e=json.load(open(sys.argv[1]));print(f\"  {e['at']}  {e['machine']:<10} {e['verb']:<8} -> {e.get('to') or e['machine']}\")" "$f"
  done
}

# Detect iCloud conflict copies. Reports only -- deleting by pattern is how a real
# project file got destroyed during setup ("GS Vintage VII 2023 Exchanges.qif"
# matched a "* 2*" glob). Look at the list, then remove by exact path yourself.
cmd_conflicts(){
  refresh
  echo "possible iCloud conflict copies under $ROOT:"
  find "$ROOT" \( -name '* 2.*' -o -name '* 2' -o -name '*conflicted copy*' \) -print 2>/dev/null \
    | sed "s|$ROOT|  |" || true
  echo "(nothing listed = clean; remove anything real by exact path, never by glob)"
}

case "${1:-status}" in
  status) cmd_status;;
  handoff) shift; cmd_handoff "$@";;
  pickup) shift; cmd_pickup "$@";;
  log) shift; cmd_log "$@";;
  conflicts) cmd_conflicts;;
  materialize) shift; materialize "${1:-$PROJECTS}";;
  *) die "usage: coworkctl.sh {status|handoff <project> --to <machine> [--wait]|pickup [project]|log <project>|conflicts|materialize [path]}";;
esac
