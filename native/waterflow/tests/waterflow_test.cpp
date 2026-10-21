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

int main() {
    try {
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
