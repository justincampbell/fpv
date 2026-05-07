#!/usr/bin/env bats

load _helper

@test "vbat_warning_cell_voltage is set" {
    assert_set vbat_warning_cell_voltage
}
