#include "factory/waterwheel.hpp"

#include <cstdlib>
#include <iostream>

namespace w = factory::waterwheel;
namespace m = factory::mechanics;

void check(bool value, const char* message) {
    if (!value) { std::cerr << message << '\n'; std::exit(1); }
}

int main() {
    w::Sample water{0, -8, 0, 6};
    check(w::rate(2, 4, m::Axis::x, water) == m::Rate{-3, 2}, "downstream flow turns X axle negatively");
    water.velocity_z = -6;
    check(w::rate(2, 4, m::Axis::x, water) == m::Rate{3, 2}, "reversed flow reverses rotation");
    water.velocity_z = 3;
    check(w::rate(2, 4, m::Axis::x, water) == m::Rate{-3, 4}, "half flow gives half speed");
    check(w::rate(2, 8, m::Axis::x, water) == m::Rate{-3, 8}, "larger radius turns more slowly");
    water.velocity_x = 5;
    check(w::rate(2, 4, m::Axis::z, water) == m::Rate{5, 4}, "Z axle uses X flow with right handed sign");
    water.velocity_x = 0;
    check(w::rate(2, 4, m::Axis::z, water) == m::Rate{0, 1}, "axial flow does not turn wheel");
    check(w::rate(4, 4, m::Axis::x, water) == m::Rate{0, 1}, "rim touching surface has no immersion");
    check(w::rate(-4, 4, m::Axis::x, water) == m::Rate{0, 1}, "rim touching bed cannot drive");
    check(w::rate(-1, 4, m::Axis::x, water) == m::Rate{0, 1}, "submerged axle is outside undershot model");
    check(!w::rate(0, 0, m::Axis::x, water), "zero radius is invalid");
    check(!w::rate(0, 4, m::Axis::y, water), "vertical axle is invalid");
    water.bed = water.surface;
    check(!w::rate(0, 4, m::Axis::x, water), "empty water profile is invalid");
    std::cout << "12 waterwheel flow controls passed\n";
}
