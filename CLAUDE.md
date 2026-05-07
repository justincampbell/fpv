# FPV drone config repo

Tracks the Betaflight configuration of each of the user's drones in git so changes are reviewable and reversible.

## ⚠️ Hardware safety

**The drone is not plugged in by default.** It can overheat if left connected to USB while powered. Before running anything that talks to the FC (`bfctl ports/info/dump`, `make backup`, etc.), **ask the user to plug it in.** When the operation is done, remind them to unplug it.

## Layout

One subdirectory per drone under `drones/`, named after the lowercase `craft_name`:

- `drones/<craft>/<craft>.txt` — full Betaflight CLI dump (`diff all` output).
- `drones/<craft>/msp.json` — MSP snapshot of static info the dump doesn't carry (board/build identity, mode names ↔ permanent IDs, mode ranges as the FC sees them). Filtered to a fixed code list — see `MSP_CODES` in the `Makefile`. Use it to decode the `aux` lines in `<craft>.txt`: each `aux N <mode_id> <ch> <start_us> <end_us> <logic> <link>` references a permanent mode ID from `MSP_BOXIDS`, named by `MSP_BOXNAMES` at the same index. Channels are 0-indexed (`0=AUX1, 1=AUX2, …`). The dump's `aux` slots can drift from the FC's live state — if they look wrong, `make backup` resyncs both files.
- `Makefile` — automation around `bfctl` and `bats`.
- `rules/` — bats files that lint each `<craft>.txt`. See [Tests](#tests).

Optional, only when there's something to record:
- `drones/<craft>/<craft>.md` — build notes, hardware, rationale.

## Workflow

**Backing up after a tuning change:** `make backup` pulls the connected FC's config to `drones/<craft>/<craft>.txt` and refreshes `drones/<craft>/msp.json`. Review the diff, commit if intentional. `make msp` refreshes just the MSP snapshot.

**Editing a config with Claude's help:** ask Claude to modify `drones/<craft>/<craft>.txt` directly. The file is line-oriented and idempotent (`set key = value`, etc.), so Claude can read, propose, and edit in place.

**Applying one change to all drones:** describe the change. Claude edits every relevant `drones/*/<craft>.txt` in one pass. Commit message should describe the *intent* ("raise vbat warning to 3.5V"), not the line-level diff.

**Restoring a config to the FC:** `bfctl restore drones/<craft>/<craft>.txt` replays the file line-by-line (matches Configurator's pacing) and ends with `save`, which reboots the FC. Use `--no-save` to apply to RAM only, or `--dry-run` to preview the line stream. AT32 dumps that only carry `# name:` / `# pilot:` headers get the matching `set craft_name` / `set pilot_name` injected automatically.

## Tools

- `bfctl` — Go CLI for talking to the FC over USB. Auto-detects the port. `bfctl --help` for the full list of commands. **Gotcha:** `bfctl backup` enters CLI mode to issue `diff all` and leaves the FC there afterward; any subsequent MSP query (`bfctl msp …`) fails with "FC is in CLI mode" until the FC reboots (unplug/replug, or `bfctl exec exit` which itself reboots the FC). The Makefile's `backup` target avoids this by pulling MSP *before* the dump.
- Web Betaflight Configurator at `app.betaflight.com` — fallback for restore and GUI tasks.

## Conventions

- One drone = one subdirectory under `drones/`, named after the lowercase craft name.
- One commit per logical change, not per backup pull.
- Don't commit a backup with no meaningful diff — review first.

## Tests

`make test` runs every rule in `rules/` against every `<craft>.txt` and prints a per-drone checklist. Requires bats (`brew install bats-core`).

Each rule is a `.bats` file. The Makefile loops over the configs and invokes bats once per drone with `CONFIG=<path>` set. Rules use `$CONFIG` to know which file they're checking; helpers in `rules/_helper.bash` make the common cases one-liners.

**Helpers** (in `rules/_helper.bash`):
- `assert_set <key>` — fails if `set <key> = ...` is missing (any value)
- `assert_set_equals <key> <value>` — fails unless the value matches exactly
- `assert_line "<text>"` — fails if the literal line is missing (for non-`set` directives like `feature OSD`, `beacon RX_LOST`)
- `recommended_set <key>` — `skip` with a note when missing instead of failing; passes when set. Use for things like `vbat_scale` where there's no single correct value.
- `craft` — returns the lowercase craft slug (e.g. `air65`), useful for per-drone branching inside a rule

**Adding a rule:** drop a new `<thing>.bats` into `rules/`, `load _helper`, write one or more `@test` blocks. Keep the test name human-readable — it's what shows in the checklist.

**Per-drone or per-class logic:** rules are bash, so anything goes. Use `case "$(craft)" in air65|air75) ... ;; *) skip "n/a" ;; esac` when a rule only applies to a subset.

**Failure output:** anything a test (or its helpers) `echo`s appears under the `not ok` line as the failure message. Bats also prints a function/line backtrace — that's standard and can't be turned off without third-party libraries.
