---
name: handoff
description: Write the handoff document that lets the user's other Mac (Madoka / Ji-su) continue this work. Use when the user says to hand off, move, send, or continue work on their other machine or laptop, or invokes /handoff by name. Captures everything the receiving machine needs into a self-contained document, then hands the transfer itself to the tandem CLI. Use this instead of improvising a summary, because a host-loop Cowork session cannot sync its chat and the other machine starts with no memory of this conversation.
---

# Hand off a workload to the other Mac

Al works across two Macs, **Madoka** (desktop) and **Ji-su** (laptop). Shared projects live at one
path identical on both:

```
~/Library/Mobile Documents/com~apple~CloudDocs/Claude/Projects/PROJECT
```

**Your job is the document, and only the document.** The transfer — materializing files, writing
the manifest, recording ownership, and proving the bytes actually reached iCloud — belongs to
`tandem send`, which runs in a terminal. This session cannot do those things: it is sandboxed to
the project folder and cannot see `fileproviderctl`, the shared `_handoff/` tree, or any CLI. Do
not try, and do not write ownership events yourself; one implementation of the mechanics is the
point.

## Why the document matters more than the bytes

The receiving Mac gets the **files** from the drive automatically. Whether it gets this
*conversation* depends on which kind of session you are:

- **Host-loop session** (runs on this Mac; `local_<uuid>.json` on disk) — the chat is machine-bound
  and cannot travel. This document is the only carrier. That is the case this skill is for.
- **Remote session** (server-side) — the chat already appears on both Macs. Writing a handoff
  document is then optional; say so rather than implying the context would be lost.

If you are unsure which you are, write the document. It is never wrong, only sometimes redundant.

Project memory is a separate thing and it does exist — a local project keeps one under
`spaces/<id>/memory/` — but it is **per-machine**, so the receiving Mac still starts blank unless
`tandem send` carried a snapshot. Do not tell the user there is no memory; tell them it does not
travel by itself.

Everything you know that isn't written down, and isn't in one of those two channels, is lost at the
handoff.

## Step 1 — Identify the project and the target

Project = the folder under the shared `Projects/` tree this session is working in. Target =
whichever of Madoka / Ji-su is not this machine (check device info). Ask only if genuinely
ambiguous.

**Same Mac, other account.** If the user is moving the work to another Claude account on this
same Mac (usually because this account hit its usage limit), the target is `<Mac>@<profile>`,
e.g. `Madoka@b`: each account profile is its own side of a handoff. The document matters just as
much — the other account starts with no memory of this chat. Its receive command is
`tandem --profile <profile> receive "PROJECT"`.

## Step 2 — Write the document

Write `HANDOFF_TOPIC.md` into the project folder — a new file per topic, named for the topic, not
a generic name. `tandem send` picks the **newest** `HANDOFF*.md`, so an old one left in the folder
is harmless, but a vague name makes it hard to tell them apart later.

Assume a competent agent with zero context who will act on it literally.

```markdown
# HANDOFF — one-line subject

Paste this whole document as your first message in Cowork. It is self-contained.

## Your task
What must be accomplished, concretely, with the actual numbers.

## Before you start — check you actually have access
Prerequisites, each independently verifiable. Say what to do if one is missing —
usually "stop, don't improvise."

## Background — what's wrong and why
The reasoning this session paid for. Include corroborating evidence, and name the
wrong theories explicitly so they don't get re-derived.

## Status
What is DONE and verified, with the figures that prove it. Then a table of what remains.

## Gotchas
Failure modes already hit. Silent ones first.
```

What separates a good handoff from a useless one:

- **Put in the numbers.** "Fix the cost basis" is useless; "THW verified exact at $31,461.60" lets
  the next agent check itself.
- **Record dead ends.** "There are NO return-of-capital transactions in 2026 — do not go looking"
  saves an hour.
- **Mark finished work so it isn't redone.** Repeating a completed financial correction is worse
  than never starting.
- **Name prerequisites honestly.** If the work needs Quicken under Parallels and that lives on one
  machine only, say so at the top, and raise it with the user *before* they transfer.

## Step 3 — Read every file you referenced

iCloud keeps evicted files *dataless*: correct name and size in a listing, contents still in the
cloud, and a read returns empty **with no error**. If you summarized a file you never actually
read, the document is fiction. Read anything you cited, and if a file still reads empty after a
retry, say so in the document rather than papering over it.

## Step 4 — Hand it to the CLI

Tell the user the exact command, with the real project name and target substituted:

```
tandem send "PROJECT" --to MACHINE --note "one line summary" --wait
```

Explain what it will do, because it is the half you cannot do: it materializes the folder, writes
an md5 manifest, records the ownership event naming your document, then **waits until every file
has actually uploaded** — and with `--wait`, until the other Mac claims it.

Then tell them not to edit the project here until it comes back. Two Macs editing one synced folder
is what produces iCloud conflict copies, and the ownership record is what prevents it.

Report honestly: at the moment you finish, the work is **written, not delivered**. Nothing has
left this Mac until `tandem send` says so.
