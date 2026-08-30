#!/usr/bin/env bash
# Runs every headless check. Developer tool — never shipped.
#
#   ./tools/run_tests.sh
#
# Set GODOT to point at your editor binary if it is not on PATH. On the machine
# this was written on it lives at:
#   D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe

set -uo pipefail

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SUITES=(
	"res://tools/smoke_test.tscn|core systems"
	"res://tools/ui_smoke_test.tscn|UI components and touch targets"
	"res://tools/warung_test.tscn|Warung end to end"
	"res://tools/kebun_test.tscn|Kebun end to end"
	"res://tools/integration_test.tscn|hub to mini-game and back"
)

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "Godot not found at '$GODOT'. Set GODOT to the editor binary." >&2
	exit 127
fi

# Import once so the class cache and .import files are current. Without this the
# first suite pays for it and can report spurious parse errors.
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

failed=0
for suite in "${SUITES[@]}"; do
	scene="${suite%%|*}"
	label="${suite##*|}"
	printf '\n=== %s ===\n' "$label"

	"$GODOT" --headless --path "$ROOT" "$scene" >"$log" 2>&1
	status=$?

	grep -E '^  FAIL|^=== [0-9]+ passed' "$log"

	if [ "$status" -ne 0 ]; then
		echo "FAILED (exit $status): $label"
		grep -E 'SCRIPT ERROR|Parse Error' "$log" | head -5
		failed=1
	fi
done

# The budget check is last and is not headless: it reads the renderer's own
# counters after a frame has actually been drawn, and a headless run draws
# nothing. It is here rather than left to be remembered because the village went
# 70% over the triangle budget in a single afternoon of art work, and nothing
# said so until it was measured.
echo
echo "=== village performance budget ==="
"$GODOT" --path "$ROOT" res://tools/scene_budget.tscn -- hub >"$log" 2>&1
status=$?
grep -E '^  (draw calls|triangles)|^=== (within|OVER)' "$log"
if [ "$status" -ne 0 ]; then
	echo "OVER BUDGET (PLAN.md 4.2)"
	failed=1
fi

printf '\n'
if [ "$failed" -eq 0 ]; then
	echo "All suites passed."
else
	echo "Some suites failed. Re-run one on its own to see every check:"
	echo "  \"\$GODOT\" --headless --path . res://tools/<suite>.tscn"
fi
exit "$failed"
