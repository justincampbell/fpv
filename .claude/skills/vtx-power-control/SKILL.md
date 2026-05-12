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

Decode the 32 bytes as 16 little-endian uint16 channels (channels 0–3 = AETR, 4+ = AUX1+). **The radio must be powered on before the first reading** — otherwise the FC returns its at-rest defaults, which won't line up with radio-on values and you won't be able to spot the change. Have the user power on the radio and hold the input at one extreme, take a reading, then move to the opposite extreme and take another. The channel that changed is the one the radio sends — that's the `aux_channel` index for our `vtx`/`aux` lines (AUX1 = index 0, AUX6 = index 5).

### 5. Propose the mapping

Show the user a table of zones → power levels before editing. Then ask whether to bind VTX PIT MODE on the lowest zone.

**PIT mode caveat — flag this to the user.** Even when the FC firmware exposes `VTX PIT MODE` (mode ID via `mode_id "VTX PIT MODE"` in `rules/_helper.bash`) and the `vtxtable` ends with a `PIT` label (powervalue `0`, the SmartAudio convention), runtime PIT-toggling via an aux switch is historically unreliable on SmartAudio VTXes. SmartAudio v1/v2 only enters pit at power-on; even v2.1 has multiple open Betaflight issues where the aux toggle silently doesn't take effect mid-flight, or only works if the switch is in the pit position at FC boot. Don't assume "the mode exists in the FC" means "the toggle works live."

Offer two paths:

- **Skip PIT, rely on `vtx_low_power_disarm = UNTIL_FIRST_ARM`** (recommended unless live PIT-toggle is verified working on this specific VTX). The VTX stays at the lowest power until first arm regardless of wheel position — covers the pre-arm safety case without depending on the unreliable toggle. Map all power zones across the full input range.
- **Bind PIT on the lowest zone** if the user has already confirmed live-toggle works on the same VTX hardware (e.g. via OSD or a successful prior test). Use `mode_id "VTX PIT MODE"` for the permanent ID.

**Counting power zones:** if `vtxtable powervalues` ends in `0` (the SmartAudio PIT slot), there are `N-1` real power levels available regardless of which path you choose — that trailing slot is never mapped to a `vtx` rule. Create `N-1` vtx rules covering powers `1..N-1`. With "bind PIT": those rules cover the upper part of the input range and the PIT aux covers the lowest zone. With "skip PIT": the `N-1` rules span the full input range. If the vtxtable has no trailing `0`, create all `N` vtx rules across the full range.

### 6. Edit `drones/<craft>/diff.txt`

Add:
- If binding PIT: one `aux <slot> <pit_mode_id> <aux_channel> <range_start> <range_end> 0 0` line, repurposing the first unused aux slot.
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
bfctl exec "aux" | grep "^aux [0-9]\+ <pit_mode_id> "   # only if PIT was bound
```

`bfctl exec` leaves the FC in CLI mode — run `bfctl exec exit` to reboot it out before any subsequent MSP query. The FC may take longer than a few seconds to re-enumerate after a restore + CLI-exit chain; if the next `make backup` or MSP call fails with "no Betaflight FC found", ask the user to unplug-replug rather than retrying in a loop.

### 9. Live test

Ask the user to power on the radio (drone still on USB, no battery), watch `vtx_power` via `bfctl get vtx_power` while they move the input. The value should track the zones.

### 10. Backup, review, commit

Run `make backup` again to capture the live state, review the `git diff`, and commit. Then remind the user to **unplug** the drone.

## Coverage check

After committing, `make test` runs `rules/vtx_scroll_power.bats` and `rules/vtx_low_power_disarm.bats` which verify:
- At least one active `vtx` rule
- All rules on a single AUX channel
- Powers 1..N map in ascending channel order
- If a PIT mode aux line is present, it's on the same AUX channel as the vtx rules (skipped when absent — PIT binding is optional)
- `vtx_low_power_disarm = UNTIL_FIRST_ARM`

If any of those fail, the rule output points to what's missing.
