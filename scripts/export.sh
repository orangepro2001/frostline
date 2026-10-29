#!/usr/bin/env bash
# Headless export with Godot.
#
#   scripts/export.sh <windows|android> <debug|release> [output-dir]
#
# Linux (WSL2) exports Windows binaries directly; it also exports Android once
# the SDK is configured. Android signing material is read from the environment
# and is never written into the repository:
#
#   FROSTLINE_KEYSTORE         path to the keystore
#   FROSTLINE_KEYSTORE_USER    keystore user
#   FROSTLINE_KEYSTORE_PASS    keystore password
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="${1:?usage: export.sh <windows|android> <debug|release> [out-dir]}"
MODE="${2:?usage: export.sh <windows|android> <debug|release> [out-dir]}"
OUT_DIR="${3:-$ROOT/build/export}"

GODOT_BIN="${GODOT:-godot}"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.1.0)"
mkdir -p "$OUT_DIR"

case "$PLATFORM-$MODE" in
	windows-release) PRESET="Windows Desktop";   FILE="$OUT_DIR/frostline-${VERSION}-win-x64.zip" ;;
	windows-debug)   PRESET="Windows Desktop";   FILE="$OUT_DIR/frostline-${VERSION}-win-x64-debug.zip" ;;
	android-release) PRESET="Android";           FILE="$OUT_DIR/frostline-${VERSION}-android.aab" ;;
	android-debug)   PRESET="Android";           FILE="$OUT_DIR/frostline-${VERSION}-android.apk" ;;
	*) echo "unknown platform/mode: $PLATFORM $MODE" >&2; exit 2 ;;
esac

# Signing is injected at export time, never stored in export_presets.cfg.
if [[ "$PLATFORM" == android && -n "${FROSTLINE_KEYSTORE:-}" ]]; then
	export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$FROSTLINE_KEYSTORE"
	export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${FROSTLINE_KEYSTORE_USER:-}"
	export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${FROSTLINE_KEYSTORE_PASS:-}"
	echo "==> signing with $FROSTLINE_KEYSTORE"
fi

# The export path is derived per mode: debug APK vs release AAB.
PATH_OVERRIDE="--export-path=$FILE"
if [[ "$PLATFORM" == windows ]]; then
	# Windows presets export a directory/zip; let the preset decide the name and
	# zip the result afterwards for a stable artifact name.
	PATH_OVERRIDE="--export-path=$OUT_DIR/frostline-win-x64"
fi

FLAG="--export-release"
[[ "$MODE" == debug ]] && FLAG="--export-debug"

# Import first: a fresh checkout has no .godot/ and export would fail.
"$GODOT_BIN" --headless --editor --quit --path "$ROOT/game" >/dev/null 2>&1 || true

echo "==> $GODOT_BIN $FLAG \"$PRESET\" $PATH_OVERRIDE"
"$GODOT_BIN" --headless --path "$ROOT/game" "$FLAG" "$PRESET" "$PATH_OVERRIDE"

if [[ "$PLATFORM" == windows ]]; then
	if [[ -d "$OUT_DIR/frostline-win-x64" ]]; then
		rm -f "$FILE"
		(cd "$OUT_DIR/frostline-win-x64" && zip -qr "$FILE" .)
	fi
fi

if [[ ! -s "$FILE" ]]; then
	echo "export produced no artifact at $FILE" >&2
	exit 1
fi
echo "==> $FILE ($(du -h "$FILE" | cut -f1))"
