#!/usr/bin/env bats

load _helper

@test "bat_capacity is set" {
    assert_set bat_capacity
}
