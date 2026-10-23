#include "factory/material_state_codec.hpp"

#include <iostream>
#include <variant>

namespace m = factory::materials;
namespace v = factory::values;

int main() {
    int checks = 0;
    int failures = 0;
    const auto check = [&](bool condition, const char* message) {
        ++checks;
        if (!condition) {
            ++failures;
            std::cerr << "FAIL: " << message << '\n';
        }
        return condition;
    };
    m::Config recipe{1, 1, 2};
    recipe.raw_mass = 4;
    recipe.plate_mass = 3;
    recipe.sheet_mass = 12;
    recipe.manual_ore = m::OreSite{"copper", {0, 0, 0}};
    const m::Path path{};
    const m::DropPoint work{4, 0, 0}, exit{8, 0, 0};
    m::State state;
    state.initial_units = 1;
    state.cargo.emplace("P", m::Cargo{});
    state.dropped_material.emplace(work, m::Cargo{1, 0, {}});
    check(m::validate(state, recipe, path) == m::Error::none,
          "One four-unit copper stock is conserved before pressing.");
    const auto before = state;
    check(m::turn_press(state, recipe, path, work, exit) == m::Error::none &&
          state.dropped_material.at(work).work_lots.size() == 1 &&
          state.dropped_material.at(work).work_lots.front().remaining_ticks == 2,
          "First crank allocates a whole copper work lot without shaping it yet.");
    check(m::turn_press(state, recipe, path, work, exit) == m::Error::none &&
          state.dropped_material.at(work).work_lots.front().remaining_ticks == 1,
          "Second crank advances the same physical lot.");
    check(m::turn_press(state, recipe, path, work, exit) == m::Error::none &&
          state.dropped_material.at(exit).products == 1 &&
          state.dropped_material.at(work).offcuts == 1 &&
          m::validate(state, recipe, path) == m::Error::none,
          "One stroke leaves a three-unit plate and a separate recoverable offcut.");
    const auto formed = state;
    check(m::turn_press(state, recipe, path, work, exit) == m::Error::unavailable_input &&
          state == formed, "An offcut cannot silently become another plate or be erased by retry.");
    m::State blocked = formed;
    blocked.initial_units = 2;
    blocked.cargo.at("P").offcuts = 1;
    blocked.dropped_material.at(work) = m::Cargo{1, 0, {}};
    check(m::validate(blocked, recipe, path) == m::Error::none,
          "A second chunk can wait while the first plate occupies the outlet.");
    check(m::turn_press(blocked, recipe, path, work, exit) == m::Error::none &&
          m::turn_press(blocked, recipe, path, work, exit) == m::Error::none &&
          m::turn_press(blocked, recipe, path, work, exit) == m::Error::none &&
          blocked.dropped_material.at(work).work_lots.front().remaining_ticks == 0,
          "The second lot becomes ready without consuming an occupied output.");
    const auto waiting = blocked;
    check(m::turn_press(blocked, recipe, path, work, exit) == m::Error::unavailable_output &&
          blocked == waiting, "A blocked stroke preserves its ready lot and all eight mass units.");
    check(m::pickup_material(blocked, recipe, path, "P", exit) == m::Error::none &&
          m::turn_press(blocked, recipe, path, work, exit) == m::Error::none &&
          blocked.dropped_material.at(work).offcuts == 1 &&
          blocked.dropped_material.at(exit).products == 1 &&
          m::validate(blocked, recipe, path) == m::Error::none,
          "Clearing the outlet releases the held plate and its own distinct offcut.");
    check(m::pickup_material(state, recipe, path, "P", work) == m::Error::none &&
          state.cargo.at("P").offcuts == 1 && !state.dropped_material.contains(work),
          "The actor can explicitly pick up the retained offcut.");
    check(m::pickup_material(state, recipe, path, "P", exit) == m::Error::none &&
          state.cargo.at("P").products == 1 &&
          m::validate(state, recipe, path) == m::Error::none,
          "Plate and offcut remain distinct in actor custody.");
    const auto encoded = m::encode_material_state(state, recipe, path, {"P"});
    check(std::holds_alternative<v::Value>(encoded), "Copper cargo encodes as a typed material checkpoint.");
    if (const auto* value = std::get_if<v::Value>(&encoded)) {
        const auto restored = m::decode_material_state(*value, recipe, path, {"P"});
        check(std::holds_alternative<m::State>(restored) && std::get<m::State>(restored) == state,
              "Reload retains both plate and offcut with exact mass.");
        const auto old_recipe = m::Config{1, 1, 2};
        const auto wrong_profile = m::decode_material_state(*value, old_recipe, path, {"P"});
        check(std::holds_alternative<m::CodecRefusal>(wrong_profile),
              "The one-to-one fixture cannot load a copper checkpoint as its own schema.");
    }
    state.cargo.at("P").offcuts = 0;
    check(m::validate(state, recipe, path) == m::Error::invalid_state,
          "Removing even one offcut unit breaks native mass conservation.");
    check(before != formed && checks == 15, "The fixture exercised actual stock and formed states.");
    std::cout << "{\"checks\":" << checks << ",\"evidence\":\"copper_material_mass\"}\n";
    return failures == 0 && checks == 16 ? 0 : 1;
}
