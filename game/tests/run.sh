#!/bin/sh
cd "$(dirname "$0")/.." || exit 1
# Import first so class_name global classes are registered for the -s script.
imp=$(godot --headless --import 2>&1)
impcode=$?
out=$(godot --headless -s res://tests/run_tests.gd -- "$@" 2>&1)
code=$?
# Drop the engine banner (and the blank line after it); keep everything else.
printf '%s\n' "$out" | grep -v '^Godot Engine v' | sed '1{/^$/d;}'
# A GDScript runtime error aborts a test method without failing it, so any
# engine error/warning line in the import or the run fails the whole run.
pat='^(SCRIPT ERROR|ERROR|USER ERROR|WARNING)'
if [ $impcode -ne 0 ] || printf '%s\n' "$imp" | grep -qE "$pat"; then
	printf '%s\n' "$imp" | grep -E "$pat" -A3
	echo "FAIL import step reported errors"
	code=1
fi
# Godot only prints an import error the first time; later runs skip the asset silently,
# but its .import file keeps `valid=false`.
broken=$(find . -path ./.godot -prune -o -name '*.import' -print | xargs grep -l '^valid=false' 2>/dev/null)
if [ -n "$broken" ]; then
	printf '%s\n' "$broken"
	echo "FAIL assets failed to import"
	code=1
fi
if printf '%s\n' "$out" | grep -qE "$pat"; then
	echo "FAIL engine errors/warnings in output"
	code=1
fi
exit $code
