#!/usr/bin/env bats

load _helper

# Calibrates the FC's vbat reading against the actual battery voltage. Needs
# a multimeter to find the right value, so this is recommended-only — the
# rule passes when set, skips (with a note) when not.
@test "vbat_scale is calibrated (recommended)" {
    recommended_set vbat_scale
}
