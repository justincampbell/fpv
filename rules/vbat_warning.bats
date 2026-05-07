#!/usr/bin/env bats

load _helper

# Per-drone value (depends on battery chemistry — Lava2 HV vs. regular LiPo,
# 1S vs. 4S), but every drone should have an explicit warning threshold so
# the OSD nags before you over-discharge.
@test "vbat_warning_cell_voltage is set" {
    assert_set vbat_warning_cell_voltage
}
