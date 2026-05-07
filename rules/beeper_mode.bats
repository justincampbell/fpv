#!/usr/bin/env bats

load _helper

# BEEPER (mode_id 13) is the lost-quad finder — bound to AUX5 high so the
# same switch position works on every radio in the bag. Slot number doesn't
# matter; mode + channel + range do.
@test "BEEPER bound to AUX5 high (1500-2100)" {
    grep -qE "^aux [0-9]+ 13 4 1500 2100 0 0$" "$CONFIG" || {
        echo "expected: aux N 13 4 1500 2100 0 0 (BEEPER, AUX5, 1500-2100us)"
        echo -n "actual:   "
        grep -E "^aux [0-9]+ 13 " "$CONFIG" || echo "(no BEEPER aux line)"
        return 1
    }
}
