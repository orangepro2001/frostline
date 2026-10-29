# Versions

Every version below was taken from the actual binary or tag that the pipeline
uses, not from a plan. `godot --version` and `git describe` in this repository
must reproduce these strings.

| Component | Version | Where it comes from | Verified with |
|---|---|---|---|
| Godot engine | `4.7.2.stable.official.ed1daf0bf` | [releases](https://github.com/godotengine/godot/releases/tag/4.7.2-stable), `Godot_v4.7.2-stable_linux.x86_64.zip` | `godot --version` |
| Export templates | `4.7.2.stable` | `Godot_v4.7.2-stable_export_templates.tpz` | `~/.local/share/godot/export_templates/4.7.2.stable/` |
| godot-cpp | `10.0.0-stable` (submodule) | [godot-cpp](https://github.com/godotengine/godot-cpp/releases/tag/10.0.0-stable) | `git -C native/godot-cpp describe --tags` |
| GDExtension API target | `4.7` | `api_version=4.7`, matches godot-cpp's `gdextension/extension_api-4-7.json` | SCons argument in `native/SConstruct` |
| SCons | `4.11.1` | `pipx install scons` | `scons --version` |
| C++ for tests | g++ `15.2.0` (C++17) | Ubuntu 26.04 host | `g++ --version` |
| Go | `1.27.2` (tools), CI pins `1.24` | mise / actions/setup-go | `go version` |
| doctest | `2.5.3` (vendored header) | `thirdparty/doctest.h` | file header |
| gdUnit4 | `6.2.2` (vendored addon) | `game/addons/gdUnit4` | `plugin.cfg` |
| llvm-mingw | `20261020` (CI), `GCC 13-win32` MinGW fallback on the build host | [llvm-mingw releases](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261020) | `x86_64-w64-mingw32-clang++ --version` |
| Android NDK | `28.2.13676358` | `~/Android/Sdk/ndk` on tony-ai-pc-1 | `source.properties` |
| Android SDK platform | `android-35`, build-tools `34.0.0` / `35.0.0` | Android SDK on tony-ai-pc-1 | `sdkmanager --list` |
| JDK | OpenJDK `17.0.20.1` | tony-ai-pc-1 | `java -version` |

## Notes

- **godot-cpp changed its versioning scheme.** Releases up to `godot-4.5-stable`
  were named after the engine; starting with `10.0.0` godot-cpp is versioned
  independently and targets Godot 4.3+ through the `api_version` SCons option.
  There is no `4.6`/`4.7` branch — `10.0.0-stable` *is* the 4.7 binding.
- **The engine needs glibc ≥ 2.28 only** (`objdump -T` on the binary), which is
  why GitHub's `ubuntu-latest` runs it and no self-hosted runner is needed for
  tests.
- The Android SDK/NDK are **not** installed in the WSL2 dev box; Android exports
  run on tony-ai-pc-1 or in a CI image that installs the SDK.
- Version bumps are a two-file change: `VERSION` and this table, plus the
  submodule tag. Do not record a version that `--version` does not print.
