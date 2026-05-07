#!/usr/bin/env bats

load _helper

# Without bat_capacity, the OSD's mAh % and remaining-time estimates don't
# work. Value is per-drone (different battery sizes) — just has to be set.
@test "bat_capacity is set" {
    assert_set bat_capacity
}
