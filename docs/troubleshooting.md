# Troubleshooting

Most of these fail *silently*: nothing errors, things just look fine and aren't. The measurements behind each are in [findings.md](findings.md).

- [Installing](#installing)
- [Profiles](#profiles)
- [Handoffs](#handoffs)
- [Reaching your other Mac](#reaching-your-other-mac)
- [Two commands never to run](#two-commands-never-to-run)

---

## Installing

| Symptom | Cause | Fix |
|---|---|---|
| `tandem: command not found` after `brew install` | Homebrew's `bin` isn't on your `PATH` | add `eval "$(/opt/homebrew/bin/brew shellenv)"` to `~/.zprofile`, then open a new terminal |
| `tandem` runs an older copy than you expect | a clone's `bin/` comes before Homebrew on your `PATH` | `which -a tandem` lists them in order; drop the clone from `PATH`, or run it as `./bin/tandem` |
| `tandem menubar`: *swiftc not found* | the Command Line Tools aren't installed | `xcode-select --install`, then `tandem menubar` again |
| The menu-bar app's menus do nothing after you delete the clone it was built from | the app runs the `tandem` it was built with | `tandem menubar` from the copy you use now: it sees the install moved and rebuilds |
| Drawing a badge fails with *No module named PIL* (from a clone) | the `python3` on your `PATH` has no Pillow; the Homebrew install brings its own | `python3 -m pip install --user Pillow`, or install with Homebrew |

## Profiles

| Symptom | Cause | Fix |
|---|---|---|
| A new profile's Code tab is empty, though you've used that account before | you used it in your **regular** Claude before it had a profile; the work is still there | menu bar › profile › **Bring In Earlier Sessions…**, or `tandem profile adopt P` |
| A new profile signed in as an account you already use | claude.ai signed it into whichever account the browser already had | in that profile, sign out and sign in again, from a **private browser window** |
| `claude @work`: *not signed in*, though you signed in | `CLAUDE_CONFIG_DIR` set for `default`: even pointing at `~/.claude`, Claude Code looks for a different Keychain item | run `default` with it unset. `tandem profile code` and the `claude @` hook do this |
| Two open profiles look identical in the Dock and ⌘-Tab | they all run the one Claude.app | `tandem profile app P --dock-icon`, then reopen it; or tell them apart in the menu bar |
| `tandem profile list` shows `QUIT+REOPEN` | another profile's app installed a Claude update; this one still runs the replaced code | quit and reopen it: menu bar › Quit and Reopen, or `tandem profile quit P` then `desktop P` |
| `desktop` refuses: *changed something profiles rely on* | a Claude update moved something profiles depend on | `tandem profile doctor` names it; don't work around it, because the next profile might open the wrong account's data |
| `rename` refused: *already profile …* | the name is another profile's id or name | pick another; ids always win over names |
| A profile's badge isn't in the Dock while it runs | `--dock-icon` is off, or the profile was already open when you turned it on | turn it on and reopen; `tandem profile doctor` flags a Dock copy older than Claude |
| Badges are blank or plain | `python3` without Pillow, typically from an app launched at login without your `PATH` | `pip install Pillow` for the `python3` on your `PATH`, then rebuild `tandem menubar --rebuild` so it records that `PATH` |
| `claude://` sign-in links open a profile's Dock copy | macOS chose a copy as the link handler (not seen so far: it prefers `/Applications`) | `tandem profile doctor` detects it and prints the `lsregister -f` line that fixes it |

---

## Handoffs

| Symptom | Cause | Fix |
|---|---|---|
| *"is not inside a folder connected to Cowork"*, though the folder looks attached | the project is linked to a **symlink** | `tandem check`, then, with Claude quit: `tandem project-repath P "$(tandem path P)"` |
| A file reads empty, no error | it's *dataless*: listed at full size, contents still in the cloud | read it again; `tandem materialize`. `du` and `.icloud` checks can't see this |
| `receive` waits, then times out, though `send` said UPLOADED | **this** Mac's iCloud Drive stopped pulling, seen after a reboot (`brctl status`: `client:needs-sync`) | open **Finder › iCloud Drive** and re-run `receive`. `receive` and `check` now flag a stalled drive |
| `receive` times out: *Newest event: none* or an old one | the handoff hasn't reached this Mac, or `send` addressed a different side | `tandem status` on the sender; check `--to` matches this side exactly (`Madoka`, `Madoka@work`) |
| `receive`: *has been EDITED since it was handed over* | work continued here (e.g. in a Cowork session) without a `receive` ever recording the claim | nothing is wrong with the data. Send it from the side that did the work, which writes a fresh manifest |
| `receive` reports a memory **clash** | the same memory changed on both sides while each held the project | compare `name.md` (kept) with `name.from-<Mac>.md` (parked, unindexed); keep one, delete the other by exact path |
| Memory didn't come across | Claude was open when you received | quit Claude, then `tandem memory-install P --merge` |
| `send` refuses: no handoff document | it ships the newest `HANDOFF*.md`, and there isn't one | run `/handoff` in the session; `--no-doc` for a first move |
| `send` warns the document is older than the last handoff | the newest `HANDOFF*.md` is from an earlier round | run `/handoff` again unless nothing has changed since |
| *Claude is running. Quit it first* | Tandem won't write a project list while that profile's app could overwrite it from memory | quit that profile's Claude (`tandem profile quit P`) and re-run |
| `name 2.ext` files appearing | two places wrote to one synced path | `tandem conflicts` (it only reports); remove by exact path, **never** by pattern |
| A Cowork session says the project has no `.handoff` folder | delivered upstream but never listed on this Mac, and a sandboxed session can't make the drive deliver | `tandem receive P`: its wait lists the whole folder chain, which is what makes iCloud hand it over |
| `/handoff` tries to do the transfer itself | an old version of the skill | re-upload `skills/handoff/SKILL.md` |
| Skill upload rejected: *cannot have XML tags* | angle-bracket placeholders in `SKILL.md` | use bare words, not `<Project>` |

---

## Reaching your other Mac

Not needed for handoffs, which go through the drive, but useful for checking on the other side.

| Symptom | Cause | Fix |
|---|---|---|
| `ssh`: *REMOTE HOST IDENTIFICATION HAS CHANGED* | the other Mac is asleep or offline, and `peer.local` resolved to **this** Mac, so you met your own host key | not an attack, so **don't** delete its `known_hosts` line. Wake it, or connect by IP with `ssh -o HostKeyAlias=peer.local you@IP`, which still checks the right key |
| `ssh` times out, though the Mac is awake (AirPlay answers) | Remote Login is off. It has been seen switching itself off on macOS 27; cause not yet found | System Settings › General › Sharing › Remote Login |
| `ssh`: *Host is down*, no ping | the other Mac is asleep | wake it; for remote access, System Settings › Battery › **Wake for network access** |

---

## Two commands never to run

Both ran during development and destroyed data. Both were recovered only because backups existed.

- **`brctl evict <path>`** runs immediately, with no confirmation. Run inside a loop probing which `brctl` subcommands exist, it evicted the whole of iCloud Drive. `brctl --help` lists only `diagnose` and `log`, but the other verbs exist and *run*.
- **`find … -name '* 2*' -delete`**, meant to clean conflict copies, also matches real names with a space and a `2`: it destroyed `GS Vintage VII 2023 Exchanges.qif` on both Macs. Match `* 2.*` and `* 2`, read the list, and delete by exact path.
