#!/usr/bin/env bats

# Pre-arm VTX safety: drops to lowest power level until the first arm.

load _helper

@test "vtx_low_power_disarm = UNTIL_FIRST_ARM" {
    assert_set_equals vtx_low_power_disarm UNTIL_FIRST_ARM
}
