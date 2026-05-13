# FPV drone config repo

Tracks the Betaflight configuration of each of the user's drones — and the EdgeTX configuration of each radio that flies them — in git so changes are reviewable and reversible.

## ⚠️ Hardware safety

**The drone is not plugged in by default.** It can overheat if left connected to USB while powered. Before running anything that talks to the FC (`bfctl ports/info/dump`, `make fc-backup`, etc.), **ask the user to plug it in.** When the operation is done, remind them to unplug it.

The radio is a separate device — plugged into USB in mass-storage mode it just exposes the SD card, no power concerns.

## Layout

One subdirectory per drone under `drones/`, named after the lowercase `craft_name`:

- `drones/<craft>/diff.txt` — Betaflight CLI `diff all` output (only non-default settings, replayable via `bfctl restore`).
- `drones/<craft>/dump.txt` — Betaflight CLI `dump all` output (every setting, including defaults). Read-only reference; not used for restore.
- `drones/<craft>/msp.json` — MSP snapshot of static info the dump doesn't carry (board/build identity, mode names ↔ permanent IDs, mode ranges as the FC sees them). Filtered to a fixed code list — see `MSP_CODES` in the `Makefile`. Use it to decode the `aux` lines in `dump.txt`: each `aux N <mode_id> <ch> <start_us> <end_us> <logic> <link>` references a permanent mode ID from `MSP_BOXIDS`, named by `MSP_BOXNAMES` at the same index. Channels are 0-indexed (`0=AUX1, 1=AUX2, …`). `diff.txt` only shows aux slots that differ from the board's defaults; `dump.txt` shows all 20.

One subdirectory per radio under `radios/`, named after the EdgeTX `board:` value (e.g. `pocket`). Mirrors the relevant subset of the EdgeTX SD card so restore is a plain `cp -R` back onto the card:

- `radios/<name>/MODELS/model*.yml` — per-model profiles (channel map, mixes, telemetry, failsafe, switch warnings).
- `radios/<name>/RADIO/radio.yml` — radio-level settings (board, stick mode, sound/haptic, LQ alarms, language).
- `radios/<name>/edgetx.sdcard.{target,version}` — EdgeTX SD layout identity.
- Deliberately not copied: `FIRMWARE/`, `LOGS/`, `SCREENSHOTS/`, `SCRIPTS/` (Lua, ~4MB), `SOUNDS/` (~10MB), `README.txt` placeholders, macOS `._*` AppleDouble files. Backup target filters these out.

Source files on the FAT32 SD card use CRLF line endings — preserved as-is in the repo so that copying back to the card keeps the radio happy. Be careful: anything we generate or hand-edit under `radios/` should use CRLF too, or EdgeTX may not parse it.

- `Makefile` — automation around `bfctl`, `rsync`, and `bats`.
- `rules/` — bats files that lint each `diff.txt`. See [Tests](#tests).

Optional, only when there's something to record:
- `drones/<craft>/<craft>.md` — build notes, hardware, rationale.

## Workflow

**Backing up after a tuning change:** `make fc-backup` pulls the connected FC into `drones/<craft>/`, writing `msp.json`, `dump.txt`, and `diff.txt` (in that order — MSP must precede CLI-mode operations). The composite target depends on `fc-msp`, `fc-dump`, `fc-diff-save`; run any one individually to refresh just that file. `make fc-diff` is the *compare-only* counterpart — it diffs the live FC against its tracked `diff.txt` without writing anything.

**Backing up the radio:** plug the radio in over USB in mass-storage mode and run `make radio-backup`. It auto-detects the SD card under `/Volumes/`, derives the radio name from `radio.yml`'s `board:` field, and rsyncs `MODELS/` + `RADIO/` + the two `edgetx.sdcard.*` identity files into `radios/<name>/`. Skips sounds/scripts/logs/screenshots/firmware/AppleDouble — the SD card is slow and those don't belong in git.

**Backing up the Radiomaster T8L** is a separate path because the T8L is a screenless radio with no removable SD card and no EdgeTX-style USB mass storage. Its config lives in internal flash, only accessible via a custom Radiomaster protocol while the radio is in **M+power management mode** (hold M while pressing power for 3 s — the same combo used for firmware update). In runtime mode the T8L doesn't expose USB at all. Run `make t8l-backup` while in that mode; it shells out to `scripts/t8l-backup.py` (uv-run, PEP 723 inline deps so no manual venv) which pulls a ~1.1KB settings dump over `/dev/cu.usbmodemRADIOMASTER1` at 420000 baud and writes:
- `radios/t8l/tx-settings.bin` — raw response, byte-stable between runs except for the live `Bad/Good` link counter; this is the canonical backup and the input for any future restore tool.
- `radios/t8l/tx-settings.txt` — fully decoded human-readable view: every setting's name, type, value, default, range/options. Uses the firmware's own type table (UINT8 / TEXT_SELECTION / FOLDER / INFO / COMMAND / …) as decoded from the web configurator source.

Protocol: request frames `A5 [subsys] [cmd] [...] 0D 0A` at 420000 baud. Subsystems `11`=TX-side, `22`=RX-side, `55`=channels. Response is a `0x56`-sentinel-prefixed packet wrapping chunked records (`[CRC] EA LEN MARKER EA EE [payload]` with marker `0x29` for device info, `0x2B` for a parameter). Multi-byte parameter records span several chunks with `seq` counting down to 0. Full byte-level breakdown lives in the docstring of `scripts/t8l-backup.py`, reverse-engineered from `radiomaster-rc/RM-Web-Page` (https://radiomaster-rc.github.io/RM-Web-Page/Connection.html).

Caveats baked into the decoder: `Bad/Good` is marked `(live)` because it drifts between dumps; Pitmode option names are cosmetically substituted (`\xc0` → `↓`, `\xc1` → `↑`) — protocol-wise those are raw bytes. The `.bin` is the source of truth; the `.txt` is the diff target.

**Editing a config with Claude's help:** ask Claude to modify `drones/<craft>/diff.txt` directly. The file is line-oriented and idempotent (`set key = value`, etc.), so Claude can read, propose, and edit in place. `dump.txt` is the full reference (incl. defaults); don't hand-edit it — it's regenerated each backup.

**Applying one change to all drones:** describe the change. Claude edits every relevant `drones/*/diff.txt` in one pass. Commit message should describe the *intent* ("raise vbat warning to 3.5V"), not the line-level diff.

**Restoring a config to the FC:** `bfctl restore drones/<craft>/diff.txt` replays the file line-by-line (matches Configurator's pacing) and ends with `save`, which reboots the FC. Use `--no-save` to apply to RAM only, or `--dry-run` to preview the line stream. AT32 dumps that only carry `# name:` / `# pilot:` headers get the matching `set craft_name` / `set pilot_name` injected automatically. To clear an aux slot in the diff, set it to `aux N 0 0 900 900 0 0` — that's the FC's "unbound" form.

**Verifying which AUX channel a radio switch sends to:** the Pocket (and other multi-protocol radios) can map the same physical switch to different AUX channels per model profile, so the FC's binding may not match what you think the radio is sending. To check live: have the user power the radio on, then `bfctl msp 105` reads MSP_RC (32 bytes = 16 little-endian uint16 channels; channels 0–3 = AETR, 4+ = AUX1+). Read once at rest, ask the user to flip the switch, read again — the channel that changes is the one the radio is sending. Compare that to the FC's `aux` lines to confirm the binding. We've already been bitten by this on the Air75 beeper.

## Tools

- `bfctl` — Go CLI for talking to the FC over USB. Auto-detects the port. `bfctl --help` for the full list of commands. **Gotcha:** `bfctl backup` enters CLI mode to issue `diff all` and leaves the FC there afterward; any subsequent MSP query (`bfctl msp …`) fails with "FC is in CLI mode" until the FC reboots (unplug/replug, or `bfctl exec exit` which itself reboots the FC). The Makefile's `fc-backup` target orders sub-targets `fc-msp → fc-dump → fc-diff-save` (with `.NOTPARALLEL`) so MSP always runs first.
- Web Betaflight Configurator at `app.betaflight.com` — fallback for restore and GUI tasks. **Gotcha:** Configurator holds the serial port for the duration of the connection; `bfctl` will fail with `Serial port busy` until you disconnect (or close the tab).

## Conventions

- One drone = one subdirectory under `drones/`, named after the lowercase craft name.
- One commit per logical change, not per backup pull.
- Don't commit a backup with no meaningful diff — review first.
- When the user refers to "this FC" / "the FC" / "the drone" without naming one, default to the drone currently plugged in. Use `bfctl info` (or the craft name from a fresh `bfctl backup`) to identify it — don't ask which drone. If nothing is plugged in, then ask.
- Same convention for radios: "the radio" / "this radio" defaults to whichever EdgeTX SD card is mounted under `/Volumes/`. Derive the name from `radio.yml`'s `board:` field.

## Tests

`make test` runs every rule in `rules/` against every `diff.txt` and prints a per-drone checklist. Requires bats (`brew install bats-core`).

Each rule is a `.bats` file. The Makefile loops over the configs and invokes bats once per drone with `CONFIG=<path>` set. Rules use `$CONFIG` to know which file they're checking; helpers in `rules/_helper.bash` make the common cases one-liners.

**Helpers** (in `rules/_helper.bash`):
- `assert_set <key>` — fails if `set <key> = ...` is missing (any value)
- `assert_set_equals <key> <value>` — fails unless the value matches exactly
- `assert_line "<text>"` — fails if the literal line is missing (for non-`set` directives like `feature OSD`, `beacon RX_LOST`)
- `refute_line "<text>"` — fails if the literal line *is* present. Use for "on by default" features where the diff would only emit a `feature -X` / `beacon -X` line when disabled.
- `recommended_set <key>` — `skip` with a note when missing instead of failing; passes when set. Use for things like `vbat_scale` where there's no single correct value.
- `craft` — returns the lowercase craft slug (e.g. `air65`), useful for per-drone branching inside a rule
- `dump` — returns the path to the drone's `dump.txt`. Use in `aux` rules: `diff.txt` only contains lines that *differ* from the board defaults, so a board that ships ANGLE on AUX2 (e.g. LIONBEE_V1) won't have it in the diff at all. `dump.txt` always shows the full effective config.
- `mode_id <name>` — returns the permanent mode ID for a name (e.g. `mode_id BEEPER` → `13`, `mode_id "FLIP OVER AFTER CRASH"` → `35`). Reads `msp.json`. Always use this in `aux` rules instead of hardcoding the integer — names are stable and self-documenting; permanent IDs aren't surfaced in Configurator.

**Adding a rule:** drop a new `<thing>.bats` into `rules/`, `load _helper`, write one or more `@test` blocks. Keep the test name human-readable — it's what shows in the checklist.

**Per-drone or per-class logic:** rules are bash, so anything goes. Use `case "$(craft)" in air65|air75) ... ;; *) skip "n/a" ;; esac` when a rule only applies to a subset.

**Failure output:** anything a test (or its helpers) `echo`s appears under the `not ok` line as the failure message. Bats also prints a function/line backtrace — that's standard and can't be turned off without third-party libraries.
