#include "factory/material_state_codec.hpp"

#include <array>
#include <iostream>
#include <stdexcept>

namespace {
namespace m = factory::materials;
using V = factory::values::Value;
using O = V::Object;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

m::Config config() {
    m::Config facts{1, 32, 2};
    facts.timber_sites = {{"tree-a", {{12, 0, 12}, 8}},
                          {"tree-b", {{12, 0, 24}, 8}},
                          {"tree-c", {{0, 0, 28}, 8}}};
    facts.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    facts.hand_carry_capacity = 32;
    return facts;
}

m::State seed() {
    m::State state;
    state.initial_units = 16;
    state.stock.source = 16;
    state.timber_remaining = {{"tree-a", 8}, {"tree-b", 8}, {"tree-c", 8}};
    state.cargo = {{"P", {}}, {"Q", {}}};
    return state;
}

void exact_bill_and_refusals() {
    const auto facts = config();
    const m::Path path{};
    auto state = seed();
    constexpr std::array wood{m::Component::wooden_frame, m::Component::wooden_shaft,
        m::Component::wooden_cog, m::Component::receiver_tray, m::Component::tool_mount,
        m::Component::sliding_guide, m::Component::wooden_workbench};
    constexpr std::array metal{m::Component::cutting_edge, m::Component::anvil,
        m::Component::ram_face, m::Component::softmetal_shaft, m::Component::softmetal_cog};
    m::Quantity timber_bill = 0, ore_bill = 0;
    for (const auto component : wood) {
        const auto cost = m::component_cost(component);
        check(cost && cost->timber > 0 && cost->ore == 0,
              "A wooden recipe consumes only finite timber, never another component.");
        timber_bill += cost->timber;
    }
    for (const auto component : metal) {
        const auto cost = m::component_cost(component);
        check(cost && cost->ore > 0 && cost->timber == 0,
              "A softmetal recipe consumes only finite ore, never another component.");
        ore_bill += cost->ore;
    }
    check(timber_bill == 14 && ore_bill == 9,
          "The whole prototype catalogue costs fourteen timber and nine softmetal blanks.");
    for (int cut = 0; cut < 8; ++cut)
        check(m::harvest_source(state, facts, path, "P", "tree-a") == m::Error::none,
              "P harvests the first finite tree.");
    for (int cut = 0; cut < 6; ++cut)
        check(m::harvest_source(state, facts, path, "P", "tree-b") == m::Error::none,
              "P harvests six more units from the next finite tree.");
    for (int cut = 0; cut < 9; ++cut)
        check(m::harvest_source(state, facts, path, "Q", "ore") == m::Error::none,
              "Q hand mines nine units from the collector's source.");
    const auto without_input = state;
    check(m::craft_component(state, facts, path, "Q", m::Component::wooden_frame) == m::Error::unavailable_input &&
          state == without_input, "Q cannot spend P's carried timber.");
    check(m::craft_component(state, facts, path, "P", m::Component::anvil) == m::Error::unavailable_input &&
          state == without_input, "P cannot spend Q's carried ore.");
    check(m::craft_component(state, facts, path, "absent", m::Component::wooden_shaft) == m::Error::invalid_actor &&
          state == without_input, "An absent actor cannot receive a crafted part.");
    check(m::craft_component(state, facts, path, "P", static_cast<m::Component>(999)) == m::Error::unavailable_recipe &&
          state == without_input, "An unknown recipe cannot mint a component.");
    for (const auto component : wood)
        check(m::craft_component(state, facts, path, "P", component) == m::Error::none &&
              state.cargo.at("P").components.at(component) == 1,
              "Each wood component costs its own carried timber.");
    for (const auto component : metal)
        check(m::craft_component(state, facts, path, "Q", component) == m::Error::none &&
              state.cargo.at("Q").components.at(component) == 1,
              "Each metal component costs its own carried ore.");
    check(state.cargo.at("P").timber == 0 && state.cargo.at("Q").raw_units == 0 &&
          state.timber_remaining.at("tree-a") == 0 && state.timber_remaining.at("tree-b") == 2 &&
          state.stock.source == 7 && m::validate(state, facts, path) == m::Error::none,
          "The shaped stock and uncut reserves account for all twenty-four timber and sixteen ore units.");

    const auto encoded = m::encode_material_state(state, facts, path, {"P", "Q"});
    check(std::holds_alternative<V>(encoded), "Crafted actor custody encodes in the one material checkpoint.");
    const auto decoded = m::decode_material_state(std::get<V>(encoded), facts, path, {"P", "Q"});
    check(std::holds_alternative<m::State>(decoded) && std::get<m::State>(decoded) == state,
          "A strict checkpoint restores the exact typed component catalogue and balances.");
    auto forged = state;
    ++forged.cargo.at("P").components.at(m::Component::wooden_frame);
    check(m::validate(forged, facts, path) == m::Error::invalid_state,
          "A forged frame cannot appear without consuming three more timber.");
    auto root = std::get<O>(std::get<V>(encoded).storage());
    auto cargo = std::get<O>(root.at("cargo").storage());
    auto player = std::get<O>(cargo.at("P").storage());
    auto components = std::get<O>(player.at("components").storage());
    components.emplace("magic_motor", V(m::Quantity{1}));
    player.at("components") = V(std::move(components));
    cargo.at("P") = V(std::move(player));
    root.at("cargo") = V(std::move(cargo));
    check(std::holds_alternative<m::CodecRefusal>(
        m::decode_material_state(V(std::move(root)), facts, path, {"P", "Q"})),
        "An unknown serialized component identity is refused.");
}

void component_capacity() {
    auto facts = config();
    facts.component_capacity = 2;
    const m::Path path{};
    auto state = seed();
    for (int cut = 0; cut < 3; ++cut)
        check(m::harvest_source(state, facts, path, "P", "tree-a") == m::Error::none,
              "The small-capacity actor obtains real recipe inputs.");
    check(m::craft_component(state, facts, path, "P", m::Component::wooden_shaft) == m::Error::none &&
          m::craft_component(state, facts, path, "P", m::Component::wooden_shaft) == m::Error::none,
          "Two one-timber shafts fill two component slots.");
    const auto full = state;
    check(m::craft_component(state, facts, path, "P", m::Component::wooden_shaft) == m::Error::inventory_full &&
          state == full && state.cargo.at("P").timber == 1,
          "A full component inventory leaves both ingredient and output untouched.");
}
}  // namespace

int main() {
    try {
        exact_bill_and_refusals();
        component_capacity();
        std::cout << "component_craft_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "component_craft_test: " << error.what() << '\n';
        return 1;
    }
}
