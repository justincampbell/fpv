#!/usr/bin/env bats

load _helper

@test "BEEPER bound to AUX5 high (1500-2100)" {
    local id; id=$(mode_id BEEPER)
    grep -qE "^aux [0-9]+ ${id} 4 1500 2100 0 0$" "$(dump)" || {
        echo "expected: aux N ${id} 4 1500 2100 0 0"
        echo -n "actual:   "
        grep -E "^aux [0-9]+ ${id} " "$(dump)" || echo "(no BEEPER aux line)"
        return 1
    }
}
