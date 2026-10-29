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
		# llvm-mingw is preferred (no MSVC anywhere in the toolchain). Its tools
		# are `x86_64-w64-mingw32-clang++`, and godot-cpp picks them up through
		# MINGW_PREFIX when `use_mingw=yes` is set.
		if command -v x86_64-w64-mingw32-clang++ >/dev/null 2>&1; then
			export MINGW_PREFIX=x86_64-w64-mingw32
		elif command -v llvm-mingw-ucrt-x86_64-g++ >/dev/null 2>&1; then
			export MINGW_PREFIX=llvm-mingw-ucrt-x86_64
		else
			export MINGW_PREFIX="${MINGW_PREFIX:-x86_64-w64-mingw32}"
		fi
		SCONS_ARGS+=(arch=x86_64 use_mingw=yes)
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
