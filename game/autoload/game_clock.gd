extends Node
## Deterministic game clock. One game day is `seconds_per_day` real seconds by
## default (12 minutes). Supports pause and 1x / 2x / 4x acceleration.
##
## Everything that advances with time asks this node, never Time.get_ticks().

const MINUTES_PER_DAY: int = 24 * 60

@export var seconds_per_day: float = 12.0 * 60.0

var day: int = 0
var minute: int = 0
var speed: float = 1.0
var paused: bool = false

var _accumulator: float = 0.0
var _minutes_per_second: float = 0.0


func _ready() -> void:
	_minutes_per_second = float(MINUTES_PER_DAY) / seconds_per_day


func _process(delta: float) -> void:
	if paused:
		return
	_accumulator += delta * speed * _minutes_per_second
	if _accumulator < 1.0:
		return
	var whole: int = int(_accumulator)
	_accumulator -= float(whole)
	_advance_minutes(whole)


func _advance_minutes(p_minutes: int) -> void:
	var previous_hour: int = hour()
	minute += p_minutes
	while minute >= MINUTES_PER_DAY:
		minute -= MINUTES_PER_DAY
		day += 1
		EventBus.clock_day_changed.emit(day)
	var current_hour: int = hour()
	if current_hour != previous_hour:
		EventBus.clock_hour_changed.emit(current_hour)
	EventBus.clock_minute_changed.emit(minute)


func hour() -> int:
	return minute / 60


func minute_of_hour() -> int:
	return minute % 60


## 0.0 at midnight, 0.5 at noon, 1.0 at the next midnight.
func day_fraction() -> float:
	return float(minute) / float(MINUTES_PER_DAY)


func set_speed(p_speed: float) -> void:
	speed = clampf(p_speed, 0.0, 4.0)
	EventBus.clock_speed_changed.emit(speed)


func set_paused(p_paused: bool) -> void:
	paused = p_paused


## Advances the clock by a fixed number of minutes, for tests and for
## "sleep until morning" actions.
func advance_minutes(p_minutes: int) -> void:
	_advance_minutes(p_minutes)


func reset() -> void:
	day = 0
	minute = 0
	_accumulator = 0.0
	speed = 1.0
	paused = false
