#!/usr/bin/env bash
# Checks (and, with --install, installs what it can) the tools the Frostline
# pipeline needs. Runs on WSL2 and on the headless build server.
set -uo pipefail

INSTALL="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
missing=()

have() { command -v "$1" >/dev/null 2>&1; }
note() { printf '  %-14s %s\n' "$1" "$2"; }
ok()   { printf '\033[32m  ok\033[0m   %-12s %s\n' "$1" "$2"; }
bad()  { printf '\033[31m  MISS\033[0m %-12s %s\n' "$1" "$2"; }

echo "frostline toolchain check"
echo

# --- Godot 4.7.x (must match docs/VERSIONS.md exactly) ---
GODOT_BIN="${GODOT:-godot}"
if have "$GODOT_BIN"; then
	ver="$("$GODOT_BIN" --version 2>/dev/null | head -1)"
	if [[ "$ver" == 4.7.* ]]; then ok godot "$ver"; else bad godot "$ver (need 4.7.x)"; fail=1; fi
else
	bad godot "not found (get Godot_v4.7.2-stable_linux.x86_64, put it in PATH or set GODOT)"; fail=1
fi

# --- SCons (godot-cpp build) ---
if have scons; then ok scons "$(scons --version 2>/dev/null | sed -n 's/.*Script: v//p' | head -1)"
else
	bad scons "install with: pipx install scons"; missing+=("pipx install scons"); fail=1
fi

# --- C++ compiler for the standalone doctest build ---
if have "${CXX:-g++}"; then ok g++ "$("${CXX:-g++}" --version | head -1)"
else bad g++ "install build-essential"; missing+=("sudo apt install build-essential"); fail=1
fi

# --- Go (data tools) ---
if have go; then ok go "$(go version | awk '{print $3}')"
else bad go "install Go 1.24+"; missing+=("sudo apt install golang-go"); fail=1
fi

# --- Windows cross toolchain (llvm-mingw preferred) ---
if have x86_64-w64-mingw32-g++; then ok mingw "$(x86_64-w64-mingw32-g++ --version | head -1)"
elif have x86_64-w64-mingw32-llvm-g++; then ok llvm-mingw "$(x86_64-w64-mingw32-llvm-g++ --version | head -1)"
else bad mingw "scripts/fetch_llvm_mingw.sh (llvm-mingw) or: sudo apt install mingw-w64"; missing+=("scripts/fetch_llvm_mingw.sh"); fail=1
fi

# --- Android (export only) ---
if [[ -n "${ANDROID_NDK_ROOT:-}" && -d "${ANDROID_NDK_ROOT:-}" ]]; then
	ok ndk "${ANDROID_NDK_ROOT}"
elif [[ -d "${ANDROID_HOME:-$HOME/Android/Sdk}/ndk" ]]; then
	ok ndk "$(ls "${ANDROID_HOME:-$HOME/Android/Sdk}/ndk" | tail -1) (set ANDROID_NDK_ROOT to build native android)"
else
	bad ndk "set ANDROID_HOME / ANDROID_NDK_ROOT"
fi
if have java; then ok java "$(java -version 2>&1 | head -1)"
else bad java "install a JDK 17 (Godot Android export)"; missing+=("sudo apt install openjdk-17-jdk"); fail=1
fi

# --- Export templates ---
tpl="${HOME}/.local/share/godot/export_templates"
if [[ -d "$tpl" ]]; then ok templates "$(ls "$tpl")"
else bad templates "install Godot 4.7.2 export templates (Editor > Manage Export Templates)"; fail=1
fi

# --- Git LFS ---
if have git-lfs; then ok git-lfs "$(git lfs version | awk '{print $1}')"
else bad git-lfs "sudo apt install git-lfs"; missing+=("sudo apt install git-lfs"); fail=1
fi

echo
if (( fail == 0 )); then
	echo "All required tools are present."
else
	echo "Some tools are missing."
	if [[ "$INSTALL" == "--install" && ${#missing[@]} -gt 0 ]]; then
		printf '  try: %s\n' "${missing[@]}"
	fi
fi
exit "$fail"
