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
| `brew upgrade claude-tandem` | update. The menu-bar app and Dock launchers keep working; `tandem menubar` rebuilds the app for the new version |
| `brew uninstall claude-tandem` | remove the CLI. Profiles, their sign-ins, `~/Applications/Claude Tandem.app` and the launchers stay; remove those yourself if you want them gone |
| `tandem version` | the installed version |
| `tandem skill [--print]` | show the `/handoff` skill's `SKILL.md` in Finder, to add in Claude › Settings › Skills; `--print` only prints the path |

The menu-bar app is compiled on your Mac, so `tandem menubar` needs the Command Line Tools (`xcode-select --install`).

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
| `tandem profile adopt P [--dry-run] [--restart] [--never]` | copy in Claude Code sessions this profile's account left in your regular Claude before it had a profile ([details](profiles.md#used-this-account-before-bring-its-history-in)) |
| `tandem profile rename P NEW` | a new name everywhere; the id and folders stay ([why](profiles.md#names-and-ids)) |
| `tandem profile app P [options]` | build its Dock launcher, `~/Applications/Claude (NAME).app` |
| `tandem profile app --all` | rebuild every launcher, e.g. after Claude's icon changes |
| `tandem profile sync [--dry-run]` | copy Claude Code sessions (`projects/`, `plans/`) between all profiles, newest wins |
| `tandem profile doctor` | after a Claude update: check what profiles rely on, flag apps to reopen and stale Dock copies, check where `claude://` links go |
| `tandem menubar [--rebuild]` | build and open the Claude Tandem menu-bar app. Rebuilds itself when its source changes, the version changes or the install moves |

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
| `tandem migrate P` | move a local project's folder into the shared tree, md5-verified, keeping the original aside |
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
| `tandem status` | every shared project, who holds it, the last event and note |
| `tandem log P` | a project's ownership history |
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
| `tandem project-repath P PATH` | point a project at a different folder (Claude quit) |
| `tandem wait P` | watch the drive deliver a project, with progress |
| `tandem materialize [PATH]` | force the drive to download real contents |
| `tandem handoff P --to SIDE` · `tandem pickup [P]` | the engine's raw handoff and claim, without `send`'s checks |

`tandem link` is deprecated: symlinked folders break Cowork.

---

## Files Tandem keeps

**On the shared drive** (iCloud by default: `~/Library/Mobile Documents/com~apple~CloudDocs/Claude/`):

```
Projects/P/                              the project's files: the folder the project reads
Projects/P/HANDOFF_topic.md              the brief, written by /handoff
Projects/P/.handoff/events/              append-only ownership log: {time}-{side}-{verb}.json
Projects/P/.handoff/memory/TIME-SIDE/    memory snapshots, md5-manifested
_handoff/bin/coworkctl-vN.sh             the engine: versioned, never edited in place (bin/VERSIONING.md)
_handoff/projects/P.TIME.json            exported definitions, one per send
_handoff/projects/P.TIME.manifest.json   sizes and md5s: what receive verifies against
```

**On each Mac:**

```
~/.config/claude-tandem/root             a shared-root override, if set (use-root)
~/.config/claude-tandem/held[-ID]/       folder links stashed by --hold, per profile
~/.config/claude-tandem/checked-version  the Claude version doctor last passed
~/.config/claude-tandem/runtimes/ID/     a profile's Dock copy of Claude.app (--dock-icon)
~/.claude-ID/                            a profile's Claude Code config and sign-in
   .profile-name · .profile-badge · .profile-badge.png · .profile-color · .profile-dock-icon · .profile-adopt-declined
~/Library/Application Support/Claude-ID/ a profile's desktop data
~/Applications/Claude (NAME).app         a profile's Dock launcher
~/Applications/Claude Tandem.app         the menu-bar app
```

**Where Tandem itself lives:** the repo, or with Homebrew `$(brew --prefix)/opt/claude-tandem/libexec/`, which holds the same `bin/`, `macos/` and `skills/` below plus `VERSION`. The menu-bar app and the Dock launchers record the `opt/` path, which stays put across `brew upgrade`.

**In this repo:**

```
bin/tandem                the CLI: handoffs, plus `profile …` and `menubar` routed to tandem-profile
bin/tandem-profile        the accounts half
bin/coworkctl-vN.sh       the engine, copied into the shared tree by `tandem deploy`
bin/mirror, bin/claude-profile   the names before Claude Tandem: forward, and say so
macos/ClaudeTandem/       the menu-bar app: one Swift file, built by `tandem menubar`
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
| `MIRROR_PROFILE`, `MIRROR_ROOT` | the same, under the names from before the rename; still honoured |

`tandem` also sets `TANDEM_ME` and `MIRROR_ME`, the side's name, plus `MIRROR_ROOT` for the engine it runs, so older engines on the drive keep working.
