#include "thermal_grid.h"

#include "thermal_core.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

using namespace godot;

namespace godot {

FrostlineThermalGrid::FrostlineThermalGrid() : grid_(std::make_unique<frostline::ThermalGrid>()) {}

FrostlineThermalGrid::~FrostlineThermalGrid() = default;

void FrostlineThermalGrid::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "width", "height", "cell_size"), &FrostlineThermalGrid::setup);
	ClassDB::bind_method(D_METHOD("get_width"), &FrostlineThermalGrid::get_width);
	ClassDB::bind_method(D_METHOD("get_height"), &FrostlineThermalGrid::get_height);

	ClassDB::bind_method(D_METHOD("set_material", "x", "y", "material_id"), &FrostlineThermalGrid::set_material);
	ClassDB::bind_method(D_METHOD("get_material", "x", "y"), &FrostlineThermalGrid::get_material);
	ClassDB::bind_method(D_METHOD("set_material_rect", "rect", "material_id"), &FrostlineThermalGrid::set_material_rect);

	ClassDB::bind_method(D_METHOD("set_exposed", "x", "y", "exposed"), &FrostlineThermalGrid::set_exposed);
	ClassDB::bind_method(D_METHOD("get_exposed", "x", "y"), &FrostlineThermalGrid::get_exposed);
	ClassDB::bind_method(D_METHOD("set_exposed_rect", "rect", "exposed"), &FrostlineThermalGrid::set_exposed_rect);

	ClassDB::bind_method(D_METHOD("set_temperature", "x", "y", "celsius"), &FrostlineThermalGrid::set_temperature);
	ClassDB::bind_method(D_METHOD("get_temperature", "x", "y"), &FrostlineThermalGrid::get_temperature);
	ClassDB::bind_method(D_METHOD("fill_temperature", "celsius"), &FrostlineThermalGrid::fill_temperature);
	ClassDB::bind_method(D_METHOD("set_ambient", "temperature_c", "wind_chill_c"), &FrostlineThermalGrid::set_ambient);

	ClassDB::bind_method(D_METHOD("add_heat_source", "cell", "power_watts"), &FrostlineThermalGrid::add_heat_source);
	ClassDB::bind_method(D_METHOD("set_heat_source_power", "id", "power_watts"), &FrostlineThermalGrid::set_heat_source_power);
	ClassDB::bind_method(D_METHOD("set_heat_source_enabled", "id", "enabled"), &FrostlineThermalGrid::set_heat_source_enabled);
	ClassDB::bind_method(D_METHOD("remove_heat_source", "id"), &FrostlineThermalGrid::remove_heat_source);
	ClassDB::bind_method(D_METHOD("get_heat_source_count"), &FrostlineThermalGrid::get_heat_source_count);

	ClassDB::bind_method(D_METHOD("step", "dt"), &FrostlineThermalGrid::step);
	ClassDB::bind_method(D_METHOD("step_active", "dt"), &FrostlineThermalGrid::step_active);
	ClassDB::bind_method(D_METHOD("get_last_substeps"), &FrostlineThermalGrid::get_last_substeps);
	ClassDB::bind_method(D_METHOD("get_total_energy"), &FrostlineThermalGrid::get_total_energy);
	ClassDB::bind_method(D_METHOD("get_temperatures"), &FrostlineThermalGrid::get_temperatures);
}

void FrostlineThermalGrid::setup(int32_t width, int32_t height, float cell_size) {
	grid_->setup(width, height, cell_size);
}

int32_t FrostlineThermalGrid::get_width() const { return grid_->width(); }
int32_t FrostlineThermalGrid::get_height() const { return grid_->height(); }

void FrostlineThermalGrid::set_material(int32_t x, int32_t y, int32_t material_id) {
	grid_->set_material(x, y, static_cast<uint8_t>(material_id));
}

int32_t FrostlineThermalGrid::get_material(int32_t x, int32_t y) const {
	return static_cast<int32_t>(grid_->get_material(x, y));
}

void FrostlineThermalGrid::set_material_rect(const Rect2i &rect, int32_t material_id) {
	grid_->set_material_rect(rect.position.x, rect.position.y, rect.size.x, rect.size.y,
			static_cast<uint8_t>(material_id));
}

void FrostlineThermalGrid::set_exposed(int32_t x, int32_t y, bool exposed) { grid_->set_exposed(x, y, exposed); }

bool FrostlineThermalGrid::get_exposed(int32_t x, int32_t y) const { return grid_->get_exposed(x, y); }

void FrostlineThermalGrid::set_exposed_rect(const Rect2i &rect, bool exposed) {
	grid_->set_exposed_rect(rect.position.x, rect.position.y, rect.size.x, rect.size.y, exposed);
}

void FrostlineThermalGrid::set_temperature(int32_t x, int32_t y, float celsius) {
	grid_->set_temperature(x, y, celsius);
}

float FrostlineThermalGrid::get_temperature(int32_t x, int32_t y) const { return grid_->get_temperature(x, y); }

void FrostlineThermalGrid::fill_temperature(float celsius) { grid_->fill_temperature(celsius); }

void FrostlineThermalGrid::set_ambient(float ambient_c, float wind_chill_c) {
	grid_->set_ambient(ambient_c, wind_chill_c);
}

int32_t FrostlineThermalGrid::add_heat_source(const Vector2i &cell, float watts) {
	return grid_->add_heat_source(cell.x, cell.y, watts);
}

bool FrostlineThermalGrid::set_heat_source_power(int32_t id, float watts) {
	return grid_->set_heat_source_power(id, watts);
}

bool FrostlineThermalGrid::set_heat_source_enabled(int32_t id, bool enabled) {
	return grid_->set_heat_source_enabled(id, enabled);
}

bool FrostlineThermalGrid::remove_heat_source(int32_t id) { return grid_->remove_heat_source(id); }

int32_t FrostlineThermalGrid::get_heat_source_count() const { return grid_->heat_source_count(); }

void FrostlineThermalGrid::step(float dt) { grid_->step(dt); }

int32_t FrostlineThermalGrid::step_active(float dt) { return grid_->step_active(dt); }

int32_t FrostlineThermalGrid::get_last_substeps() const { return grid_->last_substeps(); }

double FrostlineThermalGrid::get_total_energy() const { return grid_->total_energy(); }

PackedFloat32Array FrostlineThermalGrid::get_temperatures() const {
	const int32_t n = grid_->cell_count();
	PackedFloat32Array out;
	if (n <= 0) {
		return out;
	}
	out.resize(n);
	const int32_t w = grid_->width();
	for (int32_t y = 0; y < grid_->height(); ++y) {
		for (int32_t x = 0; x < w; ++x) {
			out[y * w + x] = grid_->get_temperature(x, y);
		}
	}
	return out;
}

} // namespace godot
