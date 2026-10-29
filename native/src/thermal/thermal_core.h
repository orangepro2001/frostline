// Frostline - pure C++ thermal grid.
//
// This file contains no godot-cpp dependency on purpose: it is compiled into
// both the GDExtension and the standalone doctest binary.
//
// Model
// -----
// Every cell stores a temperature (degC) and a material id. Once per tick each
// cell exchanges heat with its four axis neighbours:
//
//     dT_i = dt * sum_j( k_ij * (T_j - T_i) ) / C_i
//
// with k_ij the harmonic mean of the two conductivities (a series wall: the
// worse conductor dominates) and C_i the cell heat capacity.
//
// The explicit (forward) Euler update is stable only while
//
//     dt * sum_j(k_ij) / C_i <= 1/4        (2D, four neighbours)
//
// so `step()` splits the tick into as many equal sub-steps as needed. The
// condition is asserted in debug builds and clamped in release builds.
//
// Exposed cells are not exchanged with a neighbour but relaxed towards the
// ambient temperature with a per-material surface coefficient:
//
//     dT_i = dt * k_surface * (T_ambient - T_i) / C_i
//
// Heat sources inject power directly:
//
//     dT_i += dt * watts / C_i
//
// All buffers are preallocated; `step()` performs no allocation.
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace frostline {

// Material ids used by the prototype. The numeric values are part of the
// save format, so they must never be renumbered.
enum MaterialId : uint8_t {
	MAT_AIR = 0,
	MAT_WOOD = 1,
	MAT_STONE = 2,
	MAT_METAL = 3,
	MAT_INSULATION = 4,
	MAT_DOOR = 5,
	MAT_WINDOW = 6,
	MAT_GROUND = 7,
	MAT_GLASS = 8,
	MAT_COUNT = 9,
};

// Thermal properties of one material.
//
//   conductivity  W/(m*K)   harmonic-meaned across a shared edge
//   capacity      J/(m^2*K) heat capacity of one 1 m^2 cell
//   surface_coef  W/(m^2*K) relaxation rate towards ambient for exposed cells
//   heat_source_w watts a cell of this material can emit when used as a source
struct Material {
	const char *name;
	float conductivity;
	float capacity;
	float surface_coef;
	bool blocks_wind;
};

// The table is defined in thermal_core.cpp.
const Material &material(uint8_t id);
int material_count();

// Parameters of one heat source. Sources live inside the grid so that a saved
// grid round-trips without a second data structure.
struct HeatSource {
	int32_t cell = 0;
	float watts = 0.0f;
	bool enabled = true;
};

class ThermalGrid {
public:
	ThermalGrid() = default;

	// Allocates width*height cells. Invalidates all previous contents.
	void setup(int32_t width, int32_t height, float cell_size_m);

	int32_t width() const { return width_; }
	int32_t height() const { return height_; }
	int32_t cell_count() const { return width_ * height_; }
	float cell_size() const { return cell_size_; }

	bool in_bounds(int32_t x, int32_t y) const {
		return x >= 0 && y >= 0 && x < width_ && y < height_;
	}

	// --- materials / exposure -------------------------------------------
	void set_material(int32_t x, int32_t y, uint8_t id);
	uint8_t get_material(int32_t x, int32_t y) const;
	void set_material_rect(int32_t x, int32_t y, int32_t w, int32_t h, uint8_t id);

	void set_exposed(int32_t x, int32_t y, bool exposed);
	bool get_exposed(int32_t x, int32_t y) const;
	void set_exposed_rect(int32_t x, int32_t y, int32_t w, int32_t h, bool exposed);

	// --- temperature -----------------------------------------------------
	void set_temperature(int32_t x, int32_t y, float celsius);
	float get_temperature(int32_t x, int32_t y) const;
	void fill_temperature(float celsius);

	// Ambient temperature the exposed cells relax towards, plus the wind chill
	// offset that is applied to exposed cells only.
	void set_ambient(float ambient_c, float wind_chill_c);

	// --- heat sources ----------------------------------------------------
	// Returns a stable id (index into the source list). -1 when the cell is
	// outside the grid.
	int32_t add_heat_source(int32_t x, int32_t y, float watts);
	bool set_heat_source_power(int32_t id, float watts);
	bool set_heat_source_enabled(int32_t id, bool enabled);
	bool remove_heat_source(int32_t id);
	int32_t heat_source_count() const { return static_cast<int32_t>(sources_.size()); }
	const HeatSource &heat_source(int32_t id) const { return sources_[static_cast<size_t>(id)]; }

	// --- simulation ------------------------------------------------------
	// Advances the simulation by dt seconds. Internally sub-steps so that the
	// forward-Euler stability condition holds for every cell.
	void step(float dt);

	// Number of sub-steps the last `step()` performed (for tests / telemetry).
	int32_t last_substeps() const { return last_substeps_; }

	// Total thermal energy in joules, used by the conservation test.
	double total_energy() const;

	// Writes the temperature field into `out` as row-major floats.
	void write_temperatures(std::vector<float> &out) const;

	// Deterministic byte-for-byte snapshot used by the determinism test.
	std::vector<float> snapshot() const;

	// Skips whole grids whose cells are all at steady state (no exposed cell,
	// no live heat source, every neighbour within kSteadyEpsilon). Returns the
	// number of cells that were considered active.
	int32_t step_active(float dt);

	void reset_stats();
	int64_t simulated_cells() const { return simulated_cells_; }

private:
	// Conductance (W/(m^2*K)) across the edge shared by cells i and j: the
	// series coupling of the two boundary conductances.
	float boundary_conductance(size_t i, size_t j, float cell_size) const;
	void step_internal(float dt, bool use_activity_mask);
	float substep_bound() const;

	int32_t width_ = 0;
	int32_t height_ = 0;
	float cell_size_ = 1.0f;

	std::vector<uint8_t> material_;
	std::vector<uint8_t> exposed_;
	std::vector<float> temperature_;
	std::vector<float> scratch_;
	std::vector<float> delta_; // energy in joules per sub-step
	std::vector<HeatSource> sources_;

	float ambient_ = 0.0f;
	float wind_chill_ = 0.0f;
	int32_t last_substeps_ = 0;
	int64_t simulated_cells_ = 0;
};

} // namespace frostline
