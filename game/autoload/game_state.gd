extends Node
## Everything that must survive a save: which mode is running, which difficulty
## profile is active, the counters that describe progress.
##
## Simulation state lives in plain data objects (see `systems/`), not in the
## scene tree; this singleton is the handle to them.

var mode_id: String = "sandbox"
var difficulty_id: String = "standard"
var difficulty: Resource = null
var run_seed: int = 0
var days_survived: int = 0
var in_shelter: bool = true


func _ready() -> void:
	EventBus.clock_day_changed.connect(_on_day_changed)


func start_run(p_mode_id: String, p_difficulty: Resource, p_seed: int) -> void:
	mode_id = p_mode_id
	difficulty = p_difficulty
	difficulty_id = str(p_difficulty.get("id")) if p_difficulty != null else "standard"
	run_seed = p_seed
	days_survived = 0
	GameClock.reset()
	Rng.reset(p_seed)
	EventBus.game_mode_started.emit(mode_id)


func _on_day_changed(p_day: int) -> void:
	days_survived = p_day


func to_dict() -> Dictionary:
	return {
		"mode_id": mode_id,
		"difficulty_id": difficulty_id,
		"run_seed": run_seed,
		"days_survived": days_survived,
		"in_shelter": in_shelter,
	}


func from_dict(p_data: Dictionary) -> void:
	mode_id = str(p_data.get("mode_id", "sandbox"))
	difficulty_id = str(p_data.get("difficulty_id", "standard"))
	run_seed = _as_int(p_data.get("run_seed", 0))
	days_survived = _as_int(p_data.get("days_survived", 0))
	in_shelter = _as_bool(p_data.get("in_shelter", true))


## Dictionary values are Variants; converting them explicitly avoids the
## UNSAFE_CAST warnings that this project treats as errors.
static func _as_int(p_value: Variant) -> int:
	return Rng.as_int(p_value)


static func _as_bool(p_value: Variant) -> bool:
	match typeof(p_value):
		TYPE_BOOL:
			return p_value
		TYPE_INT, TYPE_FLOAT:
			return p_value != 0
		_:
			return false
