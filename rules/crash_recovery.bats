#!/usr/bin/env bats

load _helper

# crash_recovery levels the quad after a tumble so a missed bounce off a
# branch doesn't end the flight. Per-PID-profile setting; we just require
# it ON somewhere in the diff (i.e. on in at least one profile, which is
# enough for the active profile in practice).
@test "crash_recovery = ON" {
    assert_set_equals crash_recovery ON
}
