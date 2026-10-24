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

    m::State received;
    received.initial_units = 6;
    received.cargo.emplace("P", m::Cargo{5, 0, {}});
    received.cargo.emplace("Q", m::Cargo{});
    received.dropped_material.emplace(work, m::Cargo{1, 0, {}});
    auto fitted = press;
    fitted.plate_receiver = true;
    for (int cycle = 0; cycle < 4; ++cycle) {
        if (cycle != 0) {
            --received.cargo.at("P").raw_units;
            received.dropped_material.emplace(work, m::Cargo{1, 0, {}});
        }
        for (int tick_index = 0; tick_index < 3; ++tick_index)
            check(m::step_presses(received, recipe, path, {fitted}) == m::Error::none,
                  "A fitted physical plate receiver accepts the next powered stroke.");
        check(received.dropped_material.at(plate_exit).products == cycle + 1 &&
              received.dropped_material.at(tray).offcuts == cycle + 1 &&
              m::validate(received, recipe, path) == m::Error::none,
              "Each finished plate remains in the outlet tray while its offcut stays in the side tray.");
    }
    const auto full_encoded = m::encode_material_state(received, recipe, path, {"P", "Q"});
    const auto full_restored = std::holds_alternative<v::Value>(full_encoded) ?
        m::decode_material_state(std::get<v::Value>(full_encoded), recipe, path, {"P", "Q"}) :
        m::MaterialDecoding{m::CodecRefusal{}};
    check(std::holds_alternative<m::State>(full_restored) &&
          std::get<m::State>(full_restored) == received,
          "Both full fitted trays preserve four products and four offcuts through material decoding.");
    --received.cargo.at("P").raw_units;
    received.dropped_material.emplace(work, m::Cargo{1, 0, {}});
    for (int tick_index = 0; tick_index < 3; ++tick_index)
        check(m::step_presses(received, recipe, path, {fitted}) == m::Error::none,
              "The fifth lot reaches its ready state without crossing the full outlets.");
    const auto blocked = received;
    check(received.dropped_material.at(work).work_lots.front().remaining_ticks == 0 &&
          m::step_presses(received, recipe, path, {fitted}) == m::Error::none && received == blocked,
          "A full plate receiver retains the exact fifth work without duplicating mass.");
    check(m::pickup_material(received, recipe, path, "Q", plate_exit) == m::Error::none &&
          received.cargo.at("Q").products == 4 &&
          m::step_presses(received, recipe, path, {fitted}) == m::Error::none &&
          received.dropped_material.at(work).work_lots.front().remaining_ticks == 0,
          "Clearing only the plate receiver leaves fifth work held by the full offcut tray.");
    check(m::pickup_material(received, recipe, path, "Q", tray) == m::Error::none &&
          received.cargo.at("Q").offcuts == 4 &&
          m::step_presses(received, recipe, path, {fitted}) == m::Error::none &&
          received.dropped_material.at(plate_exit).products == 1 &&
          received.dropped_material.at(tray).offcuts == 1 &&
          !received.dropped_material.contains(work) &&
          m::validate(received, recipe, path) == m::Error::none,
          "The second actor clears both separate holders and releases only the retained fifth plate.");

    m::Config pure{1, 1, 2};
    pure.raw_mass = 1;
    pure.plate_mass = 1;
    m::State manual;
    manual.initial_units = 5;
    manual.cargo.emplace("P", m::Cargo{4, 0, {}});
    manual.dropped_material.emplace(work, m::Cargo{1, 0, {}});
    for (int cycle = 0; cycle < 4; ++cycle) {
        if (cycle != 0) {
            --manual.cargo.at("P").raw_units;
            manual.dropped_material.emplace(work, m::Cargo{1, 0, {}});
        }
        for (int turn = 0; turn < 3; ++turn)
            check(m::turn_press(manual, pure, path, work, plate_exit, true) == m::Error::none,
                  "A fitted plate tray accepts an ordinary crank turn.");
        check(manual.dropped_material.at(plate_exit).products == cycle + 1 &&
              m::validate(manual, pure, path) == m::Error::none,
              "Manual products obey the same finite tray capacity as powered products.");
    }
    --manual.cargo.at("P").raw_units;
    manual.dropped_material.emplace(work, m::Cargo{1, 0, {}});
    for (int turn = 0; turn < 3; ++turn)
        check(m::turn_press(manual, pure, path, work, plate_exit, true) == m::Error::none,
              "A full plate tray preserves manual work until its product can leave.");
    check(manual.dropped_material.at(work).work_lots.front().remaining_ticks == 0 &&
          manual.dropped_material.at(plate_exit).products == 4,
          "A full plate tray does not duplicate the fifth manually formed product.");
    std::cout << "{\"checks\":" << checks << ",\"failures\":" << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
