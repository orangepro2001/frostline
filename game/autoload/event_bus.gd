extends Node
## Typed signal hub. Systems never reach into each other's node paths; they
## publish state changes here and whoever cares subscribes.
##
## Signals are declared with explicit parameter types on purpose: the project
## treats untyped declarations as errors.

signal tick_heat(dt: float)

signal clock_minute_changed(game_minute: int)
signal clock_hour_changed(game_hour: int)
signal clock_day_changed(game_day: int)
signal clock_speed_changed(speed: float)

signal ambient_changed(temperature_c: float, wind_chill_c: float)

signal player_body_temp_changed(celsius: float, stage: int)
signal player_died(cause: String)

signal heat_source_fuel_changed(source_id: int, fuel_seconds_left: float)
signal heat_source_extinguished(source_id: int)

signal build_mode_changed(active: bool)
signal structure_changed(cell: Vector2i, structure_id: String)

signal weather_changed(kind: String, intensity: float)
signal forecast_ready(day: int, low_c: float, high_c: float)

signal game_mode_started(mode_id: String)
signal game_over(won: bool, reason: String)
