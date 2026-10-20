#include "factory/materials.hpp"

#include <iostream>

namespace material = factory::materials;

int main() {
    const material::Config config{2, 2, 2};
    const material::Path path{true, true, true, true, true, true};
    material::State state{8, {8, 0, 0, 0, 0, 0}, {}, 0};
    auto advance = [&](int ticks) {
        for (int tick = 0; tick < ticks; ++tick) {
            const auto error = material::step(state, config, path);
            if (error != material::Error::none) {
                std::cerr << "Material step refused: " << material::error_name(error) << '\n';
                return false;
            }
        }
        return true;
    };
    // Independent literal checkpoints from the existing two-input Core fixture.
    if (!advance(7) || state.stock != material::Stock{1, 1, 1, 1, 2, 1} || state.remaining != 2) {
        std::cerr << "The first output does not match the declared fixture.\n";
        return 1;
    }
    if (!advance(5) || state.stock != material::Stock{0, 1, 1, 2, 2, 1} || state.remaining != 0) {
        std::cerr << "Blocked ready work does not match the declared fixture.\n";
        return 1;
    }
    for (int tick = 0; tick < 32; ++tick) {
        if (state.stock.output > 0 &&
            material::retrieve(state, config, path, "P", 1) != material::Error::none) return 1;
        if (!advance(1)) return 1;
    }
    if (state.stock.output > 0 &&
        material::retrieve(state, config, path, "P", 1) != material::Error::none) return 1;
    if (state.stock != material::Stock{} || state.remaining != 0 ||
        state.inventories != std::map<std::string, material::Quantity>{{"P", 4}}) {
        std::cerr << "Final custody does not contain exactly four products.\n";
        return 1;
    }
    std::cout << "{\"status\":\"pass\",\"evidence\":\"native_headless_material_fixture\","
                 "\"initial_input_units\":8,\"input_units_per_product\":2,"
                 "\"final_P_products\":4,\"remaining_raw_units\":0}\n";
    return 0;
}
