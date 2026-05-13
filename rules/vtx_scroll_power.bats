#!/usr/bin/env bats

# Dynamic VTX power on a scroll wheel / variable AUX channel.
# Portable: extracts the AUX channel and power-level count from the dump
# instead of hardcoding. Every drone is expected to have this configured.

load _helper

# `vtx` lines from the dump, excluding the default-unbound form.
active_vtx_lines() {
    grep -E "^vtx [0-9]+ " "$(dump)" | grep -vE "^vtx [0-9]+ 0 0 0 0 900 900$" || true
}

@test "VTX scroll: rules configured" {
    local lines; lines=$(active_vtx_lines)
    [[ -n "$lines" ]] || {
        echo "expected: at least one `vtx` rule binding a power level to a channel range"
        echo "actual:   no active vtx rules in dump.txt"
        return 1
    }
}

@test "VTX scroll: all rules share one AUX channel" {
    local lines; lines=$(active_vtx_lines)
    [[ -n "$lines" ]] || skip "depends on: VTX scroll: rules configured"
    local channels; channels=$(echo "$lines" | awk '{print $3}' | sort -u)
    [[ $(echo "$channels" | wc -l) -eq 1 ]] || {
        echo "expected: all vtx rules on a single AUX channel"
        echo "actual:   $(echo "$channels" | paste -sd ',' -)"
        return 1
    }
}

@test "VTX scroll: bound to P1 (scroll wheel)" {
    local lines; lines=$(active_vtx_lines)
    [[ -n "$lines" ]] || skip "depends on: VTX scroll: rules configured"
    local ch; ch=$(echo "$lines" | head -1 | awk '{print $3}')
    local expected; expected=$(pocket_channel P1)
    [[ "$ch" == "$expected" ]] || {
        echo "expected: VTX rules on channel ${expected} (P1 scroll wheel)"
        echo "actual:   channel ${ch} ($(pocket_source "$ch"))"
        return 1
    }
}

@test "VTX scroll: powers 1..N map in ascending channel order" {
    local lines; lines=$(active_vtx_lines)
    [[ -n "$lines" ]] || skip "depends on: VTX scroll: rules configured"
    local levels; levels=$(grep -E "^vtxtable powerlevels " "$(dump)" | awk '{print $3}')
    [[ -n "$levels" ]] || skip "vtxtable powerlevels not set"
    # If the last powervalue is 0 (SmartAudio PIT), that level is bound via the
    # VTX PIT MODE aux binding (verified by the next test), not a vtx rule.
    local last_pv; last_pv=$(grep -E "^vtxtable powervalues " "$(dump)" | awk '{print $NF}')
    [[ "$last_pv" == "0" ]] && levels=$((levels - 1))
    local powers; powers=$(echo "$lines" | sort -k7n | awk '{print $6}' | paste -sd ' ' -)
    local expected; expected=$(seq 1 "$levels" | paste -sd ' ' -)
    [[ "$powers" == "$expected" ]] || {
        echo "expected: powers 1..${levels} in ascending range order → ${expected}"
        echo "actual (by range_start):                                 ${powers}"
        return 1
    }
}

@test "VTX scroll: PIT mode aux binding (if present) is on same AUX channel" {
    # PIT binding is optional — SmartAudio's runtime pit-mode toggle is flaky on
    # many VTXes. vtx_low_power_disarm=UNTIL_FIRST_ARM is the reliable pre-arm
    # safety net. This test only fires when a PIT aux line exists, to catch
    # mismatched channels.
    local lines; lines=$(active_vtx_lines)
    [[ -n "$lines" ]] || skip "depends on: VTX scroll: rules configured"
    local pit; pit=$(mode_id "VTX PIT MODE")
    local pit_line; pit_line=$(grep -E "^aux [0-9]+ ${pit} " "$(dump)" || true)
    [[ -n "$pit_line" ]] || skip "no PIT mode aux line — relying on vtx_low_power_disarm"
    local ch; ch=$(echo "$lines" | head -1 | awk '{print $3}')
    [[ "$(echo "$pit_line" | awk '{print $4}')" == "$ch" ]] || {
        echo "expected: PIT aux on channel ${ch} (matching vtx rules)"
        echo "actual:   ${pit_line}"
        return 1
    }
}
