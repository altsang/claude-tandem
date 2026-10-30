# HANDOFF — multi-account Claude profiles + same-Mac handoffs (branch `profiles`)

> **Since renamed:** the project is now Claude Tandem. `mirror` → `tandem`, `claude-profile` → `tandem profile`, and the repo is `~/workspace/claude-tandem` (`altsang/claude-tandem`). Commands below are updated; the old ones still work as shims.

Paste this whole document as your first message in a Claude Code session opened in
`~/workspace/claude-tandem`. It is self-contained. Written 2026-10-29 on Madoka.

## Your task

Al has two Claude subscriptions and one of them sits idle because only one account can be signed
in at a time. The goal: run both accounts side by side on one Mac (like the paid "Claude Switch"
app at claudeswitch.dev), and let `tandem` hand a Cowork project from one account to the other
when the first hits its usage limit.

The code is written and partly tested (see Status). What remains:

1. Commit the `profiles` branch here, and the one-file change in `~/.dotfiles` — **only when Al
   says so**; nothing is committed yet.
2. Do the first real run with a second account (steps in "Remaining" below).
3. Answer the two open questions about the desktop app (deep-link sign-in with two instances, and
   update behaviour), ideally with a full `rea` analysis.
4. `tandem deploy` to publish engine v8 to the iCloud shared tree — **ask first**; it writes to the
   shared tree and reaches Ji-su.

## Before you start — check you actually have access

- `git -C ~/workspace/claude-tandem branch --show-current` prints `profiles`, and
  `git status -s` shows: `M README.md`, `M bin/tandem`, `M skills/handoff/SKILL.md`,
  `?? bin/tandem-profile`, `?? bin/coworkctl-v8.sh` (plus this file). If the branch or files are
  missing, the work did not travel — stop; it exists only on Madoka, uncommitted.
- `git -C ~/.dotfiles status -s` shows `M claude/.claude/claude-session.zsh` (the `claude @<p>`
  hook). Same rule.
- `/Applications/Claude.app` exists. `./bin/tandem profile doctor` exits 0. If it reports ✗, the
  desktop app changed underneath the design — stop and read "Background" before changing code.
- Python 3 with Pillow (icons only). Node ≥ 24.22.1 for `npx rea-agents` (Madoka has 24.1.0; rea
  printed engine warnings but `--help` ran).

## Background — what's wrong and why

**What Claude Switch actually is.** claudeswitch.dev = SaschaHeyer/claude-switch. Its CLI (MIT,
one bash script) gives each account `~/.claude-<name>/` and launches `claude` with
`CLAUDE_CONFIG_DIR`; it symlinks `skills CLAUDE.md settings.json plugins` from `~/.claude`;
`sync` = `rsync -a --update` of `projects/` and `plans/` so `/resume` works on another account.
The $4.99 Mac app (closed source) opens the real Claude Desktop with a per-profile data folder
`~/Library/Application Support/Claude-<Name>`. **It does not mention Cowork at all.**
Dead end: Symbioose/claude-account-switcher ("Claude Switcher") is a different app — it swaps one
global Keychain slot, one account at a time, CLI only. Al confirmed that is not the one.

**What the Claude desktop app (4.29.0) does** — found by grepping
`/Applications/Claude.app/Contents/Resources/app.asar`, NOT by rea (see Gotchas):

- `CLAUDE_USER_DATA_DIR` is **ignored by signed builds** — the app logs
  "CLAUDE_USER_DATA_DIR is set and signed builds ignore it". Do not use it.
- It checks `app.commandLine.hasSwitch("user-data-dir")`: the Chromium `--user-data-dir` switch
  works, and `requestSingleInstanceLock` is per data folder, so two instances run side by side.
  Launch: `open -n -a Claude --env CLAUDE_CONFIG_DIR=… --args --user-data-dir=…`.
- `CLAUDE_CONFIG_DIR` is honoured by the embedded Claude Code (Code tab).
- Cowork store: `<userData>/local-agent-mode-sessions/<account>/<org>/spaces.json` (+ `spaces/<id>/memory/`).
- `<userData>/config.json` key `lastKnownAccountUuid` = the signed-in account.
- The updater's running-instance sentinel (`updaterRunningInstance`) lives in each data folder's
  config.json → each profile's app updates independently, all against the ONE /Applications/Claude.app.

**A pre-existing mirror bug this fixes.** `spaces_file()` used to return the first
`local-agent-mode-sessions/*/*/spaces.json`. Madoka's default data folder already holds two
accounts: `c9390ef8-…` (signed in; org `890ac620-…`; has the only spaces.json, 12 local projects)
and `d37cdc9d-…` (orgs `38d7d753-…` and `890ac620-…`; no spaces.json). It was right only by luck.

**Design.** A profile `p` = `~/.claude-p` (Code) + `Application Support/Claude-p` (desktop),
matching Claude Switch's layout so profiles interoperate. "default" = `~/.claude` + `Claude`.
In mirror, a profile is its own side of a handoff named `<Mac>@<p>` (e.g. `Madoka@b`) — `@`, not
`:`, because the engine puts the machine name in event filenames (`{ts}-{machine}-{verb}.json`)
on iCloud. So same-Mac account handoff reuses send/receive unchanged:
`tandem send X --to Madoka@b`, then `tandem --profile b receive X`.

## Status

**Done and verified on Madoka:**

| What | Evidence |
|---|---|
| `bin/tandem-profile` (290 lines): create, desktop, app, code, list, sync, doctor | `bash -n` clean; throwaway profile `zztest` created → launcher built → listed → `sync --dry-run` → removed |
| `tandem --profile` / `TANDEM_PROFILE`; `ME=<Mac>@<p>`; `HOLDDIR` per profile; account-aware `spaces_file`; per-profile `claude_running` (6 old `pgrep` sites replaced) | `tandem check` on default shows `c9390ef8…/890ac620…/spaces.json`; `--profile b check` shows `Madoka@b`, data `Claude-b`; `status`, `project-list` (12), `check` exit 0 unchanged |
| Engine `coworkctl-v8.sh` = v7 + `ME="${TANDEM_ME:-$(scutil --get ComputerName)}"` | Throwaway `TANDEM_ROOT`: handoff `Madoka`→`Madoka@b`, pickup as `Madoka@b`, status `owner: Madoka@b` |
| `claude @<p>` in `~/.dotfiles/claude/.claude/claude-session.zsh` (before the provider check, so `claude @b openrouter` composes) | `zsh -n` clean; not run against a real second login |
| Icons: Claude's icon cropped full-bleed + coloured badge with initial; colour remembered in `~/.claude-p/.profile-color` | Rendered through `NSWorkspace.icon(forFile:)` — shows the badge, system-masked, no grey plate |
| `doctor`: re-checks the 4 bundle facts; `desktop` auto-runs it when the version differs from `~/.config/claude-tandem/checked-version` | Passes on 4.29.0 |
| `list` flags a running profile older than the installed bundle (`QUIT+REOPEN`) | Logic only — no update happened during testing |
| README "Two accounts on one Mac (profiles)" section; handoff SKILL.md "Same Mac, other account" | — |

**Remaining:**

| # | Step | Notes |
|---|---|---|
| 1 | `./bin/tandem profile create b`, then `claude @b` and `./bin/tandem profile desktop b`; sign in **from a private browser window** | First real two-account run. Confirm `tandem profile list` shows two different emails |
| 2 | Verify Keychain isolation: `claude auth status` (default) still shows agilecto@gmail.com (max) after b signs in | Claude Switch claims per-config-dir Keychain items; not observed here yet |
| 3 | Desktop sign-in with two instances running: does the `claude://` callback reach the right one? | **Open question.** If it lands in default, sign b in while default is quit |
| 4 | Cowork in profile b: open once (creates its spaces.json), check disk use of a second VM | Unknown size |
| 5 | Real same-Mac handoff of a small project: `/handoff`, `tandem send P --to Madoka@b --wait`, quit b, `tandem --profile b receive P` | Install the `/handoff` skill in account b first (skills sync per account) |
| 6 | `tandem deploy` (ask Al) — publishes v8; Ji-su picks it up; without `TANDEM_ME` it behaves exactly like v7 | |
| 7 | Commit both repos (ask Al) | |
| 8 | Optional: full rea run for questions 3 and update behaviour | See Gotchas for how it failed |

## Gotchas

Silent ones first.

- **`set -o pipefail` + an awk that `exit`s early = false negative.** `ps | awk '{...; exit}'`
  SIGPIPEs `ps`, the pipeline fails, and "Claude is running" reads as not running — which would
  let mirror edit spaces.json under a live app. Both `claude_running` (mirror) and `desktop_pid`
  (tandem profile) deliberately read all of `ps`. Do not "optimise" the exit back in.
- **Setting `CLAUDE_CONFIG_DIR=~/.claude` explicitly is NOT the same as unset** — Claude Code then
  looks for a differently named Keychain item and reports "not signed in". Default profile must
  run with it unset (`cmd_list`, `cmd_code` handle this).
- **`source <(…)` silently does nothing in macOS bash 3.2** — cost two false test failures. Extract
  to a file and `.` it.
- **Empty arrays under `set -u` in bash 3.2** abort: use `${arr[@]+"${arr[@]}"}` (fixed in `sync`).
- **osacompile applets ship `Assets.car` + `CFBundleIconName`, which override `applet.icns`.**
  `cmd_app` deletes both and re-signs ad hoc. And macOS 26+ puts a non-full-bleed `.icns` on a grey
  plate — hence the crop-to-tile step.
- **A running profile's Dock/⌘-Tab icon is always Claude's.** Only the launcher carries the badge.
  Changing Claude.app's bundle would break its signature and updates — don't.
- **`3p` is reserved:** Claude itself uses `Application Support/Claude-3p`.
- **`npx rea` is the wrong package** (an old connect.router wrapper). The tool is `rea-agents`
  (binary `rea`). `analyze-javascript-application` on app.asar first fails
  `artifact_integrity_mismatch` (signing rewrites `claude-native-binding.node` — expected; pass
  `--integrity-policy record-and-continue`), then ran >10 min and was killed with no output.
  Next time: background it, restrict with `--source-path`, and upgrade Node first.
  `~/workspace/rea/evidence/` is empty; `~/workspace/rea/PLAN.md` build steps still show the
  disproved `CLAUDE_USER_DATA_DIR` launch — the README here is authoritative.
- **Engine versioning rule:** never edit a shipped `coworkctl-vN.sh`; v8 is a new file for that
  reason (iCloud pins cached copies of modified files).
- **Raw engine `handoff` does not check ownership;** the owner check lives in `tandem send`. Not a
  regression, but don't test ownership via the engine directly.
