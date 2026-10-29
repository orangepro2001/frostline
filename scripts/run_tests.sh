#!/usr/bin/env bash
# Runs every test in the project. Exit code 0 means everything passed.
#
#   scripts/run_tests.sh            # doctest + tablegen check + gdUnit4
#   scripts/run_tests.sh --fast     # doctest only (no engine needed)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAST=0
[[ "${1:-}" == "--fast" ]] && FAST=1
GODOT_BIN="${GODOT:-godot}"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

step "C++ core (doctest)"
"$ROOT/scripts/test_native.sh"

if (( FAST )); then
	echo "fast mode: skipping Godot tests"
	exit 0
fi

step "generated data is up to date"
(cd "$ROOT/tools" && go run ./cmd/tablegen -root "$ROOT" -check)

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "GODOT not found: set GODOT=/path/to/godot or skip with --fast" >&2
	exit 1
fi

step "Godot import (also refreshes the GDExtension list)"
# The editor writes .godot/extension_list.cfg, which is what makes a headless
# run load the compiled extension. A plain `--headless --quit` game run does not
# do this, so it must come first on a fresh checkout.
"$GODOT_BIN" --headless --editor --quit --path "$ROOT/game" >/dev/null 2>&1 || {
	echo "editor import failed" >&2
	exit 1
}

step "native extension smoke test"
"$GODOT_BIN" --headless --path "$ROOT/game" --script res://tests/smoke/native_smoke.gd | tee /dev/stderr | grep -q "SMOKE RESULT: PASS"

step "GDScript (gdUnit4)"
set +e
"$GODOT_BIN" --headless --path "$ROOT/game" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
	--ignoreHeadlessMode -a res://tests
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
	echo "gdUnit4 failed with exit code $rc" >&2
	exit "$rc"
fi

printf '\n\033[32mall tests passed\033[0m\n'
