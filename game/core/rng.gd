extends Node
## Seeded, split random number generators.
##
## Every random decision asks a named stream (`loot`, `weather`, `events`, ...)
## so that the same seed plus the same input sequence always reproduces the
## same run. Gameplay code must never call the global randf()/randi().

const STREAMS: PackedStringArray = ["loot", "weather", "events", "spawn", "cosmetic"]

var _seed: int = 0
var _streams: Dictionary = {}


func _ready() -> void:
	reset(0)


func reset(p_seed: int) -> void:
	_seed = p_seed
	_streams.clear()
	for stream_name: String in STREAMS:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash_combine(p_seed, stream_name)
		_streams[stream_name] = rng


## Stable 64-bit combination of the run seed and a stream name, so that two
## different streams never share a sequence.
static func hash_combine(p_seed: int, p_name: String) -> int:
	var h: int = p_seed
	for i: int in p_name.length():
		h = (h * 1099511628211) ^ p_name.unicode_at(i)
		h &= 0x7FFFFFFFFFFFFFFF
	return h


func get_seed() -> int:
	return _seed


## Variant -> int without relying on the lossy `int(Variant)` constructor
## (which the project's UNSAFE_* warnings turn into an error).
static func as_int(p_value: Variant) -> int:
	if p_value is int:
		var i: int = p_value
		return i
	if p_value is float:
		var f: float = p_value
		return int(f)
	if p_value is bool:
		var b: bool = p_value
		return 1 if b else 0
	if p_value is String:
		var s: String = p_value
		return s.to_int()
	if p_value is StringName:
		var sn: StringName = p_value
		return String(sn).to_int()
	return 0


static func as_dict(p_value: Variant) -> Dictionary:
	return p_value if p_value is Dictionary else {}


func stream(p_name: String) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = _streams.get(p_name)
	if rng == null:
		push_error("Rng: unknown stream '%s'" % p_name)
		rng = RandomNumberGenerator.new()
		rng.seed = hash_combine(_seed, p_name)
		_streams[p_name] = rng
	return rng


## Serialises the state of every stream for the save file.
func snapshot() -> Dictionary:
	var out: Dictionary = {"seed": _seed, "streams": {}}
	for stream_name: String in _streams.keys():
		var rng: RandomNumberGenerator = _streams[stream_name]
		out["streams"][stream_name] = int(rng.state)
	return out


func restore(p_snapshot: Dictionary) -> void:
	reset(as_int(p_snapshot.get("seed", 0)))
	var states: Dictionary = as_dict(p_snapshot.get("streams", {}))
	for stream_name: String in states.keys():
		if _streams.has(stream_name):
			var rng: RandomNumberGenerator = _streams[stream_name]
			rng.state = maxi(1, as_int(states[stream_name]))
