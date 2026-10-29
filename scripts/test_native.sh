#!/usr/bin/env bash
# Builds and runs the standalone doctest suite (no Godot, no godot-cpp).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/native-tests"
mkdir -p "$BUILD"

CXX="${CXX:-g++}"
SRCS=(
	"$ROOT/native/src/thermal/thermal_core.cpp"
	"$ROOT/native/tests/test_thermal.cpp"
)

"$CXX" -std=c++17 -O2 -g -Wall -Wextra -Werror \
	-I"$ROOT/native/src" -I"$ROOT/thirdparty" \
	-o "$BUILD/thermal_tests" "${SRCS[@]}"

"$BUILD/thermal_tests" --no-version "$@"
