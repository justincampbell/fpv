#!/usr/bin/env bats

load _helper

@test "VTX band = 4 (FATSHARK)" {
    grep -qxE "set vtx_band = 4" "$(dump)" || {
        echo "expected: set vtx_band = 4"
        echo -n "actual:   "
        grep -E "^set vtx_band = " "$(dump)" || echo "(no vtx_band line)"
        return 1
    }
}

@test "VTX channel = 4" {
    grep -qxE "set vtx_channel = 4" "$(dump)" || {
        echo "expected: set vtx_channel = 4"
        echo -n "actual:   "
        grep -E "^set vtx_channel = " "$(dump)" || echo "(no vtx_channel line)"
        return 1
    }
}
