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
    m::State retained;
    retained.initial_units = 2;
    retained.cargo.emplace("P", m::Cargo{});
    retained.cargo.emplace("Q", m::Cargo{});
    retained.dropped_material.emplace(work, m::Cargo{1, 0, {}});
    retained.dropped_material.emplace(exit, m::Cargo{0, 1, {}});
    retained.dropped_material.at(exit).offcuts = 1;
    check(m::turn_press(retained, recipe, path, work, exit, false,
              m::PressOutputLocation::supported_work) == m::Error::none &&
          m::turn_press(retained, recipe, path, work, exit, false,
              m::PressOutputLocation::supported_work) == m::Error::none &&
          m::turn_press(retained, recipe, path, work, exit, false,
              m::PressOutputLocation::supported_work) == m::Error::none &&
          retained.dropped_material.at(work).products == 1 &&
          retained.dropped_material.at(work).offcuts == 1 &&
          retained.dropped_material.at(work).work_lots.empty() &&
          retained.dropped_material.at(exit).products == 1 &&
          m::validate(retained, recipe, path) == m::Error::none,
          "An occupied neighboring exit does not eject or block a newly formed supported plate.");
    const auto held_on_support = retained;
    check(m::turn_press(retained, recipe, path, work, exit, false,
              m::PressOutputLocation::supported_work) == m::Error::unavailable_input &&
          retained == held_on_support,
          "Another stroke cannot overwrite a finished plate or reprocess its offcut.");
    const auto retained_checkpoint = m::encode_material_state(retained, recipe, path, {"P", "Q"});
    m::MaterialDecoding decoded_retained = m::CodecRefusal{};
    if (const auto* value = std::get_if<v::Value>(&retained_checkpoint))
        decoded_retained = m::decode_material_state(*value, recipe, path, {"P", "Q"});
    check(std::holds_alternative<v::Value>(retained_checkpoint) &&
          std::holds_alternative<m::State>(decoded_retained) &&
          std::get<m::State>(decoded_retained) == retained,
          "Save and reload keep a plate and its offcut at the supported work point.");
    check(m::pickup_material(retained, recipe, path, "Q", work) == m::Error::none &&
          retained.cargo.at("Q").products == 1 && retained.cargo.at("Q").offcuts == 1 &&
          retained.dropped_material.at(exit).products == 1 &&
          m::validate(retained, recipe, path) == m::Error::none,
          "A second actor can collect the supported plate without taking the neighboring output.");
    m::State retained_powered = held_on_support;
    retained_powered.dropped_material.at(work) = m::Cargo{1, 0, {}};
    retained_powered.cargo.at("P").products = 1;
    retained_powered.cargo.at("P").offcuts = 1;
    retained_powered.initial_units = 3;
    m::PressStep support_step{work, exit};
    support_step.output_location = m::PressOutputLocation::supported_work;
    check(m::step_presses(retained_powered, recipe, path, {support_step}) == m::Error::none &&
          m::step_presses(retained_powered, recipe, path, {support_step}) == m::Error::none &&
          m::step_presses(retained_powered, recipe, path, {support_step}) == m::Error::none &&
          retained_powered.dropped_material.at(work).products == 1 &&
          retained_powered.dropped_material.at(work).offcuts == 1 &&
          retained_powered.dropped_material.at(exit).products == 1 &&
          m::validate(retained_powered, recipe, path) == m::Error::none,
          "Powered pressing also keeps its finished plate on the support despite a full exit.");
    m::State compact;
    compact.initial_units = 1;
    compact.cargo.emplace("P", m::Cargo{});
    compact.cargo.at("P").offcuts = 4;
    check(m::validate(compact, recipe, path) == m::Error::none,
          "Four recovered one-unit offcuts retain exactly one stock chunk of mass.");
    const auto four_offcuts = compact;
    check(m::compact_offcuts(compact, recipe, path, "Q", work) == m::Error::invalid_actor &&
          compact == four_offcuts,
          "An unbound actor cannot compact someone else's recovered copper.");
    check(m::compact_offcuts(compact, recipe, path, "P", work) == m::Error::none &&
          compact.cargo.at("P").offcuts == 0 && compact.dropped_material.at(work).raw_units == 1 &&
          m::validate(compact, recipe, path) == m::Error::none,
          "Explicit compaction places one full-mass blank at the work face.");
    const auto compacted = compact;
    check(m::compact_offcuts(compact, recipe, path, "P", work) == m::Error::unavailable_input &&
          compact == compacted,
          "Retrying compaction cannot mint another blank from spent offcuts.");
    check(m::pickup_material(compact, recipe, path, "P", work) == m::Error::none &&
          compact.cargo.at("P").raw_units == 1 && m::validate(compact, recipe, path) == m::Error::none,
          "The reprocessed stock remains recoverable through ordinary pickup.");
    m::State sheet;
    sheet.initial_units = 3;
    sheet.next_work_id = 2;
    sheet.cargo.emplace("P", m::Cargo{});
    sheet.cargo.emplace("Q", m::Cargo{});
    sheet.cargo.at("P").sheets.push_back({1, 2});
    check(m::validate(sheet, recipe, path) == m::Error::none,
          "One carried oriented sheet conserves the mass of three stock chunks.");
    const auto carried_sheet = sheet;
    check(m::place_sheet(sheet, recipe, path, "P", 2, work) == m::Error::unavailable_input &&
          sheet == carried_sheet,
          "An unknown sheet serial cannot debit another item from the actor.");
    check(m::place_sheet(sheet, recipe, path, "P", 1, work) == m::Error::none &&
          sheet.cargo.at("P").sheets.empty() &&
          sheet.dropped_material.at(work).sheets == std::vector<m::Sheet>{{1, 2}} &&
          m::validate(sheet, recipe, path) == m::Error::none,
          "Placement keeps the exact sheet serial, orientation and twelve mass units.");
    const auto placed_sheet = sheet;
    check(m::place_sheet(sheet, recipe, path, "P", 1, work) == m::Error::unavailable_input &&
          sheet == placed_sheet,
          "Retrying placement cannot duplicate a sheet already at the work area.");
    auto sheared = placed_sheet;
    check(m::shear_sheet(sheared, recipe, path, 2, work) == m::Error::unavailable_input &&
          sheared == placed_sheet,
          "A different sheet serial cannot authorize a cut of the staged item.");
    auto blocked_sheet = placed_sheet;
    blocked_sheet.initial_units = 4;
    blocked_sheet.dropped_material.emplace(m::DropPoint{work[0] + 4, work[1], work[2]},
        m::Cargo{1, 0, {}});
    check(m::validate(blocked_sheet, recipe, path) == m::Error::none &&
          m::shear_sheet(blocked_sheet, recipe, path, 1, work) == m::Error::unavailable_output &&
          blocked_sheet.dropped_material.at(work).sheets == std::vector<m::Sheet>{{1, 2}},
          "One occupied output cell holds the full twelve-mass sheet without making a plate.");
    check(m::shear_sheet(sheared, recipe, path, 1, work) == m::Error::none &&
          sheared.dropped_material.at(work) == m::Cargo{0, 1, {}} &&
          sheared.dropped_material.at({work[0] + 4, work[1], work[2]}) == m::Cargo{0, 1, {}} &&
          sheared.dropped_material.at({work[0], work[1], work[2] + 4}) == m::Cargo{0, 1, {}} &&
          sheared.dropped_material.at({work[0] + 4, work[1], work[2] + 4}) == m::Cargo{0, 1, {}} &&
          m::validate(sheared, recipe, path) == m::Error::none,
          "One sheet becomes four separately located three-mass plates with no offcut.");
    check(m::shear_sheet(sheared, recipe, path, 1, work) == m::Error::unavailable_input &&
          m::validate(sheared, recipe, path) == m::Error::none,
          "A repeated cut cannot mint another four plates from the consumed sheet.");
    const auto cut_checkpoint = m::encode_material_state(sheared, recipe, path, {"P", "Q"});
    m::MaterialDecoding decoded_cut = m::CodecRefusal{};
    if (const auto* value = std::get_if<v::Value>(&cut_checkpoint))
        decoded_cut = m::decode_material_state(*value, recipe, path, {"P", "Q"});
    check(std::holds_alternative<m::State>(decoded_cut) &&
          std::get<m::State>(decoded_cut) == sheared,
          "Fresh material decoding retains all four physical plate locations.");
    check(m::pickup_material(sheared, recipe, path, "Q", work) == m::Error::none &&
          sheared.cargo.at("Q").products == 1 &&
          sheared.dropped_material.size() == 3 &&
          m::validate(sheared, recipe, path) == m::Error::none,
          "A second actor can collect one plate without changing the other three.");
    check(m::pickup_material(sheet, recipe, path, "Q", work) == m::Error::none &&
          sheet.cargo.at("Q").sheets == std::vector<m::Sheet>{{1, 2}} &&
          !sheet.dropped_material.contains(work) && m::validate(sheet, recipe, path) == m::Error::none,
          "A second actor can recover the same oriented sheet without minting mass.");
    const auto sheet_checkpoint = m::encode_material_state(sheet, recipe, path, {"P", "Q"});
    m::MaterialDecoding decoded_sheet = m::CodecRefusal{};
    if (const auto* value = std::get_if<v::Value>(&sheet_checkpoint))
        decoded_sheet = m::decode_material_state(*value, recipe, path, {"P", "Q"});
    check(std::holds_alternative<v::Value>(sheet_checkpoint) &&
          std::holds_alternative<m::State>(decoded_sheet) &&
          std::get<m::State>(decoded_sheet) == sheet,
          "Fresh material decoding retains the recovered sheet serial and rotation.");
    state.cargo.at("P").offcuts = 0;
    check(m::validate(state, recipe, path) == m::Error::invalid_state,
          "Removing even one offcut unit breaks native mass conservation.");
    check(before != formed && checks == 37, "The fixture exercised actual stock and formed states.");
    std::cout << "{\"checks\":" << checks << ",\"evidence\":\"copper_material_mass\"}\n";
    return failures == 0 && checks == 38 ? 0 : 1;
}
