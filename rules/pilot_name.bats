#!/usr/bin/env bats

load _helper

@test "pilot_name = Justin" {
    assert_set_equals pilot_name Justin
}
