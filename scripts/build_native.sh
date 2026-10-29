#!/usr/bin/env bash
# Builds the GDExtension for one platform/target and installs it into game/bin.
#
#   scripts/build_native.sh <linux|windows|android> <debug|release> [--no-copy]
#
# Environment:
#   FROSTLINE_NATIVE_VERSION  version string compiled into NativeHello
#   MINGW_PREFIX              cross prefix for windows (default x86_64-w64-mingw32)
#   ANDROID_NDK_ROOT          NDK root for android builds
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="${1:?usage: build_native.sh <linux|windows|android> <debug|release> [--no-copy]}"
TARGET_ARG="${2:?usage: build_native.sh <linux|windows|android> <debug|release> [--no-copy]}"
COPY=1
[[ "${3:-}" == "--no-copy" ]] && COPY=0

case "$TARGET_ARG" in
	debug)   SCONS_TARGET=template_debug ;;
	release) SCONS_TARGET=template_release ;;
	*) echo "target must be debug or release" >&2; exit 2 ;;
esac

JOBS="${JOBS:-$(nproc)}"
SCONS_ARGS=(platform="$PLATFORM" target="$SCONS_TARGET" api_version=4.7 "-j${JOBS}")

case "$PLATFORM" in
	linux)
		SCONS_ARGS+=(arch=x86_64)
		LIB="libfrostline.so"
		ARTIFACT="libfrostline.so.linux.${SCONS_TARGET}"
		;;
	windows)
		export MINGW_PREFIX="${MINGW_PREFIX:-x86_64-w64-mingw32}"
		if ! command -v "${MINGW_PREFIX}-g++" >/dev/null 2>&1 && ! command -v "${MINGW_PREFIX}-llvm-g++" >/dev/null 2>&1; then
			echo "note: ${MINGW_PREFIX} g++ not found; godot-cpp will try the next available toolchain" >&2
		fi
		SCONS_ARGS+=(arch=x86_64 use_mingw=yes)
		# llvm-mingw ships its own windres/lld; point scons at them when present.
		if command -v "${MINGW_PREFIX}-windres" >/dev/null 2>&1; then
			export WINDRES="${MINGW_PREFIX}-windres"
		fi
		LIB="libfrostline.dll"
		ARTIFACT="libfrostline.dll.windows.${SCONS_TARGET}"
		;;
	android)
		: "${ANDROID_NDK_ROOT:?ANDROID_NDK_ROOT must be set for android builds}"
		SCONS_ARGS+=(arch=arm64)
		LIB="libfrostline.so"
		ARTIFACT="libfrostline.so.android.${SCONS_TARGET}"
		;;
	*) echo "platform must be linux, windows or android" >&2; exit 2 ;;
esac

echo "==> scons ${SCONS_ARGS[*]}"
(cd "$ROOT/native" && FROSTLINE_NATIVE_VERSION="${FROSTLINE_NATIVE_VERSION:-frostline-native/${TARGET_ARG}}" \
	scons "${SCONS_ARGS[@]}")

if (( COPY )); then
	mkdir -p "$ROOT/game/bin"
	cp "$ROOT/native/bin/${ARTIFACT}" "$ROOT/game/bin/${ARTIFACT}"
	echo "==> installed game/bin/${ARTIFACT}"
fi
