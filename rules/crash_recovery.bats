#!/usr/bin/env bats

load _helper

@test "crash_recovery = ON" {
    assert_set_equals crash_recovery ON
}
