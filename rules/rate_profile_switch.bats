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

# Extract rateprofile N's setting block from dump.txt — just the `set` lines,
# stripping the header and the `# rateprofile N` comment so the comparison is
# value-only. Empty when the profile is at all-defaults.
_rateprofile_block() {
    awk -v n="$1" '
        $0 == "rateprofile " n { in_sec = 1; next }
        in_sec && /^rateprofile [0-9]+$/ { exit }
        in_sec && /^set / { print }
    ' "$(dump)"
}

@test "rateprofile 0, 1, 2 are all distinct" {
    case "$(craft)" in
        grinderino35) skip "no Pocket bindings configured" ;;
    esac
    local p0 p1 p2; p0=$(_rateprofile_block 0); p1=$(_rateprofile_block 1); p2=$(_rateprofile_block 2)
    local dup=""
    [[ "$p0" == "$p1" ]] && dup="${dup}rateprofile 0 == rateprofile 1\n"
    [[ "$p0" == "$p2" ]] && dup="${dup}rateprofile 0 == rateprofile 2\n"
    [[ "$p1" == "$p2" ]] && dup="${dup}rateprofile 1 == rateprofile 2\n"
    [[ -z "$dup" ]] || {
        echo "expected: rateprofile 0, 1, 2 differ from each other (SC has 3 positions)"
        echo -e "actual:   ${dup%\\n}"
        return 1
    }
}
