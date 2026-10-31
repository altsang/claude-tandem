# Claude Tandem — measured findings

> **Renamed 2026-10-30:** Claude MacOS Mirror is now **Claude Tandem**. The `mirror` command is `tandem`, `claude-profile` is `tandem profile`, and config moved from `~/.config/claude-macos-mirror` to `~/.config/claude-tandem`. Commands below use the new names. The findings themselves are unchanged.

Findings 1–15 were verified on macOS 26.6.2 (Ji-su) and Darwin 25.5 (Madoka) from 2026-08-18; 16–18 on macOS 27 (both Macs) in September–October 2026. Where a later finding corrects an earlier one, the earlier one says so in place.
These are not style preferences — each one cost real debugging time, and several look like
"iCloud is broken" until you know the mechanism.

---

## 1. Evicted iCloud files are *dataless*, not `.icloud` stubs

A file evicted from local storage keeps its name and its correct `st_size`, but `st_blocks == 0`
and the content is still in the cloud. **There are no `.icloud` stub files on modern macOS** —
searching for them returns zero even when most of the drive is evicted.

Reading a dataless file returns empty or truncated content **with no error**.

```python
st.st_size > 0 and st.st_blocks == 0   # the only reliable test
```

To materialize: read the file through to EOF, then re-check. `brctl download` does not block until
complete.

Measured: `du -sh` reported **23 MB** for an iCloud Drive holding **~1.03 GB across 397 files**,
75 of them dataless. `du` counts materialized blocks only, so it is blind to exactly the problem
you are looking for.

This is why `pickup` materializes before returning. During the acceptance test it caught a real
dataless `.qif` and downloaded it in 1s — without that, the receiving session would have parsed an
empty financial extract.

## 2. In-place modifications may never propagate

iCloud reliably carries **new** files between Macs. An in-place **modification** of a file the peer
has already cached can stay stale indefinitely — FileProvider pins the cached copy.

Measured: a rewritten `coworkctl.sh` was still the old md5 on the receiving Mac minutes later,
while a brand-new file crossed in ~54s.

Two consequences, both load-bearing:

- **Ownership state is an append-only log.** Every transition writes a NEW event file under
  `_handoff/events/<Project>/`. Nothing is ever rewritten. Current owner = newest event.
- **The tool is versioned, not edited.** Write `coworkctl-v5.sh`; never edit v4 once it has shipped.
  Callers resolve `coworkctl-v*.sh | sort -V | tail -1`.

## 3. Enumeration sets your latency

iCloud does not push to an idle Mac. The directory must be enumerated (`ls`) before a read, and
`test -f` on a missing path does **not** trigger it.

Critically, you must enumerate the **whole parent chain** — `_handoff/`, then `events/`, then
`events/<Project>/` — not just the leaf.

Measured on the same file: enumerating only the leaf, an event was still missing after **220s**.
Enumerating the parent chain, the next one landed in **30s**. Most "iCloud is slow" readings during
development were really "the reader never enumerated properly."

`refresh()` walks the whole chain. Do not trim it.

## 4. Two writers to one iCloud path produce conflict copies

Pushing via rsync into an iCloud-synced folder while iCloud delivers the same bytes makes
FileProvider fork them into `name 2.ext`. Observed on both Macs: `events 2`, `peers 2.conf`,
`coworkctl-v3 2.sh`, and a duplicated `.qif`.

Keep one writer. This is why the direct transport was removed, and why this git repo lives outside
iCloud — a `.git` directory in a synced folder is the same hazard with worse consequences.

## 5. macOS ships openrsync

`rsync --version` reports "openrsync: protocol version 29 / rsync version 2.6.9 compatible".
There is no `--protect-args` and no `-s`.

The shared path contains spaces (`Mobile Documents`), and a remote spec is parsed by the remote
shell, so remote paths must be **single-quoted**:

```bash
rsync -a -e ssh "$SRC/" "user@host:'$DST/'"
```

Without it: `server receiver mode requires two argument`.

(Not used by the tool any more, but needed for any manual administration over SSH.)

## 6. A sleeping laptop is indistinguishable from broken sync

Ji-su defaults to `sleep 1` — one minute of inactivity — and Low Power Mode (battery only) defers
iCloud sync. Several "iCloud is stalled" measurements were really "the laptop napped between SSH
calls."

Before diagnosing sync:

```bash
ssh <peer> 'uptime; pmset -g ps'
ssh <peer> 'nohup caffeinate -dimsu -t 900 >/dev/null 2>&1 &'   # pin awake for a test window
```

## 7. Attaching a folder makes a project machine-bound

A Claude project lives in one of two places, decided by whether a local folder is attached:

- **No folder** → server-side. Appears on claude.ai and on every Mac.
- **Folder attached** → written into *that Mac's* `spaces.json`, shown with a `Local` badge, and
  invisible on the web and on the other Mac.

```
~/Library/Application Support/Claude/local-agent-mode-sessions/<account>/<org>/spaces.json
```

Plain JSON. Each entry is the whole definition: `id`, `name`, `folders[].path`, `instructions`,
`createdAt`, `updatedAt`.

Counted on one setup: 8 cloud projects visible on the web and both Macs; 11 local to Madoka; 2
local to Ji-su. The local counts match each machine's `spaces.json` exactly. The UI shows a folder
name beside the badge only when an entry has exactly one folder — entries with several show a bare
`Local` badge, which is a handy way to sanity-check the UI against the file.

**A local project therefore CAN be copied** — it is a JSON object. `tandem project-export` writes
it into the shared tree, `tandem project-import` splices it into the other Mac's `spaces.json` with
the folder path rewritten. What does **not** travel is the conversation history inside the project;
that is what the handoff document is for.

Edit `spaces.json` only while Claude is quit — a running app rewrites it from memory and silently
discards the change. `project-import` and `project-repath` refuse to run otherwise.

**How this was originally got wrong.** An earlier pass concluded "Cowork spaces are device-local and
cannot travel", from two bad inferences: `claude.ai/projects` did not list them (true, but only
because folder-attached projects are not server-side), and `claude.ai/project/<id>` did not resolve
(true, but the Cowork URL form is `claude.ai/cowork/project/<id>`). Neither was evidence that the
definition was unmovable. `spaces.json` was never opened. The lesson: when concluding that
something is impossible, find the file that stores it first.

Related: in session JSON, `title` is the **chat** name and `spaceId` points at the `spaces.json`
entry. A project's real name is recorded only in `spaces.json`.

## 8. A symlinked folder registers as connected, then fails every read

**Never grant Cowork a symlinked folder.** Grant the real path.

Symptom: `get_device_info` reports the folder as connected and the UI shows it attached, but every
operation inside it fails with:

> `... is not inside a folder connected to Cowork on this device`

Listing fails, staging files fails, and the local shell mount comes up empty. Because the folder
*looks* connected, the error points nowhere near the cause.

Mechanism: the grant is registered against the symlink path. When Cowork resolves an actual file it
gets the real path — here `~/Library/Mobile Documents/…` — compares that against the connected
scope, finds it outside, and denies it.

Verified 2026-08-19 on Ji-su. Same project, same files, same machine:

| Granted path | Result |
|---|---|
| `~/Documents/Claude/Projects/<P>` (symlink) | registered, every read denied |
| `~/Library/Mobile Documents/…/Projects/<P>` (real) | reads correctly |

Confirmed with a random token in a canary file that could not be inferred from context.

Consequences, all now built in:

- `tandem migrate` no longer leaves a symlink behind; it repoints the project at the shared copy.
- `tandem link` is deprecated, creates nothing, and explains this.
- `tandem path <Project>` prints the exact path for the rare hand grant, and copies it **only when
  stdout is a terminal** — inside `cd "$(tandem path X)"` it must not clobber the handoff document
  that `tandem receive` just put on the clipboard.
- `tandem check` flags any project whose folder is a symlink and prints the repath command.
- `tandem project-repath <Project> <path>` fixes an existing one.

If you ever do open the picker, Finder will not browse to `~/Library/Mobile Documents` — it is
hidden, and Finder relabels `com~apple~CloudDocs` as "iCloud Drive". Press **⌘⇧G** and paste.

## 9. The folder "grant" is one JSON field — no picker required

Attaching a folder in the app writes exactly one thing: `folders[].path` on the project's entry in
`spaces.json`. There is no bookmark blob, permission token or consent record anywhere else in
`~/Library/Application Support/Claude` — a UI-attached project and one written by `tandem` have
identical key sets (`createdAt, folders, id, instructions, links, name, projects, updatedAt`).
`.project-cache/` holds cloud-project content only; the `grantedAt` keys in session files are
computer-use app permissions, unrelated to folders.

The app then **seeds each new session's `userSelectedFolders` from that field** — sessions in a
project all carry its path without the picker ever being reopened. That is why writing the field is
a complete grant rather than half of one, and why a symlinked path fails: the session's connected
scope is that string, and a resolved real path falls outside it (finding 8).

Two observations pinned it down:

- 2026-08-19 20:46 `tandem` wrote the shared path for `Adobe Stock Plan` while Claude was quit;
  the app launched at 20:46:10 and **rewrote `spaces.json` from memory at 20:52 keeping that
  path** — it adopted a link it had never shown a picker for.
- 2026-08-20 `Adobe Stock Plan` was imported onto the second Mac with
  `tandem project-import --wait`, which writes the folder link itself. The picker was never
  opened on that machine and Cowork read the project's files.

So the whole per-machine grant step is `migrate` / `project-import` / `project-repath`, with Claude
quit. What is *not* scriptable: the one-time macOS consent for the location (`TCC` shows
`kTCCServiceFileProviderDomain` allowed for `com.anthropic.claudefordesktop` once granted), and any
write while the app is running — it rewrites `spaces.json` from memory on exit and discards it.

## 10. `isUploaded` is the only way to know the bytes left this Mac

`handoff` could only ever report work as *staged*: the local file is complete, and nothing said
whether iCloud had taken it. The signal that answers it is FileProvider's, via
`fileproviderctl evaluate <file>`, which prints `isUploaded` alongside the download keys.

Verified 2026-08-20 on Darwin 25.5:

| Probe | Result |
|---|---|
| `fileproviderctl evaluate FILE` → `isUploaded` | **works** — 0 immediately after write, 1 when uploaded |
| `fileproviderctl evaluate FILE` → `isUploading` | useless — stayed 0 for an entire 110s upload |
| `brctl status PATH` | fails: *"Client zone not found"* — the legacy CloudDocs path is dead |
| `mdls -name kMDItemIsUbiquitous` | `(null)`, as are the other `kMDItemUbiquitous*` keys |

A 25 MB file written into the shared tree read `isUploaded = 0` at creation and flipped to 1 after
~110s. So poll `isUploaded`, never `isUploading`.

Two consequences now built into `tandem send`:

- It polls every file **including `.handoff/`** — the ownership event is precisely the part that
  tells the other Mac it owns the project, and it uploads like any other file.
- If the probe returns no `isUploaded` key at all (a drive that is not FileProvider-backed), it
  says upload state is unavailable and exits 2 rather than blocking or claiming false proof.

**Uploaded is still not delivered.** Only the receiving Mac's `claim` event proves that, which is
what `send --wait` waits for.

### Why pickup could not have caught a partial transfer

An un-uploaded file is not dataless on the far Mac — it is **absent from the listing entirely**.
`/pickup` read "every file in the folder" with no idea how many there should be, so a partial
transfer looked exactly like a complete one. `project-export`/`import` had solved this with a
manifest and md5s; handoff had no equivalent until `send` started writing the same manifest and
`receive` started verifying against it.

## 11. What a verified transfer actually costs, end to end

First real cross-Mac run of `send`/`receive`, 2026-08-20, Madoka → Ji-su over iCloud.

A plumbing test with a 10 MB payload:

```
20260820T091632Z  Madoka  handoff -> Ji-su    upload verified 4/4 in 56s
20260820T091918Z  Ji-su   claim   -> Ji-su    2m46s after the send
                                              claim visible on Madoka ~90s later
```

Then the live project (21.6 KB — a spreadsheet and an 8.5 KB handoff document):

```
20260820T092533Z  Madoka  handoff -> Ji-su    upload verified 5/5 in 25s
20260820T092745Z  Ji-su   claim   -> Ji-su    2m12s after the send
```

So the shape is: **upload is fast and knowable, delivery is slow and only observable from the far
side.** Uploading is bounded by size (56s for 10 MB, 25s for 21 KB, ~110s for 25 MB) and can be
confirmed locally. Delivery to an idle peer runs ~2–3 minutes regardless of size, and the only
proof is the `claim` event coming back.

The file count polled is larger than the project's: 5 files for a 2-file project, because the
ownership event and the manifest upload too, and they are exactly what the far Mac needs first.

## 12. A sandboxed session cannot make iCloud deliver — so it cannot tell "missing" from "late"

Observed 2026-08-20 on the live handoff. Every file, `.handoff/events/*.json` included, read
`isUploaded = 1` on the sending Mac. On the receiving Mac, `/pickup` in a Cowork session reported
**"no `.handoff` directory"** — and it was right about what it could see.

iCloud does not push to an idle Mac; a parent has to be enumerated before new entries appear
(finding 3). A Cowork session listing its project folder does not prod the drive hard enough to
surface a hidden subdirectory that has never been materialized there. The data was in the cloud the
whole time.

The session therefore cannot distinguish **not sent**, **not yet delivered**, and **delivered but
not enumerated** — three states with three different responses, and it sees one. `tandem receive`
resolves it by listing the whole chain (`_handoff/`, `Projects/`, the project, `.handoff/`,
`.handoff/events/`) every six seconds until the event appears, then verifying by md5.

Practical consequence: **when a skill says something is missing from a shared folder, do not believe
it until a terminal has looked.** Run `tandem receive`, or at minimum `ls` the parent chain.

## 12b. A project's instructions reach the session prompt — which makes them a lock

A local project's `instructions` field in `spaces.json` is copied verbatim into the Cowork
session's `systemPrompt`. Verified 2026-08-20: a Quicken Reconciliation session's `systemPrompt`
is 43,551 characters and contains that project's instructions exactly.

Two properties make it useful as a checkout lock: it is **per-machine** (`spaces.json` is not
synced), and it is read **before the user types**. So the sending Mac can carry a notice its own
sessions obey while the receiving Mac sees nothing.

`tandem send --hold` writes two things, both reversed by `receive`:

- the notice, wrapped in `<!-- mirror:hold -->` markers
- `folders[]` emptied, so a session that ignores the notice cannot read the folder at all

The markers exist because `project-export` copies `instructions` wholesale. Without stripping,
"CHECKED OUT TO Ji-su" would be exported *to* Ji-su and live in its system prompt permanently.
Export and import both strip marked blocks.

The original folder paths are stashed in `~/.config/claude-tandem/held/<Project>.json`, not
in `spaces.json`, because the app rewrites that file from memory and may drop keys it does not
recognise — which would strand the project with no folder and no record of what it used to be.

**Do not lock the files instead.** `chmod -R a-w` or `chflags uchg` on the project folder targets
the wrong process: after a handoff that folder is exactly where iCloud must write the *other* Mac's
changes. Mode bits may also propagate. Locking the project definition touches no file and leaves
sync untouched.

## 12c. Local projects DO have memory — on one Mac, in Application Support

An earlier version of these notes said a local project has "no project memory to fall back on."
That is wrong, and it mattered: it made the handoff document look like the only possible carrier of
context when in fact a large, structured one already exists on disk.

```
~/Library/Application Support/Claude/local-agent-mode-sessions/<account>/<org>/
    spaces/<spaceId>/memory/
        MEMORY.md                    index — one line per memory
        project_*.md  feedback_*.md  reference_*.md  user_*.md
```

Surveyed 2026-08-20 on Madoka:

| Project | Files | Bytes |
|---|---|---|
| K-Culture Tracker | 44 | 410,431 |
| Quicken Reconciliation | 20 | 42,696 |
| Adobe Stock Plan | 12 | 31,047 |
| Portfolio Management | 7 | 12,055 |
| Remodel Addition Project Tracker | 6 | 13,399 |

The content is not incidental. Quicken's holds reconciliation status with dollar figures
(`GS Vintage VII … LP=133,501 DPV=-2,009.89`), workflow corrections (`SPAXX is cash, never a
security`), and tool gotchas (`type fails under Parallels; use single key presses`).

Note this is a **different mechanism** from the cloud-project cache at
`.project-cache/<uuid>/memory.md`, which is a single synced file. The local store is a directory of
files keyed by the `spaces.json` project id.

Two consequences:

- **The docs' premise needs narrowing.** Conversations genuinely never cross. Memory exists but is
  per-machine, so the receiving Mac still starts blank — the handoff document remains load-bearing.
  But "there is no memory" was overstated.
- **It is copyable in principle.** `project-export`/`import` preserve the project `id`, so the
  destination path is deterministic on the other Mac. Carrying `spaces/<id>/memory/` with a handoff
  would give the receiving session everything the sending one learned, not just the topic summary
  someone remembered to write down. Observed 2026-08-20: Adobe Stock Plan had 31 KB of memory on
  Madoka and none on Ji-su, and the handoff document said so in its own words — "the sending
  machine had project memory for this work; Ji-su does not, so everything needed is below."

Implemented 2026-08-20, conservatively. `send` snapshots the holder's store into
`PROJECT/.handoff/memory/<ts>-<machine>/` with an md5 manifest (`snapshot.json`), upload-verified
with everything else; `receive` installs the newest snapshot **only when this Mac's store is
empty**. A non-empty store is refused with instructions — `tandem memory-install <P> --force`
replaces it after copying it to `memory.bak-<ts>` — and a Mac never installs a snapshot it took
itself. Corrupt or undelivered snapshot files abort the install with nothing written.

**Revised 2026-10-30: stores do diverge, so receive now merges.** This said merging was
unnecessary because only the owner writes memory. True, but ownership moves: each Mac writes
while it holds the project, so after a round trip *neither* store is a superset. Adobe Stock Plan,
handed back to Ji-su: Madoka's 11 memories held the method (entry patterns, guardrails), Ji-su's 1
held the newest status (*verified thru 7/15/2026*). Replacing would have dropped that line into a
backup nobody reads. `memory-install --merge` — what `receive` now runs — backs up, adds what this
Mac lacks, skips identical files, appends index lines only for memories it added, and on a clash
keeps this Mac's file and parks the other as `name.from-<Mac>.md`, unindexed, for a person.

## 13. Cowork on a cloud project runs in a bridged VM with per-session folder access

A Cowork session started from a **cloud** project runs in a cloud VM (`/home/claude`, Linux) with a
bridge to the Mac — it reports the machine as e.g. `ji-su-local`. Two consequences:

- **Folder access is per session, not per project.** A folder attached to the project does not
  reach a conversation; each session needs its own grant. Its picker offered only Desktop,
  Downloads, or a typed path.
- Grants under `~/Library` did not succeed through the bridge *in the original testing*. **That
  is now known to be wrong** — see the correction below.

**Corrected 2026-09-25.** Two of Ji-su's remote Quicken sessions hold
`~/Library/Mobile Documents/com~apple~CloudDocs/Claude/Projects/Quicken Reconciliation` as their
granted folder and wrote into it continuously from 2026-08-20 to 2026-09-05 — the reconciliation
notes in that folder are their output. So a bridged session *can* be granted an iCloud path under
`~/Library`; whatever failed in the first test was not a general rule. Do not plan around that
limitation.

What survives: folder access really is **per session, not per project**, so each new conversation
needs its own grant. That is the durable half of this finding.

## 14. A Cowork session is sandboxed to its granted folder — put per-project state inside it

The shell a Cowork session gets on the Mac is an isolated Linux VM that sees **only the project
folder it was granted**. It cannot reach `~/workspace`, the shared `_handoff/` tree, or any other
path, and no additional permission grant changes that. Driving Terminal via computer-use is the
only way to run an outside binary, which is a poor way to run a one-line command.

Everything a session *can* do is a file operation, and all of it can live in the project folder:

| Operation | How the session does it |
|---|---|
| write the handoff document | ordinary file write |
| read the ownership log | JSON files in `PROJECT/.handoff/events/` |
| materialize dataless files | **read them** — reading is what pulls content down |

The first design read that as "a skill must not depend on a CLI", and duplicated the mechanics in
both places. That was wrong in one direction: the sandbox also means a session can **never verify a
transfer** — no `fileproviderctl` for upload state, no manifest outside the folder to md5 against,
no view of the other project. Two implementations of the mechanics, neither able to prove anything.

Revised 2026-08-20, each side now does only what the other cannot:

| | Cowork session | terminal (`tandem`) |
|---|---|---|
| write the handoff document | **only it can** — the context is the conversation | no |
| materialize, manifest, ownership event | no | **yes** |
| verify upload / verify arrival by md5 | impossible from the sandbox | **yes** |
| define the project, link its folder | no — `spaces.json` is outside | **yes** |

So `/handoff` writes the document and stops; `tandem send` carries it. `tandem receive` verifies
and claims; `/pickup` reads the result. One implementation of the mechanics, and the session is
still never asked to do something it cannot check.

Ownership events therefore live at `PROJECT/.handoff/events/TIMESTAMP-MACHINE-verb.json`
(engine v6), not in the shared `_handoff/events/` tree where v4/v5 kept them. Verified 2026-08-19:
an event written as a plain file by hand is read back correctly by the CLI, and vice versa.

The original design put them outside the project because it looked like shared infrastructure. It
is per-project state, and putting it outside made the skill unusable from within a session.

## 15. Custom Cowork skills already sync

`skills-plugin/.../manifest.json` lists user-created skills with server-issued `skillId`s,
`creatorType: "user"`, and server timestamps — it is an account-level manifest.

Confirmed empirically: `parallels-windows-apps` was present on Ji-su at the identical path with
matching account UUIDs, without anyone copying it. Do not build skill-syncing machinery.

Installed skills land in a per-account plugin tree, which is why a search of the obvious places
finds nothing:

```
local-agent-mode-sessions/skills-plugin/<org>/<account>/skills/<name>/SKILL.md
```

**Acted on 2026-09-26.** `tandem deploy` used to zip `handoff.skill` and `pickup.skill` into the
shared tree. That duplicated a mechanism that already works, and the copies went stale: the Aug 20
bundles outlived a correction to the skill's own premises (finding 17) and would have handed
someone superseded instructions months later. `deploy` now deletes them instead of writing them,
by exact path.


## 16. `receive` could never materialize the one file it reads first

Found 2026-09-06, after a `tandem receive` on Ji-su burned its full 900s timeout and reported
`Newest event: none` — while the event sat in the folder, delivered, at its correct size.

```
$ ls -l …/Junipera - MS Korea ATU Partnership/.handoff/events/
-rw------- 1 altsang 328 Sep  6 11:29 20260906T182927Z-Madoka-handoff.json
$ cat …/events/*.json
                                    # ← 328 bytes listed, nothing behind them
```

Dataless, exactly as finding 12 describes. Two defects turned that into a 15-minute dead end
pointed at the wrong machine:

**The materializing walker skips the events directory.** `wait_for_files`' `present()` is the only
code that forces a pull, using `st_size>0 and st_blocks==0` to detect a dataless file and a
whole-file binary read to fix it. Its very first line is:

```python
for dp,_,fn in os.walk(root):
    if ".handoff" in dp.split(os.sep): continue
```

So the project's files get materialized and `.handoff/events/` never does. `newest_event` read it
with a plain `json.load(open(...))`, which returns empty on a dataless file **without** forcing the
pull. `receive` polls that function every 6s and materializes nothing, so a dataless event is not
slow to arrive — it never resolves at all, at any timeout.

**"Absent" and "unreadable" reported identically.** Both branches ended `sys.exit(1)`:

```python
if not fs: sys.exit(1)              # nothing on the drive
try: e=json.load(open(fs[-1]))
except Exception: sys.exit(1)       # present, but empty or corrupt
```

`receive` printed `Newest event: none` for either, and the accompanying advice — check the sender
ran `send`, check `scutil --get ComputerName` — sends you to the **other** Mac, which is the one
place the problem was not. Everything on the sender verified clean: `isUploaded = 1` on all six
files, matching iCloud account, matching root, correct `to:` field.

Fixed in `bin/tandem`: `newest_event` now materializes a dataless event with the same read
`present()` uses, and exits **2** for present-but-unreadable versus **1** for absent. `receive`
carries the code through its poll loop and says which one it hit, with the two commands that show
it. The general rule this is an instance of: **on a synced drive, listing a file proves nothing —
only a read does**, and any code path that treats a failed read as absence will point the user at
the wrong machine.



## 17. There are TWO session stores — and only one of them syncs

Established 2026-09-25, after a day spent on the wrong premise.

```
local-agent-mode-sessions/<account>/<org>/
    local_<uuid>.json + local_<uuid>/     host-loop sessions — run ON this Mac, never sync
    remote-session-spaces.json            a CACHE of folder grants for server-side sessions
```

Counted: Madoka 723 local / 19 remote-cache entries; Ji-su 60 local / 6. The two Macs' remote-cache
files have **zero session ids in common** — and yet the same remote conversation displays on both.

That is the whole point. `remote-session-spaces.json` is **not a session list**. It records only the
folder grants a session was given *on this Mac*, so it is inherently per-machine. The sessions
themselves are server-side, and every Mac signed into the account fetches them.

**Demonstrated.** The session `Ji-su : Quicken Reconciliation - fix lots and cost basis` (remote,
last message 2026-09-05) appears on Ji-su *and* on Madoka. Its figures — Blackstone $188.34,
$640.56, 292.76225381 sh, 0.139 shares, 469.259 — are all present in
`blackstone_lp_basis_edit_2026-09-03.md`, `sarah_ira_differences_VERIFIED_2026-09-02.md` and
`bgig_zero_basis_lots_2026-08-31.md` in the shared folder. It wrote those files.

**The consequence is large: to move a workload's conversation between Macs, run it as a remote
session.** No tooling, no copying, nothing to build. Host-loop sessions are the ones that strand —
`MS Korea Copilot sales strategy` sat on Madoka with `hostLoopMode: true` and could never have
travelled. This retires the idea of mirroring the session store (3.3 GB on Madoka, 1.1 GB of it hot
append-only `audit.jsonl`), which was being seriously considered the same day.

`tandem` still earns its place — remote sessions do no file transfer, no md5 verification and no
ownership record. But its *rationale* is narrower than the docs claimed.

**How this was got wrong, three times in one day.** Each time, one store was checked, nothing was
found, and "nothing found" was reported as "nothing exists":

| Reported | Actually |
|---|---|
| `Newest event: none` | the event was there, dataless (finding 16) |
| `the files did not all arrive` | they arrived Aug 19; 2 of 19 were edited after |
| `0 Cowork sessions, ever` | 3 remote sessions — only `local_*.json` had been globbed |

Finding 7's lesson was "find the file that stores it before concluding it is impossible." The
sharper version: **find every file that stores it.** An absence is only evidence once you know you
searched the whole space — and a tool that reports absence should say which store it looked in.



## 18. A stalled iCloud Drive on the RECEIVING Mac looks exactly like a missing handoff

2026-10-30. Madoka sent Adobe Stock Plan to Ji-su; `send` verified every file `isUploaded = 1`.
Ji-su's `receive` waited 600 s and reported the newest event as Madoka's Aug 21 claim — so the
event was not dataless (finding 16), it was absent. The cause was Ji-su itself:

```
brctl status   client:needs-sync   sync:needs-sync-down|in-sync-down   last-sync:2026-10-29 15:57
```

Ten hours without a sync-down, beginning around a reboot, and not one file newer than the previous
day anywhere in the shared tree. Opening Finder › iCloud Drive restarted it within a minute
(`client:idle`, `has-synced-down`), the event arrived, and `receive` claimed the project.

The timeout's advice — check that the sender ran `send` — pointed at the one Mac that had done
everything right, the same misdirection finding 16 fixed for a dataless event. `receive` now
checks this Mac's drive after a minute of waiting and again at timeout: a client that is not
`idle` and has not synced down for 10 minutes is reported as stalled, with the Finder fix, and the
timeout names it as the likelier cause. `tandem check` shows the same line.

Two macOS 27 changes found on the way: `MobileMeAccounts` is now an empty plist, so the iCloud
account comes from `~/Library/Accounts/Accounts4.sqlite` instead; and `ji-su.local` intermittently
resolved to `127.0.0.1`, so ssh reached Madoka itself and correctly refused it as a changed host
key. Connecting by IP with `-o HostKeyAlias=ji-su.local` checks the right key either way.


## 19. A running profile can carry its own Dock icon — through a clone, not an edit

Every profile runs the one signed `/Applications/Claude.app`, so in the Dock and ⌘-Tab two open
profiles are identical. Editing the bundle's icon would break its signature, its updates and its
Keychain access. Measured 2026-10-31 on Claude 4.29.0, macOS 27:

| Step | Result |
|---|---|
| `cp -Rc Claude.app` (APFS clone), 615 MB | 0.16 s, **no disk used** |
| `codesign --verify` on the clone | valid |
| custom icon set as Finder's paste-icon does (`NSWorkspace setIcon:forFile:`) | adds `Icon\r` and Finder info at the bundle root |
| `codesign --verify` after that | **valid**; only `--strict` objects ("Finder information… not allowed") |
| `spctl -a -vv` | **accepted**, `source=Notarized Developer ID` |
| launched with `--user-data-dir` | the **Dock shows the badged icon** while it runs |
| `claude://` handler, before / after the clone registers | `/Applications/Claude.app` both times — LaunchServices prefers it |

Two details mattered. A custom icon is drawn as-is — macOS does not mask it as it masks an app's
own `.icns` — so the clone's icon is pre-rounded on Apple's grid (824 px body, 185 px corner). And
every "is Claude running" check matches argv[0] `…/Claude.app/Contents/MacOS/Claude`, split on
whitespace; naming each clone `Claude.app` under `~/.config/claude-tandem/runtimes/<id>/` — a path
with no spaces — made all of them see it with no code change. Confirmed with the clone running:
`tandem --profile <p>` refused to edit its `spaces.json`, and `tandem profile quit` found and quit it.

**Confirmed with a real second account, 2026-10-31.** Profile `Junipera` — desktop signed in to a
second Claude account, Claude Code to a Team account — opened through its clone with **no Keychain
prompt** for *Claude Safe Storage* (the key Electron encrypts login cookies with) and stayed signed
in: the clone carries Claude.app's exact signature, so the Keychain item's access rule accepts it.
The same run confirmed what the profiles design rested on: each profile's Claude Code login is its
own (`claude auth status` showed `agilecto@gmail.com` · Max for default and `al@junipera.io` · Team
for Junipera, both signed in at once), and `claude://` still opened `/Applications/Claude.app` with
the clone running. `--dock-icon` stays opt-in only because it is a choice, not a risk.

---

## Two commands that caused damage during development

Both were recovered in full, but neither should be repeated.

**`brctl evict <path>`** executes immediately and takes no confirmation. It was run inside a loop
probing which `brctl` subcommands exist, and evicted the entire iCloud Drive. `brctl --help` lists
only `diagnose` and `log`, but the other verbs exist and *run*.

**`find … -name '* 2*' -delete`** to clean conflict copies. That glob matches real filenames
containing a space followed by `2` — it destroyed `GS Vintage VII 2023 Exchanges.qif` on both Macs
(matched on "2023"). Recovered only because a pre-migration backup existed.

Match `* 2.*` and `* 2`, inspect the list, and remove by exact path. `coworkctl conflicts` therefore
only **reports**; it never deletes.
