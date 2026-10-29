#ifndef FROSTLINE_THERMAL_GRID_H
#define FROSTLINE_THERMAL_GRID_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <memory>
#include <vector>

namespace frostline {
class ThermalGrid;
}

namespace godot {

// Thin Godot binding around frostline::ThermalGrid.
//
// The C++ core knows nothing about Godot, which is what lets the doctest suite
// exercise it on a build machine without the engine. This class only marshals
// arguments and copies the temperature field into images / packed arrays.
class FrostlineThermalGrid : public RefCounted {
	GDCLASS(FrostlineThermalGrid, RefCounted)

protected:
	static void _bind_methods();

public:
	FrostlineThermalGrid();
	~FrostlineThermalGrid() override;

	void setup(int32_t width, int32_t height, float cell_size);
	int32_t get_width() const;
	int32_t get_height() const;

	void set_material(int32_t x, int32_t y, int32_t material_id);
	int32_t get_material(int32_t x, int32_t y) const;
	void set_material_rect(const Rect2i &rect, int32_t material_id);

	void set_exposed(int32_t x, int32_t y, bool exposed);
	bool get_exposed(int32_t x, int32_t y) const;
	void set_exposed_rect(const Rect2i &rect, bool exposed);

	void set_temperature(int32_t x, int32_t y, float celsius);
	float get_temperature(int32_t x, int32_t y) const;
	void fill_temperature(float celsius);

	void set_ambient(float ambient_c, float wind_chill_c);

	int32_t add_heat_source(const Vector2i &cell, float watts);
	bool set_heat_source_power(int32_t id, float watts);
	bool set_heat_source_enabled(int32_t id, bool enabled);
	bool remove_heat_source(int32_t id);
	int32_t get_heat_source_count() const;

	void step(float dt);
	int32_t step_active(float dt);
	int32_t get_last_substeps() const;
	double get_total_energy() const;

	// Row-major temperature field, handy for HUD readouts and tests.
	PackedFloat32Array get_temperatures() const;

private:
	std::unique_ptr<frostline::ThermalGrid> grid_;
};

} // namespace godot

#endif // FROSTLINE_THERMAL_GRID_H
