#!/usr/bin/env bats

load _helper

@test "vbat_scale is calibrated (recommended)" {
    recommended_set vbat_scale
}
