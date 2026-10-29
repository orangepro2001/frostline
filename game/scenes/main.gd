extends Node2D
## M0 placeholder main scene: a few cells of thermal grid driven at 10 Hz so
## the overlay can be eyeballed. Replaced by the real world in M2.

const TICK_HZ: float = 10.0

var _grid: FrostlineThermalGrid = null
var _accumulator: float = 0.0


func _ready() -> void:
	_grid = FrostlineThermalGrid.new()
	_grid.setup(64, 64, 0.5)
	_grid.fill_temperature(-12.0)
	_grid.set_ambient(-22.0, -5.0)
	# A small room with stone walls.
	_grid.set_material_rect(Rect2i(16, 16, 32, 32), 2)
	_grid.set_material_rect(Rect2i(17, 17, 30, 30), 0)
	_grid.set_exposed_rect(Rect2i(0, 0, 64, 64), true)
	_grid.set_exposed_rect(Rect2i(16, 16, 32, 32), false)
	_grid.add_heat_source(Vector2i(32, 32), 2500.0)


func _process(delta: float) -> void:
	_accumulator += delta
	var step: float = 1.0 / TICK_HZ
	while _accumulator >= step:
		_accumulator -= step
		_grid.step(step)
	queue_redraw()


func _draw() -> void:
	var w: int = _grid.get_width()
	var h: int = _grid.get_height()
	var temps: PackedFloat32Array = _grid.get_temperatures()
	for y: int in h:
		for x: int in w:
			var t: float = temps[y * w + x]
			var k: float = clampf((t + 25.0) / 45.0, 0.0, 1.0)
			var color: Color = Color(0.05 + 0.9 * k, 0.08 + 0.5 * (1.0 - absf(k - 0.5) * 2.0), 0.35 + 0.65 * (1.0 - k), 1.0)
			draw_rect(Rect2(x * 8, y * 8, 8, 8), color)
