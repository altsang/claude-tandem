# Command reference

`tandem` is one command with two halves: the handoff verbs, and `tandem profile …` for accounts. Install it with `brew install altsang/tap/claude-tandem`, or run `./bin/tandem` from a clone of the repo. `tandem help` and `tandem profile help` print the same thing in brief.

- [Install and update](#install-and-update)
- [Accounts: `tandem profile`](#accounts-tandem-profile)
- [Handoffs](#handoffs)
- [Acting as a profile: `--profile`](#acting-as-a-profile---profile)
- [Inspecting](#inspecting)
- [Lower-level verbs](#lower-level-verbs)
- [Files Tandem keeps](#files-tandem-keeps)
- [Environment](#environment)

---

## Install and update

| Command | |
|---|---|
| `brew install altsang/tap/claude-tandem` | install `tandem`, with Python and Pillow for drawing badges. The old names `mirror` and `claude-profile` come too |
| `brew upgrade claude-tandem` | update the CLI. The app keeps running the version it was built from until `tandem menubar` rebuilds it, so run that next, on each Mac. Dock launchers keep working |
| `brew uninstall claude-tandem` | remove the CLI. Profiles, their sign-ins, `~/Applications/Claude Tandem.app` and the launchers stay; remove those yourself if you want them gone |
| `tandem version` | the installed version |
| `tandem skill [--print]` | show the `/handoff` skill's `SKILL.md` in Finder, to add in Claude › Settings › Skills; `--print` only prints the path |

The app (menu bar and window) is compiled on your Mac, so `tandem menubar` needs the Command Line Tools (`xcode-select --install`). Xcode isn't needed from 1.1.1; 1.1.0 failed to build without it ([finding 21](findings.md#21-swiftuis-state-needs-xcode-on-macos-27--the-command-line-tools-cant-expand-it)). After the first build, turn on Open at Login in its Settings, so it keeps publishing this Mac's card and hears about handoffs.

Updating both Macs:

```bash
brew upgrade claude-tandem && tandem menubar     # on each Mac
tandem where                                     # each Mac's card shows its Tandem version
```

---

## Accounts: `tandem profile`

Anywhere a profile is named you can use its id or its name. `default` is the Claude you already had.

| Command | Does |
|---|---|
| `tandem profile create ID` | make a profile: its own desktop data and Claude Code config folders, sharing skills, settings, `CLAUDE.md`, plugins, agents and commands with `~/.claude` |
| `tandem profile desktop P` | open that profile's Claude app beside any others; brings it forward if it's open |
| `tandem profile code P [args]` | Claude Code as that profile, passing `args` through (`--resume`, a prompt, …) |
| `tandem profile list [--json]` | each profile's Code account and plan, desktop account, whether it's open, and whether it needs reopening after an update |
| `tandem profile quit P` | quit that profile's app the way ⌘Q does, and wait up to 15 s for it to close |
| `tandem profile repair` | a Dock copy Claude's updater relaunched without its profile, so it shows your default account: quit it and open it again as its profile. The menu-bar app runs this whenever a copy starts |
| `tandem profile adopt P [--dry-run] [--restart] [--never]` | copy in Claude Code sessions this profile's account left in your regular Claude before it had a profile ([details](profiles.md#used-this-account-before-bring-its-history-in)) |
| `tandem profile rename P NEW` | a new name everywhere; the id and folders stay ([why](profiles.md#names-and-ids)) |
| `tandem profile app P [options]` | build its Dock launcher, `~/Applications/Claude (NAME).app` |
| `tandem profile app --all` | rebuild every launcher, e.g. after Claude's icon changes |
| `tandem profile sync [--dry-run]` | copy Claude Code sessions (`projects/`, `plans/`) between all profiles, newest wins |
| `tandem profile doctor` | after a Claude update: check what profiles rely on, flag apps to reopen, stale Dock copies and copies running without their profile, check where `claude://` links go |
| `tandem menubar [--rebuild]` | build `~/Applications/Claude Tandem.app` (menu bar and window) when its sources, the version or the install changed, then open it if it isn't running. `--rebuild` forces the build; `--help` prints usage |

`app` options, all remembered for next time:

| Option | |
|---|---|
| `--badge TEXT` | one or two letters or digits in any script, or one emoji |
| `--badge-image FILE` | an image, cover-cropped to the circle |
| `--badge auto` | back to the name's initial |
| `--color '#RRGGBB'` | the badge colour; by default one is chosen from the id |
| `--dock-icon` · `--no-dock-icon` | show the badge in the Dock while the profile runs, via its own APFS clone of Claude.app ([details](profiles.md#badges-launchers-and-the-dock)) |

For `default`, `--badge` and `--color` are saved for the menu bar only, since default is Claude.app itself.

---

## Handoffs

| Command | Does |
|---|---|
| `tandem send P --to SIDE` | hand project `P` to another Mac (`Ji-su`) or account (`Madoka@work`), and block until every file is uploaded |
| `tandem receive P` | wait for a handoff addressed to this side, verify every file, define the project if needed, merge memory, claim it, and copy the document to the clipboard |
| `tandem receive P --defer` | the same, except that if this side's Claude is open it claims now and leaves defining, memory and unlocking to `settle` (what the app runs) |
| `tandem settle [P]` | finish deferred receives once this side's Claude has quit (the app does this when it notices the quit) |
| `tandem ask P` | ask whoever holds `P` to hand it to this side: their Tandem shows the request |
| `tandem hold P --to SIDE` | lock this side out of a project it handed away |
| `tandem release P` | undo a hold (`receive` does this itself) |
| `tandem memory-install P --merge` | merge the newest memory snapshot into this side's (what `receive` runs) |
| `tandem memory-install P --force` | replace this side's memory with the snapshot. Both modes back up first |
| `tandem memory-snapshot P` | snapshot this side's memory into the shared tree (`send` does this itself) |

`send` flags:

| Flag | Effect |
|---|---|
| `--note "…"` | a line recorded in the ownership log; what `tandem status` shows |
| `--wait` | after the upload, block until the other side claims it |
| `--doc FILE` | ship this document instead of the newest `HANDOFF*.md` |
| `--no-doc` | ship with no document, e.g. for a project's first move |
| `--hold` | also lock this side out ([details](handoffs.md#locking-a-mac-out---hold)) |
| `--force` | send a project the log says this side doesn't hold. Check `tandem log` first |
| `--timeout N` | seconds to wait in all (default 900); also on `receive` |

Setting up:

| Command | Does |
|---|---|
| `tandem deploy` | install or refresh the engine in the shared tree (once; the drive carries it to the other Mac) |
| `tandem use-root PATH` | use a shared drive other than iCloud, for this Mac |
| `tandem migrate P` | copy a local project's folder (whatever it's called, wherever it is) into the shared tree, md5-verified, and switch the project to the copy. A folder Claude made is set aside; one you attached elsewhere stays put. A project with no folder gets an empty one. Claude quit first |
| `tandem rename OLD NEW` | rename a shared project: folder and project together |

---

## Acting as a profile: `--profile`

Every handoff verb acts as `default` unless told otherwise. Put `--profile P` first to act as another account:

```bash
tandem --profile work receive "P"      # receive into the `work` account
tandem --profile work status           # the same projects, from `work`'s side
```

Under `--profile`, Tandem uses that profile's data folder, its project list and memory, and its side name `<Mac>@<id>`. Only that profile's app counts as "Claude is running".

---

## Inspecting

| Command | Shows |
|---|---|
| `tandem where [--json]` | **what is where**: every Mac that publishes a card, each profile on it and its account, every shared project's holder and state, briefs ready to send, requests, receives still settling, and projects defined on only one side |
| `tandem presence` | publish this Mac's card to the shared drive (the app does it every five minutes) |
| `tandem status` | every shared project, who holds it, the last event and note |
| `tandem log P` | a project's ownership history |
| `tandem doctor` | everything at once, changing nothing: `tandem check`, then `tandem profile doctor`. Exits non-zero if the profile half fails. The app's Run Doctor |
| `tandem check` | shared root, iCloud account and sync state, engine, folder links that would fail. Changes nothing |
| `tandem conflicts` | iCloud conflict copies (`name 2.ext`). It reports only; remove them by exact path, never by pattern |
| `tandem path P` | the project's shared path, also copied to the clipboard |
| `tandem project-list` | local projects defined on this side, with their folders |

---

## Lower-level verbs

`send` and `receive` are these, composed, with verification added. They still work on their own:

| Command | |
|---|---|
| `tandem project-export P` | write the project's definition into the shared tree |
| `tandem project-import P [--wait]` | add an exported definition here (Claude quit); `--wait` waits for its files too |
| `tandem project-repath P PATH [--replace OLD]` | point a project at a different folder (Claude quit). With `--replace`, only that one folder is swapped and the project's others are kept |
| `tandem wait P` | watch the drive deliver a project, with progress |
| `tandem materialize [PATH]` | force the drive to download real contents |
| `tandem handoff P --to SIDE` · `tandem pickup [P]` | the engine's raw handoff and claim, without `send`'s checks |

`tandem link` is deprecated: symlinked folders break Claude.

---

## Automation

Everything the app does, the CLI does: the app is a client of the same commands. Run Tandem headless on a Mac without the app, script it, or feed its events into something else.

### The background half: `tandem watch`

```bash
tandem watch                          # poll, publish presence, report events, act on tandem config
tandem watch --once --json            # one pass, one JSON line per event — for cron or CI
tandem watch --no-act --notify        # report only, as macOS notifications
tandem watch --on-event ./hook.sh     # each event's JSON on stdin, TANDEM_EVENT=<event>
tandem watch --install                # run it at login (a LaunchAgent; log in ~/Library/Logs)
```

| Event | When |
|---|---|
| `arrival` | a handoff addressed to a profile on this Mac |
| `brief` | `/handoff` left a send intent for a project a profile here holds |
| `request` | another side asked for a project a profile here holds (`tandem ask`) |
| `delivered` | something this Mac sent was claimed on the other side |
| `received` · `receive-failed` | what watch did about an arrival, with `on-arrival auto` |
| `sent` · `send-failed` | what watch did about a brief, with `on-brief auto` |
| `settled` · `settle-failed` | a deferred receive finished once that profile's Claude quit (always on) |

Each announcement fires once per item, keyed like `tandem inbox`, and only for items under three days old. Seen keys are in `~/.config/claude-tandem/watch-seen.json`.

### Settings: `tandem config`

| Key | Values | |
|---|---|---|
| `on-arrival` | `ask` (default) · `auto` · `off` | what happens when a handoff arrives for a profile here |
| `on-brief` | `ask` (default) · `auto` | what happens when `/handoff` leaves a send intent. `auto` sends only when its `to` names a known side |
| `watch-interval` | seconds, ≥ 10 (default 60) | how often `tandem watch` looks |

The app's Settings › Handoffs edits the same file (`~/.config/claude-tandem/config.json`).

### Running the app and `watch` together

Both read the same inbox and settings. A send, receive or settle takes a per-project lock, so if both react to the same arrival, one does it. The other exits **75** (EX_TEMPFAIL, "already in progress") and treats that as handled. Each still announces in its own way: the app with notifications, `watch` with its output and hooks.

### JSON

`tandem where --json`, `tandem inbox --json`, `tandem config --json` and `tandem profile list --json` are the interface the app itself reads.

- They carry `"schema": 1`. Fields may be added without a bump; a removal or change of meaning bumps it.
- Timestamps are ISO 8601 UTC. On disk, ownership events keep their compact `20261101T172643Z` names.

| `where --json` field | |
|---|---|
| `me`, `root` | this Mac, the shared root |
| `machines[]` | `mac`, `this`, `silent` (no card), `age_minutes`, `version`, `drive` {`state`, `last_sync`, `minutes`, `stalled`}, `sides[]` {`side`, `profile`, `name`, `email`, `plan`, `open`, `color`, `projects[]`, `held[]` (this Mac only)} |
| `projects[]` | `name`, `holder`, `state` (`held` · `sent` · `unrecorded` · `unreadable`), `last` {`verb`, `machine`, `to`, `at`, `note`, `doc`}, `history[]`, `doc` {`name`, `modified`, `stale`}, `intents[]`, `requests[]`, `settling[]` |
| `unshared[]` | projects defined on one side only: `project`, `side`, `mac` |
| `inbox[]` | `kind` (`arrival` · `brief` · `request` · `settling` · `delivered`), `key`, `project`, `side`, `profile`, `profile_name`, `profile_open`, `other`, `note`, `at`, plus `doc` and `to` (a brief's resolved destination, or null) |

**Progress.** With `TANDEM_STEPS=1`, `send` and `receive` print `::step::NAME::STATE::DETAIL` lines:

- `NAME`: `brief`, `prepare`, `event`, `upload`, `files`, `define`, `claim`, `memory`, `unlock`, `deliver`
- `STATE`: `start`, `done`, `wait`, `skip`, `fail`

`wait` on `define`, `memory` or `unlock` means the step was deferred until that profile's Claude quits.

**Exit codes.** `0` success · `1` failure, with the reason on stderr after `error:` · `3` `settle` is still waiting for Claude to quit · `75` already in progress elsewhere.

### The app and the CLI, side by side

| In the app | The command |
|---|---|
| A profile (menu bar or its page): Open / Show Claude · Open Claude Code · Quit · Quit and Reopen | `tandem profile desktop P` · `tandem profile code P` · `tandem profile quit P` |
| New Profile (the **+** in the toolbar) | `tandem profile create P` then `tandem profile app P --color …` |
| Name · Badge · colour · Dock | `tandem profile rename` · `tandem profile app P --badge/--badge-image/--color/--dock-icon` |
| Bring In Earlier Sessions | `tandem profile adopt P` |
| Handoffs › Waiting for you | `tandem inbox` |
| Receive | `tandem [--profile P] receive "X" --defer` |
| Send… | `tandem [--profile P] send "X" --to SIDE --note … [--hold]` |
| Not Now | `tandem inbox dismiss KEY` |
| Quit Claude and Finish · Finish Now | `tandem profile quit P` then `tandem [--profile P] settle` |
| Ask for It · Handoffs › Ask for a Project | `tandem [--profile P] ask "X"` |
| Open in Claude | `tandem [--profile P] brief "X" --open` |
| History… | `tandem log "X"` |
| Unlock | `tandem [--profile P] release "X"` |
| Move to the Shared Drive | `tandem [--profile P] migrate "X"` |
| Inbox · Projects (the grid) · the Macs page | `tandem where` |
| Check Now (↻ in the toolbar, Handoffs › Check Now ⌘R) | `tandem where` |
| (every few minutes, while it runs) | `tandem presence` |
| Settings (⌘,) › Handoffs | `tandem config set on-arrival …` · `tandem config set on-brief …` |
| Settings › Maintenance: Run Doctor · Sync Claude Code sessions · Find conflict copies · Update the shared engine | `tandem doctor` · `tandem profile sync` · `tandem conflicts` · `tandem deploy` |
| Notifications, and acting automatically, while it runs | `tandem watch [--notify]` |
| Open Claude Tandem at login | `tandem watch --install`, the headless equivalent |

Only the app has the terminal choice for Claude Code (Terminal or Ghostty) and the Get Started checklist (`tandem doctor` covers what it checks). Only the CLI has the lower-level verbs below and `use-root`.

---

## Files Tandem keeps

**On the shared drive** (iCloud by default: `~/Library/Mobile Documents/com~apple~CloudDocs/Claude/`):

```
Projects/P/                              the project's files: the folder the project reads
Projects/P/HANDOFF_topic.md              the brief, written by /handoff
Projects/P/.handoff/events/              append-only ownership log: {time}-{side}-{verb}.json
Projects/P/.handoff/memory/TIME-SIDE/    memory snapshots, md5-manifested
Projects/P/.handoff/intents/TOPIC.json   "send this to …", left by /handoff for the app; the next event consumes it
Projects/P/.handoff/requests/TIME-SIDE.json   "hand it to me", from `tandem ask`; the next event consumes it
_handoff/presence/MAC/TIME.json          each Mac's card: profiles, accounts, projects, Tandem version, iCloud state
_handoff/bin/coworkctl-vN.sh             the engine: versioned, never edited in place (bin/VERSIONING.md)
_handoff/projects/P.TIME.json            exported definitions, one per send
_handoff/projects/P.TIME.manifest.json   sizes and md5s: what receive verifies against
```

**On each Mac:**

```
~/.config/claude-tandem/root             a shared-root override, if set (use-root)
~/.config/claude-tandem/held[-ID]/       folder links stashed by --hold, per profile
~/.config/claude-tandem/settle/          receives waiting for a profile's Claude to quit (receive --defer)
~/.config/claude-tandem/config.json      tandem config: shared by the app and tandem watch
~/.config/claude-tandem/dismissed.json   inbox items dismissed (tandem inbox dismiss, Not Now)
~/.config/claude-tandem/locks/           one send / receive / settle per project at a time
~/.config/claude-tandem/watch-seen.json  what tandem watch has already announced
~/.config/claude-tandem/checked-version  the Claude version doctor last passed
~/.config/claude-tandem/runtimes/ID/     a profile's Dock copy of Claude.app (--dock-icon)
~/.claude-ID/                            a profile's Claude Code config and sign-in
   .profile-name · .profile-badge · .profile-badge.png · .profile-color · .profile-dock-icon · .profile-adopt-declined
~/Library/Application Support/Claude-ID/ a profile's desktop data
~/Applications/Claude (NAME).app         a profile's Dock launcher
~/Applications/Claude Tandem.app         the app: menu bar and window
```

**Where Tandem itself lives:** the repo, or with Homebrew `$(brew --prefix)/opt/claude-tandem/libexec/`, which holds the same `bin/`, `macos/` and `skills/` below plus `VERSION`. The app and the Dock launchers record the `opt/` path, which stays put across `brew upgrade`.

**In this repo:**

```
bin/tandem                the CLI: handoffs, plus `profile …` and `menubar` routed to tandem-profile
bin/tandem-profile        the accounts half
bin/tandem-ledger.py      what is where (`where`, `inbox`, `presence`) and `watch`
bin/coworkctl-vN.sh       the engine, copied into the shared tree by `tandem deploy`
bin/mirror, bin/claude-profile   the names before Claude Tandem: forward, and say so
macos/ClaudeTandem/       the app, built by `tandem menubar`: main.swift (menu bar, main menu, Settings window), Window.swift (profiles, settings tabs), Handoffs.swift (handoffs, Macs, notifications)
skills/handoff/           the /handoff skill
VERSION                   the release, printed by `tandem version`
docs/                     these guides, and findings.md
```

Keep the repo **outside** the shared drive. A `.git` folder in a synced folder is the same two-writer problem that produces conflict copies.

---

## Environment

| Variable | |
|---|---|
| `TANDEM_PROFILE` | act as this profile, like `--profile` |
| `TANDEM_ROOT` | use this shared root for this run, ahead of `use-root` |
| `TANDEM_STEPS` | `send` and `receive` also print `::step::NAME::STATE::DETAIL` lines (the app sets it to show progress) |
| `TANDEM_NO_CLIPBOARD` | `receive` leaves the clipboard alone |
| `MIRROR_PROFILE`, `MIRROR_ROOT` | the same, under the names from before the rename; still honoured |

`tandem` also sets `TANDEM_ME` and `MIRROR_ME`, the side's name, plus `MIRROR_ROOT` for the engine it runs, so older engines on the drive keep working.
