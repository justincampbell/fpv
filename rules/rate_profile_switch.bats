#!/usr/bin/env bats

# Rate profile selection on a 3-position switch (SC by convention on Pocket).
# Uses Betaflight `adjrange` with adjustment function 12 (RATE_PROFILE) in
# SELECT mode (center=0, scale=0). With default switchPositions=3, the channel
# range 900-2100 splits into thirds: low→profile 0, mid→profile 1, high→profile 2.
# On the Pocket SC physically up = channel low = profile 0 (max rates).
#
# Grinderino35 has no Pocket bindings at all and is skipped.

load _helper

@test "SC binds rate profile selection (adjrange function 12)" {
    case "$(craft)" in
        grinderino35) skip "no Pocket bindings configured" ;;
    esac
    local ch; ch=$(pocket_channel SC)
    grep -qE "^adjrange [0-9]+ 0 ${ch} 900 2100 12 ${ch} 0 0$" "$(dump)" || {
        echo "expected: adjrange N 0 ${ch} 900 2100 12 ${ch} 0 0   (RATE_PROFILE on SC)"
        echo -n "actual:   "
        grep -E "^adjrange [0-9]+ 0 [0-9]+ [0-9]+ [0-9]+ 12 " "$(dump)" \
            | grep -vE " 0 0 0 0 0 0 0 0$" || echo "(no RATE_PROFILE adjrange)"
        return 1
    }
}

@test "rate_6pos_switch is OFF (3-pos default, not 6-pos override)" {
    case "$(craft)" in
        grinderino35) skip "no Pocket bindings configured" ;;
    esac
    local val; val=$(grep -E "^set rate_6pos_switch = " "$(dump)" | awk '{print $4}')
    [[ "$val" == "OFF" ]] || {
        echo "expected: set rate_6pos_switch = OFF (3-pos splits into thirds)"
        echo "actual:   set rate_6pos_switch = ${val:-<unset>}"
        return 1
    }
}
