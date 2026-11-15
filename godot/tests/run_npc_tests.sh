#!/bin/bash
# Dev tool: runs the npc_life GUT suites headless under godotsem and returns a TRUSTWORTHY exit code.
# GUT alone skips a test script that fails to parse (only a "Warnings 1" line, exit 0, "All tests passed"), so this wrapper also fails on any
# SCRIPT ERROR / Parse Error / GUT warning in the output. Usage: tests/run_npc_tests.sh [extra gut args, e.g. -gselect=test_station.gd]
cd "$(dirname "$0")/.." || exit 2
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
OUT=$(mktemp)
~/.claude/bin/godotsem -- "$GODOT --headless --path $PWD -s addons/gut/gut_cmdln.gd -gdir=res://tests/npc_life -gexit $*" > "$OUT" 2>&1
CODE=$?
cat "$OUT"
if grep -q "SCRIPT ERROR\|Parse Error\|^Warnings\|Failing Tests\|failed\." "$OUT"; then CODE=1; fi
if ! grep -q "All tests passed" "$OUT"; then CODE=1; fi
rm -f "$OUT"
echo "[run_npc_tests] exit=$CODE"
exit $CODE
