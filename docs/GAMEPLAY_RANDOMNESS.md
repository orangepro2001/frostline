# Core loop: randomness, anti-deadlock, and dynamic difficulty

This is the design contract for M5+ (endless mode, difficulty system). It
answers one question: **how does Frostline stay fresh without ever producing a
run that cannot be survived?**

Everything here is a *rule with parameters*, because the project forbids
hard-coded balance numbers: the values live in `data_src/*.csv` and are
generated into `game/data/*.tres` by `tools/tablegen`.

---

## 1. Two kinds of certainty

The most common failure of a "randomised survival game" is that a random roll
puts the one item you need behind an unlucky seed. Frostline splits the world in
two and never lets the lines cross.

| | Deterministic domain | Random domain |
|---|---|---|
| Contents | chapter key items, map spine (roads, river, shelter), tutorial level, safehouse shell | loot in containers, weather sequence, events, interior layout of non-key buildings |
| Driven by | hand-authored scene/data files | named RNG streams |
| Reproducible? | by construction | by seed |
| May be changed by a random roll? | **no — hard constraint** | n/a |

**Hard constraint (H1).** A chapter key item, the map spine and the tutorial
level are authored data. They are loaded, never generated. The generation code
has no reference to them, and a runtime assertion checks that no generated
object claims a cell or an id reserved by the deterministic layer.

This is what makes a walkthrough possible: a guide can say "the generator parts
are in the flooded basement on the north road" and be right in every run.

## 2. Random streams

Each domain owns an independent stream; drawing from one never advances another.

```gdscript
# core/rng.gd (implemented in M0)
stream_seed = hash_combine(run_seed, stream_name)   # stable 64-bit mix
```

| Stream | Used for | Frequency |
|---|---|---|
| `loot` | container contents, junk piles, corpse finds | per container, on first open |
| `weather` | daily temperature curve jitter, blizzard onset | once per game day |
| `events` | wandering trader, radio broadcast, structural damage | per event window |
| `layout` | interior walls, furniture placement of non-key buildings | once per building, at world build |
| `spawn` | animals, drifter NPCs (post-prototype) | per spawn window |
| `cosmetic` | wind particles, snow drift — must never affect gameplay | per frame |

**Rule (R1).** Draw order within a stream is fixed by the code path, not by
frame timing: a container is rolled when it is *first opened*, never when the
world loads. This keeps the stream position independent of how fast the player
walks.

**Rule (R2).** `cosmetic` may be consumed freely; a save never stores its state,
so a resumed run may look different but can never *play* differently.

## 3. Anti-deadlock: the mercy rule

The player can reach a state with no fuel, no food and a dying body. Losing is
fine; being *stuck* is not. The mercy rule provides a floor, and is deliberately
unprofitable so that it cannot be farmed.

### 3.1 Trigger

All of the following, sampled once per game hour:

- `fuel_minutes < mercy_fuel_threshold_min` (default 20 min of burn time left in
  the whole shelter), **and**
- `food_days < mercy_food_threshold_days` (default 0.5 day), **and**
- the player has not triggered the mercy rule in the last `mercy_cooldown_hours`
  (default 20 game hours), **and**
- `mercy_uses_this_run < mercy_max_uses` (default 2).

### 3.2 What it gives

A single "salvage cache" spawns **at least two rooms away** from the player, in a
building the player has already visited (so it is reachable without a map
reveal). Contents: one low-tier fuel item (2 h burn time) and one low-tier food
item (0.5 day). Never a tool, never a key item, never a weapon upgrade.

### 3.3 Why it cannot be farmed

The value has to be *below the expected value of normal play*, or players will
optimise for the cache instead of for exploring.

| | Mercy cache | Normal 10-minute scavenging run |
|---|---|---|
| Fuel | 2 h burn | 4–7 h burn (2–3 containers) |
| Food | 0.5 day | 1.0–1.5 day |
| Risk | time spent walking, no heat | same, plus exposure |
| Cooldown | 20 h | n/a |

Per real-time hour of play the cache yields roughly **1/3** of a normal run, and
it arrives only after the player has already spent the reserves that a normal
run would have kept. Three further rules close the obvious exploits:

- **Decay (R3).** Each use in a run multiplies the next cache's contents by
  `mercy_decay_mult` (default 0.6). Two uses is the cap; a third never comes.
- **No stockpiling (R4).** The trigger samples *current* fuel, so hoarding fuel
  prevents the trigger entirely. Sitting on a full woodpile and starving is not
  a strategy the rule rewards.
- **Cold debt (R5).** Triggering the rule applies `mercy_cold_debt_c` (default
  −1.5 °C) to the next night's ambient curve. The rescue costs something.

## 4. Dynamic difficulty (DDA)

### 4.1 The mistake to avoid

"More days survived → colder nights" is the naive design and it is wrong: it
makes the game harder precisely for the players who are doing well, which reads
as punishment. Frostline regulates **relative** performance instead.

### 4.2 Signals

Sampled once per game day, normalised to 0..1:

| Signal | Definition | Weight |
|---|---|---|
| `s_body` | day's minimum core body temperature, mapped from 36.5 °C → 0, 34.0 °C → 1 | 0.40 |
| `s_fuel` | fuel burned per degree-hour of warmth delivered, vs. the table's ideal | 0.25 |
| `s_progress` | rooms explored / rooms available this day | 0.20 |
| `s_death` | deaths in the last 3 days (0, 0.5, 1) | 0.15 |

```text
pressure_raw = w_body*s_body + w_fuel*s_fuel + w_progress*(1-s_progress) + w_death*s_death
pressure_ema = ema_alpha*pressure_raw + (1-ema_alpha)*pressure_ema   # alpha 0.25
```

`ema_alpha` 0.25 means roughly a four-day memory: one bad night moves the dial,
a bad week moves it a lot.

### 4.3 Actuation

`pressure_ema` drives one visible number, the **cold bias**:

```text
target_bias   = lerp(bias_min, bias_max, pressure_ema)      # -1.5 .. +2.0 °C
cold_bias     = move_toward(cold_bias, target_bias, bias_rate_per_day)  # 0.4 °C/day
```

It is clamped, rate-limited, and applied to the *ambient curve*, never to the
player's body temperature directly.

Loot density and blizzard frequency are **not** driven by the DDA. They follow
the difficulty profile (a static parameter set from `data_src/difficulty.csv`),
because a world whose contents shift under the player is impossible to learn and
impossible to write a guide for.

### 4.4 Why it does not punish skill

- A skilled player keeps `s_body` low (warm), `s_fuel` low (efficient) and
  `s_progress` high, so `pressure_raw` **falls** and the bias goes *negative*:
  the game gets slightly easier until the player is under real pressure again.
- The bias saturates at ±1.5–2.0 °C, which is under one clothing tier: skill
  still dominates.
- It moves at most 0.4 °C per day, so it can never turn a survivable night into
  a death without a day of warning — and the radio forecast reports it.

## 5. Freshness in endless mode

Endless mode draws `perk_count` (default 3) **modifiers** at run start from a
weighted pool, then adds one more at each `perk_interval_days` (default 5).

- **Weighting.** Base weight per modifier × `scarcity_mult` for modifiers that
  have not appeared in the last `perk_cooldown_runs` (default 3) runs.
- **Mutual exclusion.** Modifiers carry tags; tags in the same group cancel
  (`calm`/`stormy`, `abundant`/`scarce`). The draw rejects a conflicting pick and
  redraws, with a hard cap of `perk_draw_attempts` (default 20) before giving up
  and shipping one fewer modifier.
- **Effect budget.** Every modifier declares a `budget` in "difficulty points";
  a run may not exceed `perk_budget_total` (default 4). This bounds the
  combination space far more effectively than limiting the item count.
- **Stream.** Modifier draws use `events`, not `loot`, so a lucky loot roll can
  never change which modifiers the run gets.

## 6. Testability

The whole design exists to be asserted on:

| ID | Precondition | Input | Expected |
|---|---|---|---|
| T1 | run seed S | generate a world twice | byte-identical layout and loot |
| T2 | seed S | open containers in a different order | same per-container results (R1) |
| T3 | seed S | draw from `weather` 100 times | `loot` stream position unchanged |
| T4 | chapter 2 loaded | any seed | every key item present at its authored cell |
| T5 | fuel 10 min, food 0.3 d, cooldown elapsed | advance 1 h | cache spawns ≥2 rooms away |
| T6 | as T5, then trigger again immediately | advance 1 h | no second cache (cooldown) |
| T7 | mercy used twice | advance 100 h | no third cache |
| T8 | 10 h of normal scavenging | compare | fuel+food value > 3× a mercy cache |
| T9 | pressure 0.0 | 30 simulated days of good play | `cold_bias` ≤ 0 and stable |
| T10 | pressure 1.0 | 30 simulated days | `cold_bias` ≤ bias_max and never exceeds rate limit |
| T11 | any state | random 10 000 actions | no state with zero reachable fuel and food (invariant) |
| T12 | endless run | draw modifiers 1 000 times | never two conflicting tags, never over budget |

## 7. Parameters

| Field | Type | Default | Range | Unit |
|---|---|---|---|---|
| `mercy_fuel_threshold_min` | float | 20 | 0–120 | game minutes |
| `mercy_food_threshold_days` | float | 0.5 | 0–3 | days |
| `mercy_cooldown_hours` | float | 20 | 1–48 | game hours |
| `mercy_max_uses` | int | 2 | 0–5 | count |
| `mercy_decay_mult` | float | 0.6 | 0.1–1.0 | ratio |
| `mercy_cold_debt_c` | float | 1.5 | 0–5 | °C |
| `ema_alpha` | float | 0.25 | 0.05–0.6 | ratio |
| `bias_min` / `bias_max` | float | −1.5 / 2.0 | −3–3 | °C |
| `bias_rate_per_day` | float | 0.4 | 0.05–1.0 | °C/day |
| `perk_count` | int | 3 | 1–5 | count |
| `perk_interval_days` | int | 5 | 1–15 | days |
| `perk_cooldown_runs` | int | 3 | 0–10 | runs |
| `perk_budget_total` | int | 4 | 1–10 | points |
| `perk_draw_attempts` | int | 20 | 1–100 | count |

## 8. Open questions

- Should `s_progress` count *new* rooms only, or any room revisited after dark?
  Counting revisits rewards thorough play but makes the signal noisy.
- The cold debt (R5) is currently flat. A debt proportional to how far the player
  fell below the floor would be fairer but much harder to explain in a HUD line.
