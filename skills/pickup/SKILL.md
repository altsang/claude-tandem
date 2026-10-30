---
name: pickup
description: Resume a workload handed over from the user's other Mac (Madoka / Ji-su). Use when the user says to pick up, resume, or continue work handed off from their other machine, or invokes /pickup by name. Loads the handoff document as working context, confirms this machine actually holds the project, and checks the prerequisites before any work starts.
---

# Pick up a workload from the other Mac

> **Not installed by default.** `tandem receive` claims the project and hands you the document, so
> this skill has nothing mechanical left to do. It is kept for anyone who wants the prerequisite
> ritual inside the session — but note that a Cowork session cannot force iCloud to deliver, so it
> can report a folder as missing when the data is merely un-enumerated. See `docs/findings.md` 12.

Counterpart to `/handoff`. Shared projects live at one path identical on both Macs:

```
~/Library/Mobile Documents/com~apple~CloudDocs/Claude/Projects/PROJECT
```

The transfer itself — waiting for the drive, md5-verifying every file against the manifest,
defining the project on this Mac, and claiming ownership — is done by `tandem receive` in a
terminal, before you are invoked. This session is sandboxed to the project folder and cannot
verify a transfer or reach any CLI, so do not attempt those steps or write ownership events.

## Step 1 — Confirm this machine actually holds the project

Read `PROJECT_FOLDER/.handoff/events/*.json`. Sort by filename; the newest event is the current
state — owner is `to` if its verb is `handoff`, `machine` if it is `claim`.

- **Newest is a `claim` by this machine** → good, `tandem receive` ran. Continue.
- **Newest is a `handoff` to this machine** → the files are here but nothing verified them. Stop
  and ask the user to run `tandem receive "PROJECT"` in a terminal first. It confirms every file
  arrived complete, which you cannot check from in here: a file that never uploaded is simply
  **absent** from this Mac's listing, not empty, so nothing about the folder looks wrong.
- **Newest names the other Mac** → this project was not handed over. Say so and stop. Editing it
  anyway is how iCloud produces `(conflicted copy)` files.
- **No events at all** → this project has never been through a handoff; ask before assuming.

## Step 2 — Load the document as your brief

The newest event's `handoff_doc` field names the file. Read that exact file — do not guess from
the folder listing, which may hold documents from earlier topics.

Read it as your working brief, not as background. It was written by a session with context you do
not have; where it contradicts your assumptions, it wins.

## Step 3 — Verify prerequisites before acting

Work through the document's prerequisite section **on this machine**. The common failure is work
that needs something only the other Mac has — Quicken under Parallels, a mounted volume, a live
web session.

If one is missing, say so and stop. Do not improvise a substitute. Offer to hand the work back.

## Step 4 — Confirm the plan

Before executing, tell the user what the previous machine finished, what remains, and what you
will do first. Cheaper to catch a stale handoff now than after a wrong edit.

## If the folder is not readable

Symptom: the folder appears connected but every read fails with *"is not inside a folder connected
to Cowork on this device"*. Cause: the project points at a **symlink**. It has to be repointed at
the real shared path, which needs a terminal and a quit app — ask the user to run:

```
tandem check                                       # names the project and prints the fix
tandem project-repath "PROJECT" "$(tandem path "PROJECT")"
```

Then relaunch Claude. No folder picker is involved.

Note also that **cloud** Cowork projects run in a bridged VM and could not reach `~/Library` at
all. Use the `Local`-badged project for file work.

## Ownership

From the claim onward this machine is the only one that should edit the project. When the work is
done or stalls, `/handoff` writes the return document and `tandem send` carries it back.
