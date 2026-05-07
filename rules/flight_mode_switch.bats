#!/usr/bin/env bats

load _helper

@test "SB low binds ANGLE (AUX2, 900-1300)" {
    local id; id=$(mode_id ANGLE)
    grep -qE "^aux [0-9]+ ${id} 1 900 1300 0 0$" "$(dump)" || {
        echo "expected: aux N ${id} 1 900 1300 0 0"
        echo -n "actual:   "
        grep -E "^aux [0-9]+ ${id} " "$(dump)" || echo "(no ANGLE aux line)"
        return 1
    }
}

@test "SB mid binds TURTLE (AUX2, 1300-1700)" {
    local id; id=$(mode_id "FLIP OVER AFTER CRASH")
    grep -qE "^aux [0-9]+ ${id} 1 1300 1700 0 0$" "$(dump)" || {
        echo "expected: aux N ${id} 1 1300 1700 0 0"
        echo -n "actual:   "
        grep -E "^aux [0-9]+ ${id} " "$(dump)" || echo "(no TURTLE aux line)"
        return 1
    }
}

@test "SB high stays acro (no other mode on AUX2)" {
    local angle turtle
    angle=$(mode_id ANGLE)
    turtle=$(mode_id "FLIP OVER AFTER CRASH")
    local stray
    stray=$(grep -E "^aux [0-9]+ [0-9]+ 1 " "$(dump)" \
        | grep -vE "^aux [0-9]+ (${angle}|${turtle}) 1 " \
        | grep -vE " 900 900 0 0$" || true)
    [[ -z "$stray" ]] || {
        echo "expected: AUX2 high unbound (acro)"
        echo "stray modes on AUX2:"
        echo "$stray"
        return 1
    }
}
