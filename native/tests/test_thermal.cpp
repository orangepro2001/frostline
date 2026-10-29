// Tests for the pure C++ thermal core. They build without godot-cpp, which is
// what lets `scripts/run_tests.sh` verify the simulation on any machine.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include "doctest.h"

#include "thermal/thermal_core.h"

#include <chrono>
#include <cmath>
#include <cstring>
#include <vector>

using namespace frostline;

namespace {

// Builds a room: `wall_id` walls, an air interior, everything outside exposed
// to the ambient. Returns the grid by value.
ThermalGrid make_room(int32_t size, uint8_t wall_id, bool door_open) {
	ThermalGrid grid;
	grid.setup(size, size, 1.0f);
	grid.fill_temperature(-20.0f);
	grid.set_material_rect(0, 0, size, size, MAT_GROUND);
	grid.set_exposed_rect(0, 0, size, size, true);

	// Room occupies the middle third, walls included.
	const int32_t lo = size / 3;
	const int32_t hi = size - size / 3;
	grid.set_material_rect(lo, lo, hi - lo, hi - lo, wall_id);
	grid.set_material_rect(lo + 1, lo + 1, hi - lo - 2, hi - lo - 2, MAT_AIR);
	grid.set_exposed_rect(lo + 1, lo + 1, hi - lo - 2, hi - lo - 2, false);
	// The floor is never exposed: only the interior and the walls are indoors.
	grid.set_exposed_rect(lo, lo, hi - lo, hi - lo, false);

	if (door_open) {
		// A one-cell gap in the wall, exposed to the outside.
		grid.set_material(lo, (lo + hi) / 2, MAT_DOOR);
		grid.set_exposed(lo, (lo + hi) / 2, true);
	}
	grid.set_ambient(-20.0f, 0.0f);
	grid.fill_temperature(-20.0f);
	return grid;
}

} // namespace

TEST_CASE("material table is complete") {
	CHECK(material_count() == MAT_COUNT);
	for (int i = 0; i < material_count(); ++i) {
		const Material &m = material(static_cast<uint8_t>(i));
		CHECK(m.name != nullptr);
		CHECK(m.capacity > 0.0f);
		CHECK(m.conductivity >= 0.0f);
	}
}

TEST_CASE("out of bounds access is safe") {
	ThermalGrid g;
	g.setup(8, 8, 1.0f);
	g.set_temperature(-1, 4, 99.0f);
	CHECK(g.get_temperature(-1, 4) == doctest::Approx(g.get_temperature(0, 0)));
	CHECK(g.add_heat_source(99, 99, 100.0f) == -1);
	CHECK(g.get_material(100, 100) == MAT_AIR);
}

TEST_CASE("closed room conserves energy") {
	// No exposed cells: the domain is a sealed box, so the sum of C*T must not
	// change even though heat is redistributed internally.
	ThermalGrid g;
	g.setup(16, 16, 1.0f);
	g.set_material_rect(0, 0, 16, 16, MAT_STONE);
	g.set_temperature(4, 4, 40.0f);
	g.set_temperature(8, 8, -10.0f);
	g.set_ambient(-30.0f, 0.0f);

	const double e0 = g.total_energy();
	for (int i = 0; i < 5000; ++i) {
		g.step(0.1f);
	}
	const double e1 = g.total_energy();
	const double rel = std::fabs(e1 - e0) / std::max(1.0, std::fabs(e0));
	INFO("energy " << e0 << " -> " << e1);
	// float32 rounding of 256 accumulating cells: no systematic drift, only noise.
	CHECK(rel < 1e-4);
}

TEST_CASE("heat source warms its cell") {
	ThermalGrid g;
	g.setup(8, 8, 1.0f);
	// A single room cell surrounded by walls: the source only has to heat one
	// small node, so 3 kW is plenty for a 60 s smoke test.
	g.set_material_rect(0, 0, 8, 8, MAT_STONE);
	g.set_material_rect(3, 3, 3, 3, MAT_AIR);
	g.fill_temperature(-20.0f);
	g.set_ambient(-20.0f, 0.0f);
	const int32_t id = g.add_heat_source(4, 4, 3000.0f);
	CHECK(id == 0);
	for (int i = 0; i < 600; ++i) {
		g.step(0.1f);
	}
	CHECK(g.get_temperature(4, 4) > 0.0f);
	CHECK(g.get_temperature(0, 0) < g.get_temperature(4, 4));

	// Switching the source off lets the cell cool again.
	g.set_heat_source_enabled(id, false);
	const float hot = g.get_temperature(4, 4);
	for (int i = 0; i < 600; ++i) {
		g.step(0.1f);
	}
	CHECK(g.get_temperature(4, 4) < hot);
}

TEST_CASE("stone walls insulate better than wooden walls") {
	// Same source, same ambient: the stone room must end up warmer because
	// stone conducts less than wood in the material table... and because the
	// wall material's capacity stores the heat it lets through.
	auto run = [](uint8_t wall) {
		ThermalGrid g = make_room(24, wall, false);
		g.set_temperature(12, 12, 0.0f);
		g.add_heat_source(12, 12, 900.0f);
		for (int i = 0; i < 3000; ++i) {
			g.step(0.1f);
		}
		return g.get_temperature(12, 12);
	};
	const float wood = run(MAT_WOOD);
	const float stone = run(MAT_STONE);
	INFO("wood=" << wood << " stone=" << stone);
	CHECK(stone > wood);
}

TEST_CASE("opening a door lets the room cool down") {
	auto run = [](bool open) {
		ThermalGrid g = make_room(24, MAT_WOOD, open);
		g.set_temperature(12, 12, 15.0f);
		g.add_heat_source(12, 12, 400.0f);
		for (int i = 0; i < 1500; ++i) {
			g.step(0.1f);
		}
		return g.get_temperature(12, 12);
	};
	const float closed = run(false);
	const float open = run(true);
	INFO("closed=" << closed << " open=" << open);
	CHECK(open < closed);
}

TEST_CASE("step() is deterministic") {
	auto run = []() {
		ThermalGrid g = make_room(16, MAT_WOOD, true);
		g.add_heat_source(8, 8, 700.0f);
		g.add_heat_source(9, 8, 250.0f);
		for (int i = 0; i < 1000; ++i) {
			g.step(0.1f);
		}
		return g.snapshot();
	};
	const std::vector<float> a = run();
	const std::vector<float> b = run();
	REQUIRE(a.size() == b.size());
	CHECK(std::memcmp(a.data(), b.data(), a.size() * sizeof(float)) == 0);
}

TEST_CASE("sub-stepping keeps an explicit Euler step stable") {
	// Insulation has a small capacity and a zero-ish conductivity; a large dt
	// must still not explode. 1000 degC ambient with a 1 s tick is far outside
	// the single-step stability region.
	ThermalGrid g;
	g.setup(8, 8, 1.0f);
	g.set_material_rect(0, 0, 8, 8, MAT_INSULATION);
	g.fill_temperature(0.0f);
	g.set_ambient(1000.0f, 0.0f);
	g.set_exposed_rect(0, 0, 8, 8, true);
	for (int i = 0; i < 50; ++i) {
		g.step(1.0f);
		const float t = g.get_temperature(3, 3);
		REQUIRE(std::isfinite(t));
		CHECK(t <= 1000.0f + 1.0f);
	}
	CHECK(g.last_substeps() >= 1);
}

TEST_CASE("active-set stepping skips resting cells") {
	ThermalGrid g;
	g.setup(32, 32, 1.0f);
	g.set_material_rect(0, 0, 32, 32, MAT_STONE);
	g.fill_temperature(-5.0f);
	g.reset_stats();
	for (int i = 0; i < 10; ++i) {
		g.step_active(0.1f);
	}
	// Everything is at rest, so no cell should need work.
	CHECK(g.simulated_cells() == 0);
}

TEST_CASE("benchmark: 128x128 tick budget") {
	// Budget from the brief: < 0.5 ms per tick on desktop for 128x128.
	ThermalGrid g;
	g.setup(128, 128, 1.0f);
	g.set_material_rect(0, 0, 128, 128, MAT_STONE);
	g.set_material_rect(40, 40, 48, 48, MAT_AIR);
	g.set_exposed_rect(0, 0, 128, 128, true);
	g.set_exposed_rect(40, 40, 48, 48, false);
	g.fill_temperature(-12.0f);
	g.set_ambient(-25.0f, 3.0f);
	g.add_heat_source(64, 64, 2000.0f);

	const int ticks = 200;
	auto t0 = std::chrono::steady_clock::now();
	for (int i = 0; i < ticks; ++i) {
		g.step(0.1f);
	}
	auto t1 = std::chrono::steady_clock::now();
	const double ms = std::chrono::duration<double, std::milli>(t1 - t0).count() / ticks;
	MESSAGE("128x128 step: " << ms << " ms/tick");
	// Generous bound for CI machines; the desktop budget is 0.5 ms.
	CHECK(ms < 5.0);
}
