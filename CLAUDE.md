# FPV drone config repo

Tracks the Betaflight configuration of each of the user's drones in git so changes are reviewable and reversible.

## ⚠️ Hardware safety

**The drone is not plugged in by default.** It can overheat if left connected to USB while powered. Before running anything that talks to the FC (`bfctl ports/info/dump`, `make backup`, etc.), **ask the user to plug it in.** When the operation is done, remind them to unplug it.

## Layout

Flat — one file per drone at the repo root:

- `<craft>.txt` — full Betaflight CLI dump (`diff all` output) for that drone. Filename is the lowercase `craft_name` from the dump.
- `Makefile` — automation around `bfctl`.

Optional, only when there's something to record:
- `<craft>.md` — build notes, hardware, rationale.

## Workflow

**Backing up after a tuning change:** `make backup` pulls the connected FC's config and overwrites `<craft>.txt`. Review the diff, commit if intentional.

**Editing a config with Claude's help:** ask Claude to modify `<craft>.txt` directly. The file is line-oriented and idempotent (`set key = value`, etc.), so Claude can read, propose, and edit in place.

**Applying one change to all drones:** describe the change. Claude edits every relevant `<craft>.txt` in one pass. Commit message should describe the *intent* ("raise vbat warning to 3.5V"), not the line-level diff.

**Restoring a config to the FC:** `bfctl` does not yet have a `restore` subcommand. For now: open the web Configurator (`app.betaflight.com`), connect, paste the file's contents into the CLI tab, save.

## Tools

- `bfctl` — Go CLI for talking to the FC over USB. Auto-detects the port. `bfctl --help` for the full list of commands.
- Web Betaflight Configurator at `app.betaflight.com` — fallback for restore and GUI tasks.

## Conventions

- One drone = one `.txt` file at the repo root, named after the lowercase craft name.
- One commit per logical change, not per backup pull.
- Don't commit a backup with no meaningful diff — review first.
