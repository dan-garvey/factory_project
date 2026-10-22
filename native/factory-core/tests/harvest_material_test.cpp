#include "factory/material_state_codec.hpp"

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
    m::Config result{1, 32, 2};
    result.timber_sites = {{"tree-a", {{12, 0, 12}, 8}},
                           {"tree-b", {{12, 0, 24}, 8}}};
    result.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    result.hand_carry_capacity = 3;
    return result;
}

m::State seed() {
    m::State state;
    state.initial_units = 16;
    state.stock.source = 16;
    state.cargo = {{"P", {}}, {"Q", {}}};
    state.timber_remaining = {{"tree-a", 8}, {"tree-b", 8}};
    return state;
}

void conserved_hand_work() {
    const auto facts = config();
    const m::Path path{};
    auto state = seed();
    check(m::validate(state, facts, path) == m::Error::none,
          "The two tree reserves and collector ore reserve have one valid initial ledger.");
    check(m::harvest_source(state, facts, path, "P", "tree-a") == m::Error::none &&
          state.timber_remaining.at("tree-a") == 7 && state.cargo.at("P").timber == 1,
          "One timber cut moves one real unit to the bound actor.");
    check(m::harvest_source(state, facts, path, "Q", "ore") == m::Error::none &&
          state.stock.source == 15 && state.cargo.at("Q").raw_units == 1,
          "Manual ore and the collector share the exact same finite source stock.");
    check(m::harvest_source(state, facts, path, "P", "tree-b") == m::Error::none &&
          m::harvest_source(state, facts, path, "P", "ore") == m::Error::none,
          "The actor can choose a different tree or a mineable deposit.");
    const auto full = state;
    check(m::harvest_source(state, facts, path, "P", "tree-a") == m::Error::inventory_full &&
          state == full, "A full carried inventory refuses without debiting a tree.");
    check(m::harvest_source(state, facts, path, "P", "unknown") == m::Error::unavailable_source &&
          state == full, "An unknown target cannot create a free resource.");
    check(m::harvest_source(state, facts, path, "other", "tree-a") == m::Error::invalid_actor &&
          state == full, "An unbound actor cannot acquire another player's stock.");

    const auto saved = m::encode_material_state(state, facts, path, {"P", "Q"});
    check(std::holds_alternative<V>(saved), "The single resource ledger encodes.");
    const auto loaded = m::decode_material_state(std::get<V>(saved), facts, path, {"P", "Q"});
    check(std::holds_alternative<m::State>(loaded) && std::get<m::State>(loaded) == state,
          "Save and restore preserve both tree balances and the shared ore debit.");
    auto forged = state;
    ++forged.cargo.at("Q").timber;
    check(m::validate(forged, facts, path) == m::Error::invalid_state,
          "Timber cannot appear in an actor inventory without leaving a named tree.");
    forged = state;
    ++forged.stock.source;
    check(m::validate(forged, facts, path) == m::Error::invalid_state,
          "Hand extraction cannot refill the collector's ore source.");
    auto root = std::get<O>(std::get<V>(saved).storage());
    auto remaining = std::get<O>(root.at("timber_remaining").storage());
    remaining.at("tree-a") = V(m::Quantity{8});
    root.at("timber_remaining") = V(std::move(remaining));
    const auto rejected = m::decode_material_state(V(std::move(root)), facts, path, {"P", "Q"});
    check(std::holds_alternative<m::CodecRefusal>(rejected),
          "An altered checkpoint tree balance is refused before restore.");

    auto generous = facts;
    generous.hand_carry_capacity = 64;
    auto depleted = seed();
    for (int cut = 0; cut < 8; ++cut)
        check(m::harvest_source(depleted, generous, path, "P", "tree-a") == m::Error::none,
              "Every named tree cut transfers one unit until its last piece.");
    const auto empty_tree = depleted;
    check(m::harvest_source(depleted, generous, path, "P", "tree-a") == m::Error::unavailable_source &&
          depleted == empty_tree,
          "A depleted tree cannot regrow through repeated commands.");
    check(m::harvest_source(depleted, generous, path, "Q", "ore") == m::Error::none,
          "One manual ore cut is admitted before the collector runs.");
    m::Path collector;
    collector.collector_present = true;
    collector.powered = true;
    check(m::step(depleted, generous, collector) == m::Error::none &&
          depleted.stock.source == 14 && depleted.stock.collector == 1 &&
          depleted.cargo.at("Q").raw_units == 1,
          "The operating collector extracts from the reserve already reduced by hand mining.");
    for (int cut = 0; cut < 14; ++cut)
        check(m::harvest_source(depleted, generous, collector, "Q", "ore") == m::Error::none,
              "The remaining ore reserve can be hand mined without minting stock.");
    const auto empty_ore = depleted;
    check(m::harvest_source(depleted, generous, collector, "Q", "ore") == m::Error::unavailable_source &&
          depleted == empty_ore && m::validate(depleted, generous, collector) == m::Error::none,
          "Collector and manual mining together exhaust one ore source exactly.");
}
}  // namespace

int main() {
    try {
        conserved_hand_work();
        std::cout << "harvest_material_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "harvest_material_test: " << error.what() << '\n';
        return 1;
    }
}
