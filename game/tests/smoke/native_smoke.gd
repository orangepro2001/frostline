extends SceneTree
## M0 acceptance: the engine loads the GDExtension and both native classes work.

func _initialize() -> void:
	var failures: int = 0
	if not ClassDB.class_exists("NativeHello"):
		printerr("NativeHello is not registered")
		failures += 1
	else:
		print("NativeHello.get_version() = ", NativeHello.get_version())
		if NativeHello.get_answer() != 42:
			printerr("NativeHello.get_answer() != 42")
			failures += 1

	if not ClassDB.class_exists("FrostlineThermalGrid"):
		printerr("FrostlineThermalGrid is not registered")
		failures += 1
	else:
		var grid: FrostlineThermalGrid = FrostlineThermalGrid.new()
		grid.setup(32, 32, 0.5)
		grid.fill_temperature(-5.0)
		grid.set_ambient(-20.0, -4.0)
		grid.set_material_rect(Rect2i(8, 8, 16, 16), 2)
		grid.add_heat_source(Vector2i(16, 16), 1500.0)
		for i: int in 100:
			grid.step(0.1)
		var t: float = grid.get_temperature(16, 16)
		print("grid centre after 10 s = %.3f C (%d cells, %d sub-steps)" % [t, grid.get_width() * grid.get_height(), grid.get_last_substeps()])
		if not is_finite(t):
			printerr("grid temperature is not finite")
			failures += 1
		if grid.get_temperatures().size() != 32 * 32:
			printerr("get_temperatures() has the wrong size")
			failures += 1

	print("SMOKE RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
