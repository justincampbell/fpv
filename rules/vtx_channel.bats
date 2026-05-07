#!/usr/bin/env bats

load _helper

# F4 = FATSHARK band, channel 4 (5800 MHz). Standard channel for the bag
# so goggles don't need re-tuning between drones, and so multiple drones
# can't accidentally share a channel and clobber each other's video.
# Read dump.txt because some boards default to band/channel 4 and won't
# emit the line in diff.txt.

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
