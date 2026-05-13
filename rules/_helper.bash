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

# Reverse of mode_id — name for a permanent ID. Empty if the ID isn't in
# this FC's BOXNAMES (e.g. mode disabled in firmware). Use to render aux
# bindings in human-readable form (failure messages, switch tables).
mode_name() {
    local id="$1"
    local msp="$(dirname "$CONFIG")/msp.json"
    jq -r --arg id "$id" '
        (.[] | select(.code == 116) | .decoded | split(", ")) as $names |
        (.[] | select(.code == 119) | .decoded | split(" ") | map(tonumber)) as $ids |
        ($ids | index($id|tonumber)) as $i |
        if $i == null then "" else $names[$i] end
    ' "$msp"
}

# Path to the Pocket "FPV DRONE" model file. Hardcoded to model01 because
# that's the model that flies these drones; the other slots are templates.
# Uses BASH_SOURCE so the helper works from anywhere (bats, bin/switches,
# ad-hoc shell) — no $CONFIG dependency.
_pocket_model() {
    local repo; repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
    echo "$repo/radios/pocket/MODELS/model01.yml"
}

# Look up the Betaflight aux-channel index (0=AUX1 ... 5=AUX6) bound to a
# Pocket source ("SA"–"SE", "P1") in the FPV model. Use in `aux` rules to
# express "BEEPER on SE" instead of hardcoding channel 4 — if the radio is
# remapped, the rule reads the new value automatically.
#
# EdgeTX destCh is 0-indexed across all 16 channels (CH1=0, CH5=4, ...);
# BF aux uses 0=AUX1, 1=AUX2, ... — so the conversion is destCh - 4.
pocket_channel() {
    local src="$1" model dest
    model=$(_pocket_model)
    [[ -f "$model" ]] || { echo "pocket_channel: $model not found" >&2; return 1; }
    dest=$(awk -v want="$src" '
        { sub(/\r$/, "") }
        /^mixData:/          { inmix=1; next }
        inmix && /^[a-zA-Z]/ { exit }
        inmix && /^ -[ \t]*$/ { d=""; s="" }
        inmix && /destCh:/   { d=$2 }
        inmix && /srcRaw:/   { gsub(/"/, "", $2); s=$2 }
        inmix && s == want && d != "" { print d; exit }
    ' "$model")
    [[ -n "$dest" ]] || { echo "pocket_channel: '$src' not bound in model01" >&2; return 1; }
    echo $((dest - 4))
}

# Reverse direction — friendly label ("SA"–"SE", "P1") for a BF aux channel.
# Empty if the channel isn't bound in the Pocket FPV model. Use in failure
# messages so an unexpected channel names itself.
pocket_source() {
    local ch="$1" model dest=$(( $1 + 4 ))
    model=$(_pocket_model)
    [[ -f "$model" ]] || return 0
    awk -v want="$dest" '
        { sub(/\r$/, "") }
        /^mixData:/          { inmix=1; next }
        inmix && /^[a-zA-Z]/ { exit }
        inmix && /^ -[ \t]*$/ { d=""; s="" }
        inmix && /destCh:/   { d=$2 }
        inmix && /srcRaw:/   { gsub(/"/, "", $2); s=$2 }
        inmix && d == want && s != "" { print s; exit }
    ' "$model"
}
