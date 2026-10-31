# Why the filenames are versioned

iCloud does not reliably propagate an in-place MODIFICATION of a file the other Mac
has already read — FileProvider pins the cached copy. Measured 2026-08-18: a rewritten
coworkctl.sh was still the old md5 on the receiving Mac minutes later, while a brand-new
file crossed in ~54s.

So every release is a NEW file: coworkctl-v1.sh, coworkctl-v2.sh, ...
Never edit one in place. Bump the number and write a new file.

The rule is about SHIPPED engines — ones `tandem deploy` has put on the drive. An engine
still only in this repo can be edited: v8 was, during the rename to Claude Tandem, because
it had never been deployed.

Old engines keep working across the rename without being edited. v5–v7 look for a custom
root in ~/.config/claude-macos-mirror, which no longer exists, but they read MIRROR_ROOT
first — so bin/tandem exports the resolved root as MIRROR_ROOT (and TANDEM_ROOT) for every
engine it runs. v8 reads TANDEM_ME / TANDEM_ROOT and falls back to the MIRROR_ names.

Callers should resolve the newest version rather than hardcoding one:

    COWORKCTL="$(ls -1 ~/Library/Mobile\ Documents/com~apple~CloudDocs/Claude/_handoff/bin/coworkctl-v*.sh \
                 | sort -V | tail -1)"
    bash "$COWORKCTL" status
