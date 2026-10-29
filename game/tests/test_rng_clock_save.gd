extends GdUnitTestSuite
## M0 infrastructure tests: deterministic RNG streams, the game clock, and the
## versioned atomic save file.


func before_test() -> void:
	Rng.reset(1)
	GameClock.reset()


func test_rng_streams_are_reproducible() -> void:
	Rng.reset(1234)
	var first: Array[int] = []
	for i: int in 8:
		first.append(Rng.stream("loot").randi())
	Rng.reset(1234)
	for i: int in 8:
		assert_int(Rng.stream("loot").randi()).is_equal(first[i])


func test_rng_streams_are_independent() -> void:
	Rng.reset(99)
	var loot: int = Rng.stream("loot").randi()
	Rng.reset(99)
	var weather: int = Rng.stream("weather").randi()
	assert_int(loot).is_not_equal(weather)


func test_rng_snapshot_round_trip() -> void:
	Rng.reset(777)
	var a: int = Rng.stream("events").randi()
	var state: Dictionary = Rng.snapshot()
	var b: int = Rng.stream("events").randi()
	Rng.restore(state)
	assert_int(Rng.stream("events").randi()).is_between(b, b)
	assert_int(a).is_not_equal(b)


func test_clock_advances_and_rolls_days() -> void:
	GameClock.reset()
	GameClock.advance_minutes(24 * 60 - 1)
	assert_int(GameClock.day).is_equal(0)
	assert_int(GameClock.hour()).is_equal(23)
	GameClock.advance_minutes(1)
	assert_int(GameClock.day).is_equal(1)
	assert_int(GameClock.hour()).is_equal(0)


func test_clock_process_respects_pause_and_speed() -> void:
	GameClock.reset()
	GameClock.set_paused(true)
	for i: int in 600:
		GameClock._process(0.1)
	assert_int(GameClock.minute).is_equal(0)
	GameClock.set_paused(false)
	GameClock.set_speed(4.0)
	# 1440 game minutes per 720 real seconds = 2 min/s, x4 = 8 min/s.
	# 100 ticks of 0.1 s = 10 real seconds = 80 game minutes.
	for i: int in 100:
		GameClock._process(0.1)
	assert_int(GameClock.day).is_equal(0)
	assert_int(GameClock.minute).is_equal(80)


func test_save_round_trip() -> void:
	GameState.start_run("sandbox", null, 4242)
	GameClock.advance_minutes(1337)
	var _unused: int = Rng.stream("loot").randi()
	assert_bool(SaveSystem.save_slot("autotest")).is_true()
	# The save holds the RNG state as of the save; the next draw is the value a
	# reloaded run must reproduce.
	var expected_next: int = Rng.stream("loot").randi()
	GameClock.reset()
	Rng.reset(0)
	assert_bool(SaveSystem.load_slot("autotest")).is_true()
	assert_int(GameClock.minute).is_equal(1337)
	assert_int(GameState.run_seed).is_equal(4242)
	assert_int(Rng.stream("loot").randi()).is_equal(expected_next)
	var dir: DirAccess = DirAccess.open(SaveSystem.SAVE_DIR)
	dir.remove("autotest.sav")


func test_save_rejects_garbage() -> void:
	DirAccess.make_dir_recursive_absolute(SaveSystem.SAVE_DIR)
	var file: FileAccess = FileAccess.open(SaveSystem.SAVE_DIR + "/garbage.sav", FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8]))
	file.close()
	assert_bool(SaveSystem.load_slot("garbage")).is_false()
	assert_str(SaveSystem.last_error).is_not_empty()
	var dir: DirAccess = DirAccess.open(SaveSystem.SAVE_DIR)
	dir.remove("garbage.sav")


func test_data_tables_are_generated_and_loadable() -> void:
	var materials: MaterialTable = load("res://data/materials.tres") as MaterialTable
	assert_object(materials).is_not_null()
	assert_int(materials.count()).is_equal(9)
	var air: MaterialDef = materials.get_by_id(0)
	assert_object(air).is_not_null()
	assert_str(air.id_name).is_equal("air")
	var fuels: FuelTable = load("res://data/fuels.tres") as FuelTable
	assert_object(fuels).is_not_null()
	var log: FuelDef = fuels.get_by_id("wood_log")
	assert_object(log).is_not_null()
	assert_float(log.total_energy_kj()).is_greater(0.0)
