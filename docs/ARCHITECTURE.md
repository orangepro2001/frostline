# Architecture

Frostline is a 2D top-down survival game about heat. This document describes how
the pieces fit, what each one owns, and where the next milestone plugs in.

## 1. Layers

```text
                 ┌───────────────────────────────┐
                 │ ui/            HUD, build menu │
                 └───────────────┬───────────────┘
                                 │ EventBus (typed signals)
┌────────────────────────────────┴──────────────────────────────┐
│ entities/  player, interactables      world/  map, rooms       │
└────────────────────────────────┬──────────────────────────────┘
                                 │ direct calls, no node paths
┌────────────────────────────────┴──────────────────────────────┐
│ systems/  thermal · body · fuel · weather · building           │
│ autoload/ GameClock · Rng · GameState · SaveSystem · Settings  │
└────────────────────────────────┬──────────────────────────────┘
                                 │ narrow, batch-oriented API
┌────────────────────────────────┴──────────────────────────────┐
│ GDExtension: FrostlineThermalGrid  (C++, native/src)           │
│   └── frostline::ThermalGrid  (pure C++, no engine dependency) │
└───────────────────────────────────────────────────────────────┘
```

Rules that keep the layers honest:

1. **Simulation and presentation are separate.** Gameplay state lives in plain
   data (resources, typed arrays, the native grid); nodes only render and take
   input.
2. **Fixed steps.** The thermal grid advances at 10 Hz from accumulated real
   time; movement and physics use `_physics_process` at 60 Hz; rendering follows
   the display. `GameClock` owns time scaling, so no system reads wall-clock
   time directly.
3. **Determinism.** All randomness comes from `Rng.stream(name)`; `randf()` and
   `randi()` are forbidden in gameplay code. A seed plus an input sequence
   reproduces a run.
4. **Data drives balance.** Items, fuels, materials, difficulty live in
   `data_src/*.csv`, are converted by `tools/tablegen` into `game/data/*.tres`,
   and are never hand-edited.
5. **Cross-system communication goes through `EventBus`** with typed signals;
   within one entity, components hold direct references.

## 2. The thermal grid

`native/src/thermal/thermal_core.{h,cpp}` is plain C++17 and is compiled twice:
into the GDExtension and into the doctest binary. That split is deliberate — the
simulation can be tested on a machine with no engine and no display.

Model: a lumped RC network on a grid. Each cell has a temperature, a material id
and an `exposed` flag. Per tick, every shared edge is evaluated **once** and the
same joule amount is added to one cell and removed from the other, so the scheme
conserves energy exactly up to float32 rounding regardless of how different the
two materials are. Exposed cells relax towards `ambient + wind_chill`.

The forward-Euler step is stable while `dt * Σk / C ≤ 1`; `step()` computes the
worst cell and splits the tick into equal sub-steps. `step_active()` skips a grid
in which nothing is moving (no exposed cell, no live source, all neighbours
within 1e-3 °C).

`native/src/thermal/thermal_grid.{h,cpp}` is the thin Godot binding. It exposes
only batch operations (`set_material_rect`, `set_exposed_rect`, `add_heat_source`,
`step`, `get_temperatures`) so the GDScript side never loops per cell.

**Measured budget.** 128×128, one 0.1 s tick: **≈0.44 ms** on the dev machine
(`scripts/test_native.sh` prints it). The budget is 0.5 ms desktop, 2 ms on a
mid-range Snapdragon.

## 3. Time, randomness, saving

| Autoload | Owns | Notes |
|---|---|---|
| `GameClock` | game day/minute, speed (1×/2×/4×), pause | one day = `seconds_per_day` (12 min) |
| `Rng` | one seeded stream per domain | `hash_combine(seed, stream)`; snapshots for saves |
| `GameState` | mode, difficulty, seed, days survived | plain data, no nodes |
| `SaveSystem` | binary saves with a version header | temp file + rename, atomic |
| `Settings` | overlay toggle, volume | emits `changed` |

Save format: `magic "FROS" | u32 version | u32 length | payload`, where the
payload is `var_to_bytes` of a dictionary (`clock`, `rng`, `game_state`). M0
saves the clock, the RNG state and the run descriptor; the thermal grid, player,
buildings and inventory are added with their systems.

## 4. Modes and difficulty

`modes/` holds `GameMode` (start, win/lose, save policy) with `SandboxMode` in the
prototype. `DifficultyProfile` is a resource with cooling rate, resource
multiplier, forecast error, event frequency and save mode, generated from
`data_src/difficulty.csv`. Nothing in the gameplay code branches on a difficulty
*name*; it reads fields.

The randomness / anti-deadlock / DDA contract is in
[GAMEPLAY_RANDOMNESS.md](GAMEPLAY_RANDOMNESS.md).

## 5. Extension points

| Milestone | Plugs in at |
|---|---|
| M1 overlay | `systems/thermal/thermal_overlay.gd` samples `get_temperatures()` into a `FORMAT_RF` image |
| M2 body heat | `systems/body/` reads the player cell temperature from the grid |
| M2 fuel | `systems/fuel/` maps `FuelDef` to watts for `set_heat_source_power` |
| M3 building | `systems/building/` calls `set_material_rect` / `set_exposed_rect` |
| M4 weather | `systems/weather/` drives `set_ambient(temp, wind_chill)` |
| Story mode | `modes/story_mode.gd` + authored chapter data (deterministic domain) |
| Endless mode | `modes/endless_mode.gd` + `layout`/`loot` streams + perk pool |

## 6. Build and CI

`scripts/` is the only supported entry point:

| Script | Does |
|---|---|
| `setup.sh` | checks/points at Godot, SCons, compilers, NDK, JDK, LFS |
| `build_native.sh <platform> <debug|release>` | SCons, copies the library into `game/bin` |
| `test_native.sh` | compiles and runs doctest (no engine needed) |
| `run_tests.sh` | doctest + tablegen `--check` + Godot import + smoke + gdUnit4 |
| `export.sh <windows|android> <debug|release>` | headless export, signing from env |

CI (`.github/workflows/ci.yml`) runs on GitHub-hosted runners: the engine binary
needs glibc ≥ 2.28, which `ubuntu-latest` has. A tag `v*` additionally exports
Windows and publishes to release-publish (`relhub`) with an app-scoped token.

## 7. Known gaps (M0)

- The Android export path is written but has not run in CI (no SDK in the
  pipeline); it runs on the build machine with `scripts/export.sh`.
- `gradle_build/use_gradle_build=true` is required for arm64 AAB; the template
  has to be installed once with `--install-android-build-template`.
- The overlay is a debug `_draw()` in `scenes/main.gd`, not the shader described
  in the brief; it moves to a shader in M1.
