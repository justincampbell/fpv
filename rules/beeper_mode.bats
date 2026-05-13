#!/usr/bin/env bats

load _helper

@test "BEEPER bound to SE high (1500-2100)" {
    local id ch
    id=$(mode_id BEEPER)
    ch=$(pocket_channel SE)
    grep -qE "^aux [0-9]+ ${id} ${ch} 1500 2100 0 0$" "$(dump)" || {
        echo "expected: aux N ${id} ${ch} 1500 2100 0 0   (BEEPER on SE high)"
        local actual; actual=$(grep -E "^aux [0-9]+ ${id} " "$(dump)" || true)
        if [[ -n "$actual" ]]; then
            local got; got=$(echo "$actual" | awk '{print $4}')
            local label; label=$(pocket_source "$got")
            echo "actual:   ${actual}   (channel ${got} = ${label:-unmapped})"
        else
            echo "actual:   (no BEEPER aux line)"
        fi
        return 1
    }
}
