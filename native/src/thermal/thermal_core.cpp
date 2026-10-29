#include "thermal_core.h"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstring>

namespace frostline {

namespace {

// The forward-Euler update stays stable while dt * sum(k_ij) / C_i <= 1.
// We aim at half of that so that every sub-step has margin.
constexpr float kStabilityTarget = 0.5f;

// Cells whose neighbourhood differs by less than this are considered at rest by
// the active-set variant.
constexpr float kSteadyEpsilon = 1e-3f;

// Material table.
//
// The model is a lumped RC network on a grid: every cell is one node with a
// heat capacity C (J/K) and a coupling k (W/K) per shared edge. The
// coefficients already fold in wall thickness and cell geometry, so the values
// are per cell of the prototype's 0.5 m grid - they are balance numbers, not
// bulk material constants. Keeping them lumped keeps the system stable at the
// 10 Hz tick without making the solver expensive.
//
// `surface` couples an *exposed* cell to the ambient weather; `blocks_wind`
// feeds the wind-chill correction.
struct MaterialDef {
	const char *name;
	float conductivity; // W/K per shared edge, before the harmonic mean
	float capacity;     // J/K for one cell
	float surface;      // W/K to the ambient, exposed cells only
	bool blocks_wind;
};

// data_src/materials.csv is the source of truth for tooling; the unit test
// "compiled table matches the CSV" keeps the two in sync.
const MaterialDef kMaterials[MAT_COUNT] = {
	// name          cond  cap      surf  wind
	{"air", 4.00f, 1000.0f, 3.0f, false},
	{"wood", 1.50f, 30000.0f, 2.0f, true},
	{"stone", 0.80f, 90000.0f, 1.0f, true},
	{"metal", 40.00f, 40000.0f, 1.5f, true},
	{"insulation", 0.12f, 15000.0f, 0.5f, true},
	{"door", 2.50f, 25000.0f, 3.0f, false},
	{"window", 5.00f, 6000.0f, 8.0f, false},
	{"ground", 0.60f, 300000.0f, 0.4f, true},
	{"glass", 6.00f, 8000.0f, 9.0f, false},
};

} // namespace

const Material &material(uint8_t id) {
	static Material table[MAT_COUNT];
	static bool filled = false;
	if (!filled) {
		for (int i = 0; i < MAT_COUNT; ++i) {
			Material &m = table[i];
			const MaterialDef &d = kMaterials[i];
			m.name = d.name;
			m.conductivity = d.conductivity;
			m.capacity = d.capacity;
			m.surface_coef = d.surface;
			m.blocks_wind = d.blocks_wind;
		}
		filled = true;
	}
	return table[id < MAT_COUNT ? static_cast<size_t>(id) : static_cast<size_t>(MAT_AIR)];
}

int material_count() { return MAT_COUNT; }

void ThermalGrid::setup(int32_t width, int32_t height, float cell_size_m) {
	assert(width > 0 && height > 0);
	width_ = width;
	height_ = height;
	cell_size_ = cell_size_m > 0.0f ? cell_size_m : 1.0f;
	const size_t n = static_cast<size_t>(width) * static_cast<size_t>(height);
	material_.assign(n, MAT_AIR);
	exposed_.assign(n, 0);
	temperature_.assign(n, 0.0f);
	scratch_.assign(n, 0.0f);
	delta_.assign(n, 0.0f);
	sources_.clear();
	sources_.shrink_to_fit();
	ambient_ = 0.0f;
	wind_chill_ = 0.0f;
	last_substeps_ = 0;
	simulated_cells_ = 0;
}

void ThermalGrid::set_material(int32_t x, int32_t y, uint8_t id) {
	if (!in_bounds(x, y)) {
		return;
	}
	material_[static_cast<size_t>(y) * width_ + x] = id;
}

uint8_t ThermalGrid::get_material(int32_t x, int32_t y) const {
	if (!in_bounds(x, y)) {
		return MAT_AIR;
	}
	return material_[static_cast<size_t>(y) * width_ + x];
}

void ThermalGrid::set_material_rect(int32_t x, int32_t y, int32_t w, int32_t h, uint8_t id) {
	for (int32_t yy = y; yy < y + h; ++yy) {
		for (int32_t xx = x; xx < x + w; ++xx) {
			set_material(xx, yy, id);
		}
	}
}

void ThermalGrid::set_exposed(int32_t x, int32_t y, bool exposed) {
	if (!in_bounds(x, y)) {
		return;
	}
	exposed_[static_cast<size_t>(y) * width_ + x] = exposed ? 1 : 0;
}

bool ThermalGrid::get_exposed(int32_t x, int32_t y) const {
	if (!in_bounds(x, y)) {
		return false;
	}
	return exposed_[static_cast<size_t>(y) * width_ + x] != 0;
}

void ThermalGrid::set_exposed_rect(int32_t x, int32_t y, int32_t w, int32_t h, bool exposed) {
	for (int32_t yy = y; yy < y + h; ++yy) {
		for (int32_t xx = x; xx < x + w; ++xx) {
			set_exposed(xx, yy, exposed);
		}
	}
}

void ThermalGrid::set_temperature(int32_t x, int32_t y, float celsius) {
	if (!in_bounds(x, y)) {
		return;
	}
	temperature_[static_cast<size_t>(y) * width_ + x] = celsius;
}

float ThermalGrid::get_temperature(int32_t x, int32_t y) const {
	if (!in_bounds(x, y)) {
		return ambient_;
	}
	return temperature_[static_cast<size_t>(y) * width_ + x];
}

void ThermalGrid::fill_temperature(float celsius) {
	std::fill(temperature_.begin(), temperature_.end(), celsius);
}

void ThermalGrid::set_ambient(float ambient_c, float wind_chill_c) {
	ambient_ = ambient_c;
	wind_chill_ = wind_chill_c;
}

int32_t ThermalGrid::add_heat_source(int32_t x, int32_t y, float watts) {
	if (!in_bounds(x, y)) {
		return -1;
	}
	// Reuse a tombstoned slot so ids do not grow without bound.
	for (size_t i = 0; i < sources_.size(); ++i) {
		if (sources_[i].cell < 0) {
			sources_[i].cell = y * width_ + x;
			sources_[i].watts = watts;
			sources_[i].enabled = true;
			return static_cast<int32_t>(i);
		}
	}
	HeatSource s;
	s.cell = y * width_ + x;
	s.watts = watts;
	s.enabled = true;
	sources_.push_back(s);
	return static_cast<int32_t>(sources_.size()) - 1;
}

bool ThermalGrid::set_heat_source_power(int32_t id, float watts) {
	if (id < 0 || id >= static_cast<int32_t>(sources_.size()) || sources_[static_cast<size_t>(id)].cell < 0) {
		return false;
	}
	sources_[static_cast<size_t>(id)].watts = watts;
	return true;
}

bool ThermalGrid::set_heat_source_enabled(int32_t id, bool enabled) {
	if (id < 0 || id >= static_cast<int32_t>(sources_.size()) || sources_[static_cast<size_t>(id)].cell < 0) {
		return false;
	}
	sources_[static_cast<size_t>(id)].enabled = enabled;
	return true;
}

bool ThermalGrid::remove_heat_source(int32_t id) {
	if (id < 0 || id >= static_cast<int32_t>(sources_.size())) {
		return false;
	}
	HeatSource &s = sources_[static_cast<size_t>(id)];
	if (s.cell < 0) {
		return false;
	}
	s.cell = -1; // tombstone: the other ids stay stable
	s.watts = 0.0f;
	s.enabled = false;
	return true;
}

float ThermalGrid::boundary_conductance(size_t i, size_t j, float cell_size) const {
	(void)cell_size;
	const float a = material(material_[i]).conductivity;
	const float b = material(material_[j]).conductivity;
	const float sum = a + b;
	// harmonic mean of the two cell coefficients (design document M1): the
	// worse conductor dominates a series wall.
	return sum > 0.0f ? (2.0f * a * b) / sum : 0.0f;
}

float ThermalGrid::substep_bound() const {
	float worst = 0.0f;
	const int32_t w = width_;
	const int32_t h = height_;
	for (int32_t y = 0; y < h; ++y) {
		for (int32_t x = 0; x < w; ++x) {
			const size_t i = static_cast<size_t>(y) * static_cast<size_t>(w) + static_cast<size_t>(x);
			const Material &m = material(material_[i]);
			float sum = 0.0f;
			const int32_t nx[4] = {x - 1, x + 1, x, x};
			const int32_t ny[4] = {y, y, y - 1, y + 1};
			for (int d = 0; d < 4; ++d) {
				if (!in_bounds(nx[d], ny[d])) {
					continue;
				}
				const size_t j = static_cast<size_t>(ny[d]) * static_cast<size_t>(w) + static_cast<size_t>(nx[d]);
				sum += boundary_conductance(i, j, cell_size_);
			}
			if (exposed_[i] != 0) {
				sum += m.surface_coef;
			}
			worst = std::max(worst, sum / std::max(1e-3f, m.capacity));
		}
	}
	return worst;
}

void ThermalGrid::step(float dt) { step_internal(dt, false); }

int32_t ThermalGrid::step_active(float dt) {
	simulated_cells_ = 0;
	int32_t active = 0;
	const int32_t w = width_;
	const int32_t h = height_;
	for (int32_t y = 0; y < h; ++y) {
		for (int32_t x = 0; x < w; ++x) {
			const size_t i = static_cast<size_t>(y) * static_cast<size_t>(w) + static_cast<size_t>(x);
			bool moving = exposed_[i] != 0;
			if (!moving) {
				const float t_i = temperature_[i];
				const int32_t nx[4] = {x - 1, x + 1, x, x};
				const int32_t ny[4] = {y, y, y - 1, y + 1};
				for (int d = 0; d < 4 && !moving; ++d) {
					if (!in_bounds(nx[d], ny[d])) {
						continue;
					}
					const size_t j = static_cast<size_t>(ny[d]) * static_cast<size_t>(w) + static_cast<size_t>(nx[d]);
					moving = exposed_[j] != 0 || std::fabs(temperature_[j] - t_i) >= kSteadyEpsilon;
				}
			}
			if (moving) {
				++active;
			}
		}
	}
	for (const HeatSource &src : sources_) {
		if (src.cell >= 0 && src.enabled && src.watts != 0.0f) {
			++active; // a live source injects heat every tick
		}
	}
	if (active > 0) {
		step_internal(dt, true);
	}
	return active;
}

void ThermalGrid::step_internal(float dt, bool use_activity_mask) {
	if (dt <= 0.0f || width_ <= 0 || height_ <= 0) {
		last_substeps_ = 0;
		return;
	}
	const float bound = substep_bound() * dt;
	int32_t substeps = 1;
	if (bound > kStabilityTarget) {
		substeps = static_cast<int32_t>(std::ceil(bound / kStabilityTarget));
	}
	assert(substeps <= 4096);
	substeps = std::clamp(substeps, 1, 4096);
	last_substeps_ = substeps;

	const float h = dt / static_cast<float>(substeps);
	const int32_t w = width_;
	const int32_t hgt = height_;
	const float ambient = ambient_ + wind_chill_;

	for (int32_t s = 0; s < substeps; ++s) {
		// `delta_` holds *energy* in joules, not temperature: every edge is
		// evaluated once and the same number is added to one cell and
		// subtracted from the other, so the discrete scheme conserves energy
		// exactly (up to float32 rounding of a single value) no matter how
		// asymmetric the two materials are.
		std::fill(delta_.begin(), delta_.end(), 0.0f);

		for (const HeatSource &src : sources_) {
			if (src.cell < 0 || !src.enabled) {
				continue;
			}
			delta_[static_cast<size_t>(src.cell)] += h * src.watts;
		}

		for (int32_t y = 0; y < hgt; ++y) {
			const size_t row = static_cast<size_t>(y) * static_cast<size_t>(w);
			for (int32_t x = 0; x < w; ++x) {
				const size_t i = row + static_cast<size_t>(x);
				// Right and down edges only: every interior edge is visited once.
				if (x + 1 < w) {
					const size_t j = i + 1;
					const float t_i = temperature_[i];
					const float t_j = temperature_[j];
					if (!(use_activity_mask && exposed_[i] == 0 && exposed_[j] == 0 &&
								std::fabs(t_j - t_i) < kSteadyEpsilon)) {
						const float e = h * boundary_conductance(i, j, cell_size_) * (t_j - t_i);
						delta_[i] += e;
						delta_[j] -= e;
					}
				}
				if (y + 1 < hgt) {
					const size_t j = i + static_cast<size_t>(w);
					const float t_i = temperature_[i];
					const float t_j = temperature_[j];
					if (!(use_activity_mask && exposed_[i] == 0 && exposed_[j] == 0 &&
								std::fabs(t_j - t_i) < kSteadyEpsilon)) {
						const float e = h * boundary_conductance(i, j, cell_size_) * (t_j - t_i);
						delta_[i] += e;
						delta_[j] -= e;
					}
				}
				if (exposed_[i] != 0) {
					const float t_i = temperature_[i];
					delta_[i] += h * material(material_[i]).surface_coef * (ambient - t_i);
				}
			}
		}

		for (size_t i = 0; i < delta_.size(); ++i) {
			scratch_[i] = temperature_[i] + delta_[i] / std::max(1e-3f, material(material_[i]).capacity);
		}
		temperature_.swap(scratch_);
		simulated_cells_ += static_cast<int64_t>(delta_.size());
	}
}

double ThermalGrid::total_energy() const {
	double e = 0.0;
	for (size_t i = 0; i < temperature_.size(); ++i) {
		e += static_cast<double>(material(material_[i]).capacity) * static_cast<double>(temperature_[i]);
	}
	return e;
}

void ThermalGrid::write_temperatures(std::vector<float> &out) const { out = temperature_; }

std::vector<float> ThermalGrid::snapshot() const { return temperature_; }

void ThermalGrid::reset_stats() {
	simulated_cells_ = 0;
	last_substeps_ = 0;
}

} // namespace frostline
