#!/bin/sh
cd "$(dirname "$0")/.." || exit 1
# Import first so class_name global classes are registered for the -s script.
godot --headless --import >/dev/null 2>&1
out=$(godot --headless -s res://tests/run_tests.gd -- "$@" 2>&1)
code=$?
# Drop the engine banner (and the blank line after it); keep everything else.
printf '%s\n' "$out" | grep -v '^Godot Engine v' | sed '1{/^$/d;}'
exit $code
