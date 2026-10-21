#include "factory/waterflow.hpp"

#include <array>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>

using factory::waterflow::Cell;
using factory::waterflow::Terrain;
using factory::waterflow::derive;

void check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

Terrain channel(bool broad, bool wall = false) {
    Terrain terrain{{-2, -1, -0.5, 0, 0.5, 1, 2}, {}, 0.25};
    for (const auto z : terrain.axis) {
        for (const auto x : terrain.axis) {
            auto bed = std::abs(x) < (broad ? 1.5 : 0.75) ? -2.0 : 0.7;
            if (wall && z == -0.5) bed = 0.7;
            terrain.heights.push_back(bed);
        }
    }
    return terrain;
}

void continuous_bank_clearance() {
    Terrain ridge{{-2, 0, 0.03, 0.04, 0.05, 1, 2}, {}, 0.25};
    for (const auto z : ridge.axis) {
        (void)z;
        for (const auto x : ridge.axis) ridge.heights.push_back(x == 0.04 ? 1.0 : -2.0);
    }
    const std::vector<Cell> across{{0, 0, 200}, {4, 0, 196}};
    const auto blocked = derive(ridge, across);
    check(blocked.has_value(), "The thin-bank terrain and both wet cell centers are valid inputs.");
    std::cout << "thin bank velocity: " << blocked->at({0, 0}).velocity_x << ','
              << blocked->at({0, 0}).velocity_z << '\n';
    check(blocked->at({0, 0}).velocity_x == 0,
          "A thin bank between the former equally spaced probes blocks current.");
    for (auto& height : ridge.heights) if (height == 1.0) height = 0.2;
    const auto submerged = derive(ridge, across);
    check(submerged && submerged->at({0, 0}).velocity_x > 0,
          "Lowering that exact ridge below the water restores the connection.");

    Terrain quarter;
    quarter.meters_per_step = 0.4125;
    for (int index = -4; index <= 8; ++index) quarter.axis.push_back(index * 0.25);
    for (const auto z : quarter.axis) {
        (void)z;
        for (const auto x : quarter.axis) quarter.heights.push_back(x == 0.25 ? 0.14 : -1.0);
    }
    const std::vector<Cell> actual_grid{{0, 0, 32}, {4, 0, 31}};
    const auto shallow = derive(quarter, actual_grid);
    check(shallow && shallow->at({0, 0}).velocity_x == 0,
          "The opening's actual terrain spacing and 1.65 metre neighbor also respect a shallow crest.");
    for (auto& height : quarter.heights) if (height == 0.14) height = 0.12;
    const auto clear = derive(quarter, actual_grid);
    check(clear && clear->at({0, 0}).velocity_x > 0,
          "Submerging the current-grid crest permits downstream current again.");

    // The line stays inside one grid cell but crosses its triangle diagonal.
    Terrain diagonal{{-2, 2}, {0.501, -2, -2, 0.501}, 0.25};
    const std::vector<Cell> through{{0, 4, 200}, {4, 0, 196}};
    const auto crest = derive(diagonal, through);
    check(crest && crest->at({0, 4}).velocity_x == 0 && crest->at({0, 4}).velocity_z == 0,
          "An interior triangle ridge blocks a path whose grid-edge endpoints are wet.");
    diagonal.heights = {0.49, -2, -2, 0.49};
    const auto open = derive(diagonal, through);
    check(open && open->at({0, 4}).velocity_x > 0 && open->at({0, 4}).velocity_z < 0,
          "A submerged triangle diagonal retains the actual downhill direction.");
}

int main() {
    try {
        continuous_bank_clearance();
        const std::vector<Cell> downhill{{0, -4, 0}, {0, 0, -1}, {0, 4, -2}};
        const auto narrow = derive(channel(false), downhill);
        const auto wide = derive(channel(true), downhill);
        check(narrow && wide, "both emitted beds admit the same connected water levels");
        const auto a = narrow->at({0, -4});
        const auto b = wide->at({0, -4});
        check(a.velocity_x == 0 && a.velocity_z > b.velocity_z && b.velocity_z > 0,
              "a narrow bed accelerates downhill current relative to a broad bed");
        check(narrow->at({0, 4}).velocity_z == 0, "no downhill outlet means stationary water");
        const auto blocked = derive(channel(false, true), {{0, -4, 0}, {0, 0, -1}});
        check(blocked && blocked->at({0, -4}).velocity_z == 0,
              "a solid bank between two wet cells blocks their apparent downhill connection");
        const auto basin = derive(channel(true), {{0, -4, 0}, {0, 0, 0}, {0, 4, 1}});
        check(basin && basin->at({0, -4}).velocity_z == 0,
              "a level or rising outlet cannot draw current uphill from a basin");
        check(!derive(channel(true), {{0, -4, 0}, {0, -4, -1}}),
              "duplicate water cells cannot replace one another");
        check(!derive(channel(true), {{8, -4, 0}}),
              "a water level below solid terrain cannot create a wet cell");
        auto invalid = channel(true);
        invalid.axis[2] = invalid.axis[1];
        check(!derive(invalid, downhill), "a repeated terrain coordinate is rejected before interpolation");
        invalid = channel(true);
        invalid.heights[0] = std::numeric_limits<double>::quiet_NaN();
        check(!derive(invalid, downhill), "nonfinite terrain is rejected before water routing");
        std::cout << "terrain waterflow controls passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
