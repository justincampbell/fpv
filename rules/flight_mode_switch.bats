#!/usr/bin/env bats

load _helper

@test "SB low binds ANGLE (900-1300)" {
    local id ch
    id=$(mode_id ANGLE)
    ch=$(pocket_channel SB)
    grep -qE "^aux [0-9]+ ${id} ${ch} 900 1300 0 0$" "$(dump)" || {
        echo "expected: aux N ${id} ${ch} 900 1300 0 0   (ANGLE on SB low)"
        echo -n "actual:   "
        grep -E "^aux [0-9]+ ${id} " "$(dump)" || echo "(no ANGLE aux line)"
        return 1
    }
}

@test "SB mid binds TURTLE (1300-1700)" {
    local id ch
    id=$(mode_id "FLIP OVER AFTER CRASH")
    ch=$(pocket_channel SB)
    grep -qE "^aux [0-9]+ ${id} ${ch} 1300 1700 0 0$" "$(dump)" || {
        echo "expected: aux N ${id} ${ch} 1300 1700 0 0   (TURTLE on SB mid)"
        echo -n "actual:   "
        grep -E "^aux [0-9]+ ${id} " "$(dump)" || echo "(no TURTLE aux line)"
        return 1
    }
}

@test "SB high stays acro (no other mode on SB)" {
    local angle turtle ch
    angle=$(mode_id ANGLE)
    turtle=$(mode_id "FLIP OVER AFTER CRASH")
    ch=$(pocket_channel SB)
    local stray
    stray=$(grep -E "^aux [0-9]+ [0-9]+ ${ch} " "$(dump)" \
        | grep -vE "^aux [0-9]+ (${angle}|${turtle}) ${ch} " \
        | grep -vE " 900 900 0 0$" || true)
    [[ -z "$stray" ]] || {
        echo "expected: SB high unbound (acro)"
        echo "stray modes on SB (channel ${ch}):"
        echo "$stray"
        return 1
    }
}
