# Profiles — several Claude accounts on one Mac

The Claude desktop app and Claude Code each hold one signed-in account at a time. A **profile** gives each additional account its own place to live, so all of them can be open at once — the desktop app and Claude Code both — while Claude.app itself stays exactly as Anthropic shipped it.

- [What a profile is](#what-a-profile-is)
- [Create one and sign in](#create-one-and-sign-in)
- [Used this account before? Bring its history in](#used-this-account-before-bring-its-history-in)
- [Every day](#every-day)
- [Names and ids](#names-and-ids)
- [Badges, launchers and the Dock](#badges-launchers-and-the-dock)
- [Moving work to another account](#moving-work-to-another-account)
- [Claude Code sessions across accounts](#claude-code-sessions-across-accounts)
- [When Claude updates](#when-claude-updates)
- [Removing a profile](#removing-a-profile)
- [How it works](#how-it-works)

---

## What a profile is

An **id** and two folders. `default` is the Claude you already have:

| | `default` | profile `work` |
|---|---|---|
| Desktop app data — sign-in, Cowork projects, project memory | `~/Library/Application Support/Claude` | `~/Library/Application Support/Claude-work` |
| Claude Code config and sign-in | `~/.claude` | `~/.claude-work` |
| Skills, `settings.json`, `CLAUDE.md`, plugins, agents, commands | the real files | links to `~/.claude`'s — change once, every account sees it |
| Handoff identity | `Madoka` | `Madoka@work` |

The layout matches [Claude Switch](https://claudeswitch.dev)'s, so a profile made by either tool works in both.

---

## Create one and sign in

```bash
./bin/tandem profile create work
```

Then sign in **once on each surface** — the desktop app and Claude Code keep separate logins:

```bash
./bin/tandem profile desktop work      # a second Claude window: sign in
./bin/tandem profile code work         # Claude Code as `work`: sign in
```

**Sign in from a private browser window.** When the sign-in page opens, claude.ai otherwise signs the new profile straight into whichever account your browser is already using — and you end up with two profiles on one account.

Check it took — each row should show a different account:

```bash
./bin/tandem profile list
PROFILE          CODE (terminal)                    DESKTOP                            OPEN
default          you@personal.com (max)             account c9390ef8                   yes
work             you@company.com (team)             account d37cdc9d                   yes
```

Your default sign-in is untouched by any of this: each profile's Claude Code login is its own Keychain item, confirmed with two real accounts signed in at once.

---

## Used this account before? Bring its history in

If you signed this account into your **regular** Claude before giving it a profile, its work is still there. The new profile is a fresh folder, so it starts empty, and it looks as if your sessions vanished. They haven't.

**From the menu bar it's a setup step.** After *New Profile… → Open Claude* and you sign in, Claude Tandem checks whether your regular Claude holds anything from that account, and asks:

> *Bring Junipera's earlier work in?* Junipera is signed in as you@company.com. Before it had its own profile, this account was used in your regular Claude app, which still has 4 Claude Code sessions from it: AI Video Editing Kit for Chloe, … · **Copy Them** · **Not Now** · **Never for This Profile**

For a profile you already have, the menu marks it *"4 earlier sessions to bring in"* and offers **Bring In Earlier Sessions…** in its submenu. `tandem profile list` points it out too. From the terminal:

```bash
./bin/tandem profile adopt work --dry-run      # what it would bring in
./bin/tandem profile adopt work --restart      # copy it, closing and reopening `work` if it's open
./bin/tandem profile adopt work --never        # stop offering (adopt still works if you ask)
```

It **copies, never moves**: each Claude Code session's record and its full conversation, checked byte for byte, and only what the profile doesn't already have. Your regular Claude keeps its originals. The profile's app has to be closed while it copies, because a running app rewrites its own session list from memory.

**Not yet:** Cowork projects and sessions the account left behind. `adopt` lists them but doesn't move them, because their files record absolute paths into the regular app's folder and moving them needs path rewriting that hasn't been proven yet.

---

## Every day

| To | Run, or use |
|---|---|
| Open an account's desktop app | its Dock launcher · the menu bar · `tandem profile desktop work` |
| Claude Code as an account | `claude @work` (zsh hook below) · `tandem profile code work` |
| See every account, and which are open | the menu bar · `tandem profile list` |
| Quit one account's app, leaving the others | the menu bar · `tandem profile quit work` |

`quit` sends that one window's app the same quit event as ⌘Q, so it saves its state. Quitting "Claude" by name — from a script, say — would hit whichever instance macOS picks.

**`claude @work`.** Add to `~/.zshrc`:

```zsh
claude() {
  if [[ ${1:-} == @?* ]]; then local p=${1#@}; shift
    ~/workspace/claude-tandem/bin/tandem profile code "$p" "$@"
  else command claude "$@"; fi
}
```

It takes the profile's id or its name, and anything after it goes to Claude Code: `claude @work --resume`.

---

## Names and ids

A profile's **id** is the suffix in its folder names, chosen at `create`, and it never changes. Its **name** is what you see and type, and you can change it any time:

```bash
./bin/tandem profile rename work Junipera
```

Afterwards `Junipera` works everywhere — launcher, list, menu bar, `claude @Junipera`, `tandem --profile Junipera` — and so does `work`. The folders stay put because three things are tied to their paths:

- **The Claude Code sign-in.** Its Keychain item is named after a hash of the config folder's path, so moving `~/.claude-work` would sign that account out.
- **Cowork sessions,** which record absolute paths into the data folder.
- **Handoff ownership,** recorded on the shared drive as `Madoka@work`. Renaming that would orphan every project the account holds.

Names are resolved on the Mac where you set them. To address a profile on your *other* Mac — `--to Ji-su@work` — use its id.

Reserved: `default`, and `3p`, which Claude itself uses for `Application Support/Claude-3p`.

---

## Badges, launchers and the Dock

```bash
./bin/tandem profile app work                          # "Claude (work)" in ~/Applications — drag it to the Dock
./bin/tandem profile app work --badge W                # one or two letters, in any script: --badge 지
./bin/tandem profile app work --badge 💼               # one emoji
./bin/tandem profile app work --badge-image logo.png   # an image, cropped to the circle
./bin/tandem profile app work --color '#0E9AA7'        # the badge colour
./bin/tandem profile app work --badge auto             # back to the name's initial
./bin/tandem profile app --all                         # rebuild every launcher, e.g. after Claude's icon changes
```

The launcher is Claude's own current icon with the badge in the corner. Badge and colour are remembered, so rebuilding keeps them. `default` is Claude.app itself and has no launcher, but it can still have a badge and colour for the menu bar.

**A badged icon while it runs.** Normally every running profile shows Claude's own Dock and ⌘-Tab icon, because they all run the one Claude.app. Turn this on and the profile shows its badge while it's open:

```bash
./bin/tandem profile app work --dock-icon        # or: menu bar › work › Show Badge in the Dock
./bin/tandem profile app work --no-dock-icon     # off again
```

It takes effect the next time the profile opens. The profile then runs from its own copy of Claude.app in `~/.config/claude-tandem/runtimes/work/`. The copy is an **APFS clone**: no extra disk, made in a fraction of a second. It carries a custom icon set the same way Finder's *Get Info › paste icon* does. Checked before it was offered ([finding 19](findings.md)):

- the copy stays validly signed and Gatekeeper accepts it
- a signed-in profile opens through it with no Keychain prompt and stays signed in
- `claude://` sign-in links still go to `/Applications/Claude.app`
- every "is Claude running?" safety check sees it

When Claude updates, the copy is remade the next time the profile opens.

---

## Moving work to another account

When one account is close to its usage limit, hand the project to another. It's the same handoff that moves a project between Macs, with the other account as the target:

```bash
/handoff                                                 # in the Cowork session, on account A
./bin/tandem send "My Project" --to Madoka@work          # Madoka is this Mac's name
./bin/tandem --profile work receive "My Project"         # then ⌘V into a session on `work`
```

- **Hand off at the warning, not the wall.** `/handoff` runs inside the session and needs usage to do it. Once the account is at its limit, it can't write the document.
- **Only the receiving account's app needs to be closed,** and only when the project is new to that account. `receive` adds it to that account's project list, which the app would otherwise overwrite from memory. Account A can stay open.
- **The `/handoff` skill installs per account,** since skills sync by account. Add it in every account you hand work *from*.
- **Memory comes across and merges** into whatever the receiving account already knows on that project.

The full mechanics are in the [handoffs guide](handoffs.md).

---

## Claude Code sessions across accounts

Claude Code keeps sessions as plain files under each config folder. To pick up a terminal session on another account:

```bash
./bin/tandem profile sync --dry-run     # what would be copied
./bin/tandem profile sync               # copy projects/ and plans/ between all profiles, newest wins
claude @work --resume                   # the session started on default is there
```

Never continue the *same* session in two profiles at once. The copies diverge, and the next sync keeps only the newer one.

---

## When Claude updates

There's one Claude.app, so there's nothing to update per profile. But each profile's app **checks for updates on its own**. When one installs an update, any other profile that's open keeps running the old code from a bundle that's been replaced underneath it:

```bash
./bin/tandem profile list
work             you@company.com (team)             account d37cdc9d                   yes — QUIT+REOPEN (app updated since)
```

Quit and reopen each open profile; the menu bar offers *Quit and Reopen*. Then:

```bash
./bin/tandem profile doctor
Claude.app 4.29.0
  ✓ honors --user-data-dir (profiles run side by side)
  ✓ records lastKnownAccountUuid (tandem finds the signed-in account)
  ✓ Cowork store is still local-agent-mode-sessions/
  ✓ Code tab honors CLAUDE_CONFIG_DIR (same login as claude @<p>)
  ✓ claude:// links open /Applications/Claude.app
```

Profiles rest on behaviour found inside Claude's app bundle, not a documented interface. So `doctor` re-checks it, and `tandem profile desktop` runs it automatically whenever the installed version changes. If anything shows **✗**, `desktop` refuses to open a second profile rather than risk opening the wrong account's data. If Claude's icon changed, `tandem profile app --all` rebuilds the launchers.

---

## Removing a profile

There's no `remove` command, on purpose: a profile's folders hold its sign-ins, Cowork projects and memory. To remove one, hand off anything it owns first (`tandem status`), quit it, then delete by **exact path**:

```bash
./bin/tandem profile quit work
rm -rf ~/.claude-work "$HOME/Library/Application Support/Claude-work" \
       "$HOME/Applications/Claude (work).app" ~/.config/claude-tandem/runtimes/work
```

Folders use the id; the launcher uses the profile's *current* name. A profile renamed to `Junipera` has `Claude (Junipera).app`.

The Claude Code sign-in stays in the Keychain as `Claude Code-credentials-…`. It's harmless, and Keychain Access can delete it.

---

## How it works

What profiles rely on, found by reading the Claude 4.29 app bundle, and re-checked by `doctor` on every new version:

- **`--user-data-dir`, not `CLAUDE_USER_DATA_DIR`.** Signed builds of the desktop app ignore the environment variable (the app logs *"signed builds ignore it"*) but honour Chromium's `--user-data-dir` switch. The app's single-instance lock is per data folder, so instances with different folders run side by side.
- **`CLAUDE_CONFIG_DIR`** is honoured by Claude Code, including the desktop app's Code tab, which is how a profile's app and terminal share one Code login. `default` must run with it **unset**: set even to `~/.claude`, Claude Code looks for a differently named Keychain item and reports *not signed in*.
- **One data folder can hold several accounts.** Signing a different account into an app adds another `local-agent-mode-sessions/<account>/<org>/` beside the first. Tandem reads which one is current from `config.json`'s `lastKnownAccountUuid`, rather than taking the first folder it finds.
- **"Is Claude running?" means *this profile's* Claude.** A running app rewrites its project list from memory, so Tandem never edits a profile's `spaces.json` while that profile is open. Other profiles' apps don't count.
