#!/usr/bin/env bats

load _helper

# SB on the Radiomaster Pocket is the flight-mode switch (AUX2). Three
# positions: low = ANGLE (self-level), mid = TURTLE (flip-over-after-crash),
# high = acro. Same physical motion on every quad so muscle memory transfers.
# Read dump.txt because boards may default-bind ANGLE; diff.txt would omit it.

@test "SB low binds ANGLE (AUX2, 900-1300)" {
    local id; id=$(mode_id ANGLE)
    grep -qE "^aux [0-9]+ ${id} 1 900 1300 0 0$" "$(dump)" || {
        echo "expected: aux N ${id} 1 900 1300 0 0 (ANGLE on AUX2 low)"
        echo -n "actual:   "
        grep -E "^aux [0-9]+ ${id} " "$(dump)" || echo "(no ANGLE aux line)"
        return 1
    }
}

@test "SB mid binds TURTLE (AUX2, 1300-1700)" {
    local id; id=$(mode_id "FLIP OVER AFTER CRASH")
    grep -qE "^aux [0-9]+ ${id} 1 1300 1700 0 0$" "$(dump)" || {
        echo "expected: aux N ${id} 1 1300 1700 0 0 (TURTLE on AUX2 mid)"
        echo -n "actual:   "
        grep -E "^aux [0-9]+ ${id} " "$(dump)" || echo "(no TURTLE aux line)"
        return 1
    }
}

@test "SB high stays acro (no other mode on AUX2)" {
    # ANGLE and TURTLE on AUX2 are expected — anything else there steals
    # the high position from acro. Skip placeholder rows (range 900-900).
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
