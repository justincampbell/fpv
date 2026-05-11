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

@test "VTX scroll: powers 1..N map in ascending channel order" {
    local lines; lines=$(active_vtx_lines)
    [[ -n "$lines" ]] || skip "depends on: VTX scroll: rules configured"
    local levels; levels=$(grep -E "^vtxtable powerlevels " "$(dump)" | awk '{print $3}')
    [[ -n "$levels" ]] || skip "vtxtable powerlevels not set"
    local powers; powers=$(echo "$lines" | sort -k7n | awk '{print $6}' | paste -sd ' ' -)
    local expected; expected=$(seq 1 "$levels" | paste -sd ' ' -)
    [[ "$powers" == "$expected" ]] || {
        echo "expected: powers 1..${levels} in ascending range order → ${expected}"
        echo "actual (by range_start):                                 ${powers}"
        return 1
    }
}

@test "VTX scroll: PIT mode bound to same AUX channel" {
    local lines; lines=$(active_vtx_lines)
    [[ -n "$lines" ]] || skip "depends on: VTX scroll: rules configured"
    local ch; ch=$(echo "$lines" | head -1 | awk '{print $3}')
    local pit; pit=$(mode_id "VTX PIT MODE")
    grep -qE "^aux [0-9]+ ${pit} ${ch} " "$(dump)" || {
        echo "expected: aux N ${pit} ${ch} ... (PIT on same AUX channel)"
        echo -n "actual:   "
        grep -E "^aux [0-9]+ ${pit} " "$(dump)" || echo "(no PIT mode aux line)"
        return 1
    }
}
