#include "factory/material_state_codec.hpp"

#include <iostream>
#include <limits>
#include <stdexcept>
#include <variant>

namespace m = factory::materials;
namespace v = factory::values;

namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

m::Config recipe() {
    m::Config result{1, 1, 3};
    result.raw_mass = 4;
    result.plate_mass = 3;
    result.sheet_mass = 12;
    return result;
}

void support_fit_rule() {
    const m::DropPoint origin{8, 4, 12};
    const std::vector<m::DropPoint> one_wide{origin};
    const std::vector<m::DropPoint> four_cell_floor{{8, 4, 12}, {12, 4, 12},
        {8, 4, 16}, {12, 4, 16}};
    check(m::fits_supported_workcells(origin, m::work_footprint(m::WorkOutput::plate), 0,
              one_wide) &&
          !m::fits_supported_workcells(origin, m::work_footprint(m::WorkOutput::sheet), 0,
              one_wide),
        "One supported belt tile fits a plate but cannot hold the broad unfinished lot.");
    for (m::Quantity rotation = 0; rotation < 4; ++rotation)
        check(m::fits_supported_workcells(origin, m::sheet_footprint(), rotation,
                  four_cell_floor),
            "The complete two-by-two floor supports one oriented sheet at the same height.");
    check(!m::fits_supported_workcells(origin, m::sheet_footprint(), 0,
              {{8, 4, 12}, {12, 4, 12}, {8, 4, 16}}),
        "A missing corner cannot be treated as support for a whole sheet.");
    check(m::fits_supported_workcells(origin, {1, 2}, 1,
              {{8, 4, 12}, {12, 4, 12}}) &&
          !m::fits_supported_workcells(origin, {1, 2}, 0,
              {{8, 4, 12}, {12, 4, 12}}),
        "A non-square future item must fit its actual quarter-turn orientation.");
    check(!m::fits_supported_workcells(origin, m::sheet_footprint(), 4,
              four_cell_floor),
        "An unsupported orientation cannot open a transport path.");
    const m::DropPoint destination{8, 4, 20};
    const std::vector<m::DropPoint> complete_route{{8, 4, 12}, {12, 4, 12},
        {8, 4, 16}, {12, 4, 16}, {8, 4, 20}, {12, 4, 20},
        {8, 4, 24}, {12, 4, 24}};
    check(m::fits_clear_swept_workcells(origin, destination, m::sheet_footprint(), 2,
              complete_route, {}),
        "A two-wide floor supports the entire oriented sheet sweep.");
    check(m::fits_clear_swept_workcells(destination, origin, m::sheet_footprint(), 2,
              complete_route, {}),
        "Reversing a level route checks the same whole workpiece corridor.");
    auto missing_middle = complete_route;
    missing_middle.erase(missing_middle.begin() + 3);
    check(!m::fits_clear_swept_workcells(origin, destination, m::sheet_footprint(), 2,
              missing_middle, {}),
        "Endpoint support cannot excuse a missing middle channel cell.");
    check(!m::fits_clear_swept_workcells(origin, destination, m::sheet_footprint(), 2,
              complete_route, {{12, 4, 16}}),
        "A blocked cell anywhere under the moving sheet refuses the route.");
    check(!m::swept_workcells(origin, {12, 4, 20}, m::sheet_footprint(), 2) &&
          !m::swept_workcells(origin, {8, 8, 20}, m::sheet_footprint(), 2) &&
          !m::swept_workcells(origin, {8, 4, 19}, m::sheet_footprint(), 2),
        "A level straight channel cannot silently bend, climb or use a fractional workcell.");
    check(!m::swept_workcells(origin,
              {std::numeric_limits<m::Quantity>::max(), 4, 12},
              m::sheet_footprint(), 2),
        "An untrusted remote endpoint cannot overflow the bounded route check.");
    check(m::channel_spec(m::Component::channel_narrow_x) ==
              m::ChannelSpec{{1, 1}, 0} &&
          m::channel_spec(m::Component::channel_narrow_z) ==
              m::ChannelSpec{{1, 1}, 2} &&
          m::channel_workcells(m::Component::channel_broad_x, origin) ==
              std::vector<m::DropPoint>{{8, 4, 12}, {8, 4, 16}} &&
          m::channel_workcells(m::Component::channel_broad_z, origin) ==
              std::vector<m::DropPoint>{{8, 4, 12}, {12, 4, 12}} &&
          !m::channel_spec(m::Component::anvil),
        "A selected channel segment has one fixed cardinal rail direction and complete width.");
    const m::DropPoint long_origin{0, 4, 0};
    const m::DropPoint long_destination{0, 4, 4 * 1200};
    std::vector<m::DropPoint> long_support;
    for (m::Quantity z = 0; z <= 1201; ++z) {
        long_support.push_back({0, 4, 4 * z});
        long_support.push_back({4, 4, 4 * z});
    }
    const auto long_sweep = m::swept_workcells(long_origin, long_destination,
        m::sheet_footprint(), 0);
    check(long_sweep && long_sweep->size() == long_support.size() &&
          m::fits_clear_swept_workcells(long_origin, long_destination,
              m::sheet_footprint(), 0, long_support, {}),
        "A long two-wide corridor counts distinct cells rather than repeated footprint samples.");
    const auto full_sweep = m::swept_workcells(long_origin, {0, 4, 4 * 2046},
        m::sheet_footprint(), 0);
    check(full_sweep && full_sweep->size() == m::maximum_drop_points &&
          !m::swept_workcells(long_origin, {0, 4, 4 * 2047}, m::sheet_footprint(), 0),
        "The route accepts its exact distinct-cell cap and refuses the next cell pair.");
}

void formed_sheet_and_blocked_output() {
    const auto config = recipe();
    const m::Path path{};
    const m::DropPoint work{0, 0, 0};
    m::State state;
    state.initial_units = 6;
    state.cargo = {{"P", m::Cargo{6, 0, {}}}, {"Q", {}}};
    check(m::validate(state, config, path) == m::Error::none,
        "Six finite chunks permit two batches without gifting broad work.");
    check(m::feed_broad_press(state, config, path, "P", work) == m::Error::none &&
          state.cargo.at("P").raw_units == 3 &&
          state.dropped_material.at(work).work_lots.front().id == 1 &&
          state.dropped_material.at(work).work_lots.front().remaining_ticks == 3,
        "Joining three chunks allocates one identity-bearing broad batch at the work face.");
    m::BeltLane narrow;
    narrow.slots = {state.dropped_material.at(work), std::nullopt};
    check(!m::advance_belt_lane(narrow, m::work_subticks_per_tick, 1),
        "A one-wide belt cannot transport an unfinished two-by-two workpiece.");
    auto forged_belt = state;
    forged_belt.dropped_material.clear();
    forged_belt.belt_lanes.emplace("narrow", narrow);
    check(m::validate(forged_belt, config, path) == m::Error::invalid_state,
        "A saved one-wide belt slot cannot claim custody of broad partial work.");
    check(m::turn_broad_press(state, config, path, work, 4) ==
          m::Error::unavailable_recipe && state.dropped_material.at(work).work_lots.front().remaining_ticks == 3,
        "Invalid sheet orientation cannot start a batch or consume its input.");
    check(m::turn_broad_press(state, config, path, work, 2) == m::Error::none &&
          state.dropped_material.at(work).work_lots.front().recipe.output == m::WorkOutput::sheet &&
          state.dropped_material.at(work).work_lots.front().remaining_ticks == 2,
        "One powered stroke advances the original sheet-bound serial without changing mass.");
    check(m::turn_broad_press(state, config, path, work, 2, 2048) == m::Error::none &&
          state.dropped_material.at(work).work_lots.front().remaining_ticks == 2 &&
          state.dropped_material.at(work).work_lots.front().completed_subticks == 2048,
        "A half-speed connected drive only advances a half stroke per authority tick.");
    check(m::turn_broad_press(state, config, path, work, 2, 2048) == m::Error::none &&
          state.dropped_material.at(work).work_lots.front().remaining_ticks == 1,
        "The broad batch retains exact partial progress at its work face.");
    check(m::turn_broad_press(state, config, path, work, 2) == m::Error::none &&
          state.dropped_material.at(work).sheets == std::vector<m::Sheet>{{1, 2}} &&
          m::validate(state, config, path) == m::Error::none,
        "One oriented twelve-mass sheet remains on its four-anvil working area.");
    const auto formed = state;
    check(m::turn_broad_press(state, config, path, work, 2) ==
          m::Error::unavailable_input && state == formed,
        "Repeating the release cannot duplicate the sheet.");
    check(m::feed_broad_press(state, config, path, "P", work) ==
          m::Error::unavailable_output && state == formed,
        "The completed sheet blocks the next broad batch at the same real work area.");
    check(m::pickup_material(state, config, path, "Q", work) == m::Error::none &&
          state.cargo.at("Q").sheets == std::vector<m::Sheet>{{1, 2}} &&
          m::validate(state, config, path) == m::Error::none,
        "A second actor clears the sheet without a teleporting output route.");
    check(m::feed_broad_press(state, config, path, "P", work) == m::Error::none &&
          state.cargo.at("P").raw_units == 0 &&
          state.dropped_material.at(work).work_lots.front().id == 2,
        "The same work area can accept a second finite batch only after physical sheet recovery.");
    const auto encoded = m::encode_material_state(state, config, path, {"P", "Q"});
    check(std::holds_alternative<v::Value>(encoded),
        "One carried sheet and the next staged batch encode as a material checkpoint.");
    if (const auto* value = std::get_if<v::Value>(&encoded)) {
        const auto restored = m::decode_material_state(*value, config, path, {"P", "Q"});
        check(std::holds_alternative<m::State>(restored) &&
              std::get<m::State>(restored) == state,
            "Fresh material restore preserves the sheet identity, orientation and finite mass.");
    }
    auto forged = state;
    forged.cargo.at("Q").sheets.front().rotation = 4;
    check(m::validate(forged, config, path) == m::Error::invalid_state,
        "An invalid sheet orientation refuses without a silent coercion.");
    m::State duplicated;
    duplicated.initial_units = 6;
    duplicated.next_work_id = 2;
    duplicated.cargo = {{"P", {}}, {"Q", {}}};
    duplicated.cargo.at("P").sheets.push_back({1, 0});
    duplicated.cargo.at("Q").sheets.push_back({1, 0});
    check(m::validate(duplicated, config, path) == m::Error::invalid_state,
        "Two mass-balanced sheet holders cannot share one forged serial.");
}

void recovered_broad_work() {
    const auto config = recipe();
    const m::Path path{};
    const m::DropPoint work{0, 4, 0};
    m::State state;
    state.initial_units = 3;
    state.cargo = {{"P", m::Cargo{3, 0, {}}}};
    check(m::feed_broad_press(state, config, path, "P", work) == m::Error::none &&
          m::turn_broad_press(state, config, path, work, 0) == m::Error::none &&
          m::turn_broad_press(state, config, path, work, 0) == m::Error::none,
        "A raised broad workpiece can start and advance on the shared height grid.");
    const auto partial = state.dropped_material.at(work).work_lots.front();
    check(m::pickup_material(state, config, path, "P", work) == m::Error::none &&
          state.cargo.at("P").work_lots.front() == partial,
        "Reclaiming partial broad work retains its original recipe and progress.");
    const auto carried = state;
    check(m::feed_broad_press(state, config, path, "P", work, 2) ==
          m::Error::unavailable_input && state == carried,
        "A forged serial cannot reinsert a different carried workpiece.");
    check(m::feed_broad_press(state, config, path, "P", work, partial.id) == m::Error::none &&
          state.dropped_material.at(work).work_lots.front() == partial,
        "The same broad work serial returns to its supported working area.");
    check(m::turn_broad_press(state, config, path, work, 0) == m::Error::none &&
          state.dropped_material.at(work).sheets == std::vector<m::Sheet>{{partial.id, 0}},
        "One resumed stroke completes the original twelve-mass workpiece.");
}

void one_owner_loose_transfer() {
    const auto config = recipe();
    const m::Path path{};
    const m::DropPoint source{0, 4, 0};
    const m::DropPoint occupied{4, 4, 0};
    const m::DropPoint destination{8, 4, 0};
    m::Cargo sheet;
    sheet.sheets.push_back({1, 2});
    m::Cargo offcut;
    offcut.offcuts = 1;
    m::Cargo mixed{1, 1, {}};
    check(m::single_loose_item(m::Cargo{1, 0, {}}) ==
              m::LooseItem{m::LooseForm::raw, {1, 1}, 0, 0} &&
          m::single_loose_item(m::Cargo{0, 1, {}}) ==
              m::LooseItem{m::LooseForm::plate, {1, 1}, 0, 0} &&
          m::single_loose_item(offcut) ==
              m::LooseItem{m::LooseForm::offcut, {1, 1}, 0, 0} &&
          m::single_loose_item(sheet) ==
              m::LooseItem{m::LooseForm::sheet, {2, 2}, 2, 1} &&
          !m::single_loose_item(mixed),
        "The same one-item custody rule identifies stock, plates, offcuts and oriented sheets.");
    m::State state;
    state.initial_units = 5;
    state.next_work_id = 2;
    state.cargo = {{"P", {}}};
    state.dropped_material.emplace(source, sheet);
    state.dropped_material.emplace(occupied, m::Cargo{1, 0, {}});
    state.dropped_material.emplace(m::DropPoint{12, 4, 0}, m::Cargo{0, 1, {}});
    state.dropped_material.emplace(m::DropPoint{16, 4, 0}, offcut);
    check(m::validate(state, config, path) == m::Error::none,
        "Sheet, stock, plate and offcut are four finite loose items with conserved mass.");
    const auto before = state;
    check(m::move_loose_item(state, config, path, source, occupied) ==
              m::Error::unavailable_output && state == before,
        "An occupied receiver cannot take or duplicate the sheet.");
    check(m::move_loose_item(state, config, path, source, destination) == m::Error::none &&
          !state.dropped_material.contains(source) &&
          state.dropped_material.at(destination) == sheet &&
          m::validate(state, config, path) == m::Error::none,
        "One accepted handoff moves the same sheet serial and orientation exactly once.");
    check(m::move_loose_item(state, config, path, occupied, {28, 4, 0}) == m::Error::none &&
          m::move_loose_item(state, config, path, {12, 4, 0}, {20, 4, 0}) == m::Error::none &&
          m::move_loose_item(state, config, path, {16, 4, 0}, {24, 4, 0}) == m::Error::none &&
          state.dropped_material.at({28, 4, 0}) == m::Cargo{1, 0, {}} &&
          state.dropped_material.at({20, 4, 0}) == m::Cargo{0, 1, {}} &&
          state.dropped_material.at({24, 4, 0}) == offcut &&
          m::validate(state, config, path) == m::Error::none,
        "The same handoff preserves separate stock, plate and offcut forms without changing mass.");
    const auto moved = state;
    check(m::move_loose_item(state, config, path, source, {12, 4, 0}) ==
              m::Error::unavailable_input && state == moved,
        "A stale source cannot move the already transferred sheet again.");
    const auto encoded = m::encode_material_state(state, config, path, {"P"});
    check(std::holds_alternative<v::Value>(encoded),
        "A transferred sheet and its blocked neighboring stock encode at the new owner.");
    if (const auto* value = std::get_if<v::Value>(&encoded)) {
        const auto restored = m::decode_material_state(*value, config, path, {"P"});
        check(std::holds_alternative<m::State>(restored) &&
              std::get<m::State>(restored) == state,
            "Save and reopen preserve the single transferred sheet owner and mass.");
    }
}
}  // namespace

int main() {
    try {
        support_fit_rule();
        formed_sheet_and_blocked_output();
        recovered_broad_work();
        one_owner_loose_transfer();
        std::cout << "broad_sheet_mass_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "broad_sheet_mass_test: " << error.what() << '\n';
        return 1;
    }
}
