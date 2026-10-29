# Frostline

A 2D top-down winter survival prototype. The enemy is the cold, not a monster.

**Status: M0 — engineering skeleton.** One fixed map, one room, a thermal grid
that actually simulates heat leaking through walls. No gameplay loop yet.

## What exists

- **Pure C++ thermal core** (`native/src/thermal/thermal_core.*`): energy-conserving
  grid, per-material insulation, wind chill, heat sources, sub-stepping and an
  active-set skip. ≈0.44 ms per tick at 128×128.
- **GDExtension** exposing it to GDScript (`FrostlineThermalGrid`).
- **Godot 4.7.2 project**, Compatibility renderer, 480×270 base resolution,
  integer scaling, strict GDScript warnings (untyped declarations are errors).
- **Deterministic RNG streams**, a game clock, and versioned atomic saves.
- **Data pipeline**: `data_src/*.csv` → `tools/tablegen` → `game/data/*.tres`.
- **Tests**: doctest for C++, gdUnit4 for GDScript, plus a native-load smoke test.

## Layout

```
game/      Godot project (project.godot lives here)
native/    C++ GDExtension; godot-cpp is a submodule
tools/     Go: tablegen (CSV -> .tres)
data_src/  design spreadsheets
scripts/   setup, build, test, export
docs/      ARCHITECTURE, VERSIONS, GAMEPLAY_RANDOMNESS
```

## Requirements

Godot 4.7.x, SCons, a C++17 compiler, Go 1.24+, git-lfs. Android exports also
need the SDK/NDK and a JDK 17. `scripts/setup.sh` checks all of it and tells you
what is missing.

## Build and test

```sh
git clone --recurse-submodules git@github.com:orangepro2001/frostline.git
cd frostline
./scripts/setup.sh                       # check the toolchain
./scripts/build_native.sh linux debug    # build + install the extension
./scripts/run_tests.sh                   # doctest + data check + gdUnit4
godot --path game                        # run it (needs a display)
```

Run the game headless to smoke-test the extension:

```sh
godot --headless --path game --script res://tests/smoke/native_smoke.gd
```

## Export

```sh
./scripts/export.sh windows release build/export
```

Android needs the SDK, NDK and a keystore; signing values come from the
environment (`FROSTLINE_KEYSTORE`, `FROSTLINE_KEYSTORE_USER`,
`FROSTLINE_KEYSTORE_PASS`) and are never committed.

## CI and releases

GitHub Actions runs on `ubuntu-latest`: the C++ tests, the data check, the
GDExtension build and the Godot test suite. Pushing a `v*` tag also exports
Windows and publishes to the release server:

```sh
git tag -a v0.1.0 -m "..." && git push origin v0.1.0
```

Releases are served at `https://tony-ai-pc-1.tail9f7f1f.ts.net/release/` (an
app-scoped token lives in the repository secrets; the publishing step uses it).

## Versions

Exact versions and where they were read from: [docs/VERSIONS.md](docs/VERSIONS.md).

## License

Not decided yet. Do not assume it is open source until `LICENSE` exists.
