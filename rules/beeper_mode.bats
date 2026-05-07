#!/usr/bin/env bats

load _helper

# BEEPER is the lost-quad finder — bound to AUX5 high so the same switch
# position works on every radio in the bag. Read dump.txt so we catch
# defaults too; slot number doesn't matter, mode + channel + range do.
@test "BEEPER bound to AUX5 high (1500-2100)" {
    local id; id=$(mode_id BEEPER)
    grep -qE "^aux [0-9]+ ${id} 4 1500 2100 0 0$" "$(dump)" || {
        echo "expected: aux N ${id} 4 1500 2100 0 0 (BEEPER on AUX5, 1500-2100us)"
        echo -n "actual:   "
        grep -E "^aux [0-9]+ ${id} " "$(dump)" || echo "(no BEEPER aux line)"
        return 1
    }
}
