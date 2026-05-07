#!/usr/bin/env bash
# Helpers for rule .bats files. The Makefile sets $CONFIG to the drone's
# diff.txt being checked, then runs bats once per drone.

# Print the value of `set <key> = ...`. Empty if not present.
get_set() {
    local key="$1"
    grep -E "^set ${key} = " "$CONFIG" | sed -E "s/^set ${key} = //"
}

# Pass if `set <key>` is present (any value).
assert_set() {
    local key="$1"
    grep -qE "^set ${key} = " "$CONFIG" || {
        echo "missing: set ${key}"
        return 1
    }
}

# Pass if `set <key> = <value>` matches exactly.
assert_set_equals() {
    local key="$1" expected="$2" actual
    actual=$(get_set "$key")
    [[ "$actual" == "$expected" ]] || {
        echo "expected: set ${key} = ${expected}"
        echo "actual:   set ${key} = ${actual:-<unset>}"
        return 1
    }
}

# Pass if a literal line is present (non-`set` directives like
# `feature OSD`, `beacon RX_LOST`).
assert_line() {
    local line="$1"
    grep -qxF "$line" "$CONFIG" || {
        echo "missing line: $line"
        return 1
    }
}

# Pass unless the literal line is present. Useful for things that are
# on-by-default — Betaflight only emits a line in the diff when it diverges
# from the default, so checking for the absence of `feature -X` or
# `beacon -X` is the right way to confirm "not disabled."
refute_line() {
    local line="$1"
    if grep -qxF "$line" "$CONFIG"; then
        echo "unexpected line present: $line"
        return 1
    fi
}

# Skip with a friendly message instead of failing — for nice-to-have settings
# where there's no single correct value (e.g. vbat_scale needs a meter).
recommended_set() {
    local key="$1"
    if ! grep -qE "^set ${key} = " "$CONFIG"; then
        skip "not set"
    fi
}

# Helper for writing per-drone or per-class logic inside a rule. Returns the
# craft slug derived from the parent directory (e.g. air65, lionbee3).
craft() {
    basename "$(dirname "$CONFIG")"
}

# Path to the drone's dump.txt. Use for rules that need the FC's full
# effective config — `aux` lines, defaults — that diff.txt omits when
# they match the board defaults.
dump() {
    echo "$(dirname "$CONFIG")/dump.txt"
}

# Look up a mode's permanent ID by name (e.g. "ANGLE", "BEEPER",
# "FLIP OVER AFTER CRASH"). Reads msp.json, mapping MSP_BOXNAMES (116)
# slot order to MSP_BOXIDS (119) values. Use in `aux` rules instead of
# hardcoding the integer ID — names are stable across firmware versions,
# permanent IDs aren't necessarily exposed to the user.
mode_id() {
    local name="$1"
    local msp="$(dirname "$CONFIG")/msp.json"
    jq -r --arg n "$name" '
        (.[] | select(.code == 116) | .decoded | split(", ")) as $names |
        (.[] | select(.code == 119) | .decoded | split(" ") | map(tonumber)) as $ids |
        ($names | index($n)) as $i |
        if $i == null then "ERR" else $ids[$i] end
    ' "$msp"
}
