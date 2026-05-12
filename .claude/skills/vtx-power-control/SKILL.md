---
name: vtx-power-control
description: Walks the user through configuring dynamic VTX power control on a scroll wheel or 3-way toggle switch for the currently plugged-in drone. Use when the user wants to set up runtime VTX power adjustment via radio input.
---

# VTX power control setup

Configure dynamic VTX power on a radio input (scroll wheel or 3-way toggle). Each input position maps to a power level from the FC's `vtxtable`, with optional VTX PIT MODE on the lowest position.

## Workflow

### 1. Fresh backup first

The dump on disk may be stale. Ask the user to plug in the drone (FC only, no battery), then run `make backup` to refresh `diff.txt`, `dump.txt`, and `msp.json`. If `git status` shows changes, review and commit any drift before proceeding.

### 2. Read the dump

Pull these from `drones/<craft>/dump.txt`:
- `vtxtable powerlevels N` — number of power steps available
- `vtxtable powerlabels` — human labels (e.g. `25 100 MAX`)
- Existing `vtx 0..9` lines — warn the user if any are already non-default (`vtx N 0 0 0 0 900 900`); ask whether to extend or replace
- Existing `aux` table — find the first unused slot (matches `aux N 0 0 900 900 0 0`) for the PIT-mode binding

### 3. Pick the input device

Ask the user: scroll wheel or 3-way toggle? This determines how many zones to define and the natural mapping.

| Input | Zones | Typical mapping |
|---|---|---|
| Scroll wheel | 3–N (matches `powerlevels`, optionally +1 for PIT) | continuous: zones span 1000–2000μs |
| 3-way toggle | 3 zones with sharp boundaries | low/mid/high = `<1300` / `1300-1700` / `>1700` |

### 4. Identify the AUX channel live

Don't trust the radio's labeling — different model profiles can remap. Verify via MSP_RC:

```bash
bfctl msp 105
```

Decode the 32 bytes as 16 little-endian uint16 channels (channels 0–3 = AETR, 4+ = AUX1+). Note the current values, then ask the user to move the input (flip toggle to one extreme, or scroll wheel one way). Read again. The channel that changed is the one the radio sends — that's the `aux_channel` index for our `vtx`/`aux` lines (AUX1 = index 0, AUX6 = index 5).

### 5. Propose the mapping

Show the user a table of zones → power levels before editing. Ask whether to bind VTX PIT MODE on the lowest zone (recommended for safety in the pits). Use `mode_id "VTX PIT MODE"` via `rules/_helper.bash` conventions, or `bfctl exec "get vtx_pit_mode_freq"` to spot-check that PIT is supported — though every modern Betaflight build has it.

### 6. Edit `drones/<craft>/diff.txt`

Add:
- One `aux <slot> <pit_mode_id> <aux_channel> <range_start> <range_end> 0 0` line for PIT, repurposing the first unused aux slot.
- One `vtx <slot> <aux_channel> 0 0 <power> <range_start> <range_end>` per power zone, starting at `vtx 0`. `band = 0` and `channel = 0` mean "no change" — keep the FC's current band/channel. `power` is 1-indexed into the powervalues table (1 = lowest label).

Shared boundaries between zones (e.g. `1500` ending one and starting the next) are fine — Betaflight evaluates rules in order and the last matching one wins.

### 7. Recommend the disarm-safety setting

If `set vtx_low_power_disarm` isn't already `UNTIL_FIRST_ARM` in the dump, recommend adding it. It pins the VTX to the lowest power level until the first arm, then normal control takes over.

### 8. Restore and verify

```bash
bfctl restore drones/<craft>/diff.txt
```

After it reboots, sleep briefly then verify with:

```bash
bfctl exec "vtx"
bfctl exec "aux" | grep "^aux [0-9]\+ <pit_mode_id> "
```

`bfctl exec` leaves the FC in CLI mode — run `bfctl exec exit` to reboot it out before any subsequent MSP query.

### 9. Live test

Ask the user to power on the radio (drone still on USB, no battery), watch `vtx_power` via `bfctl get vtx_power` while they move the input. The value should track the zones.

### 10. Backup, review, commit

Run `make backup` again to capture the live state, review the `git diff`, and commit. Then remind the user to **unplug** the drone.

## Coverage check

After committing, `make test` runs `rules/vtx_scroll_power.bats` and `rules/vtx_low_power_disarm.bats` which verify:
- At least one active `vtx` rule
- All rules on a single AUX channel
- Powers 1..N map in ascending channel order
- VTX PIT MODE is bound to the same AUX channel
- `vtx_low_power_disarm = UNTIL_FIRST_ARM`

If any of those fail, the rule output points to what's missing.
