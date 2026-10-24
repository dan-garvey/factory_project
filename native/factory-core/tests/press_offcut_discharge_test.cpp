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
    };
    m::Config recipe{1, 1, 2};
    recipe.raw_mass = 4;
    recipe.plate_mass = 3;
    recipe.sheet_mass = 12;
    m::State state;
    state.initial_units = 6;
    state.cargo.emplace("P", m::Cargo{5, 0, {}});
    const m::DropPoint work{0, 0, 0}, plate_exit{-1, 0, 0}, tray{0, 0, 1};
    state.dropped_material.emplace(work, m::Cargo{1, 0, {}});
    m::PressStep press{work, plate_exit};
    press.offcut_receiver = tray;
    const m::Path path{};
    const auto tick = [&] { return m::step_presses(state, recipe, path, {press}); };
    const auto feed = [&] {
        --state.cargo.at("P").raw_units;
        state.dropped_material.emplace(work, m::Cargo{1, 0, {}});
        check(m::validate(state, recipe, path) == m::Error::none,
              "A newly fed chunk remains in the conserved native ledger.");
    };
    check(m::validate(state, recipe, path) == m::Error::none,
          "Six copper chunks begin in actor and work-face custody.");
    for (int cycle = 0; cycle < 4; ++cycle) {
        if (cycle != 0) feed();
        check(tick() == m::Error::none && tick() == m::Error::none &&
              tick() == m::Error::none,
              "The continuously powered press completes one small stroke.");
        check(!state.dropped_material.contains(work) &&
              state.dropped_material.at(plate_exit).products == 1 &&
              state.dropped_material.at(tray).offcuts == cycle + 1 &&
              m::validate(state, recipe, path) == m::Error::none,
              "The plate and the receiver's separate offcut count conserve every chunk.");
        check(m::pickup_material(state, recipe, path, "P", plate_exit) == m::Error::none,
              "An actor can remove the plate without clearing the offcut receiver.");
    }
    check(state.cargo.at("P").products == 4 &&
          state.dropped_material.at(tray).offcuts == m::press_offcut_receiver_capacity,
          "Four unattended strokes fill one finite tray without manual offcut pickup.");
    const auto encoded = m::encode_material_state(state, recipe, path, {"P"});
    const auto restored = std::holds_alternative<v::Value>(encoded) ?
        m::decode_material_state(std::get<v::Value>(encoded), recipe, path, {"P"}) :
        m::MaterialDecoding{m::CodecRefusal{}};
    check(std::holds_alternative<m::State>(restored) &&
          std::get<m::State>(restored) == state,
          "A full offcut receiver and four plates survive exact material checkpoint decoding.");

    feed();
    check(tick() == m::Error::none && tick() == m::Error::none &&
          tick() == m::Error::none &&
          state.dropped_material.at(work).work_lots.front().remaining_ticks == 0 &&
          !state.dropped_material.contains(plate_exit),
          "A full tray holds finished work safely before plate release.");
    const auto waiting = state;
    check(tick() == m::Error::none && state == waiting,
          "Repeated power cannot duplicate a plate or erase blocked work.");
    check(m::pickup_material(state, recipe, path, "P", tray) == m::Error::none &&
          state.cargo.at("P").offcuts == 4 && tick() == m::Error::none &&
          state.dropped_material.at(tray).offcuts == 1 &&
          state.dropped_material.at(plate_exit).products == 1 &&
          !state.dropped_material.contains(work),
          "Clearing the tray resumes the waiting plate and its separately counted offcut.");
    check(m::pickup_material(state, recipe, path, "P", plate_exit) == m::Error::none,
          "The fifth plate remains an ordinary recoverable material item.");

    // An incompatible item cannot be used as an implicit offcut container.
    --state.cargo.at("P").products;
    ++state.cargo.at("P").offcuts;
    state.dropped_material.at(tray).offcuts = 0;
    state.dropped_material.at(tray).products = 1;
    check(m::validate(state, recipe, path) == m::Error::none,
          "Exchanging one plate for one offcut preserves exact copper mass.");
    feed();
    check(tick() == m::Error::none && tick() == m::Error::none &&
          tick() == m::Error::none &&
          state.dropped_material.at(work).work_lots.front().remaining_ticks == 0 &&
          !state.dropped_material.contains(plate_exit),
          "A plate occupying the tray cannot silently accept an offcut.");
    check(m::pickup_material(state, recipe, path, "P", tray) == m::Error::none &&
          tick() == m::Error::none &&
          state.dropped_material.at(tray).offcuts == 1 &&
          state.dropped_material.at(plate_exit).products == 1 &&
          m::validate(state, recipe, path) == m::Error::none,
          "Removing the incompatible item resumes the sixth stroke without losing copper.");

    const auto before_bad_path = state;
    auto bad = press;
    bad.offcut_receiver = work;
    check(m::step_presses(state, recipe, path, {bad}) == m::Error::invalid_path &&
          state == before_bad_path,
          "A receiver cannot overlap a press work point or mutate accepted material.");
    std::cout << "{\"checks\":" << checks << ",\"failures\":" << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
