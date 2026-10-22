#include "factory/checkpoint.hpp"
#include "factory/world.hpp"

#include <iostream>
#include <stdexcept>

namespace {
namespace w = factory::world;
namespace m = factory::materials;
namespace a = factory::authority;
using V = factory::values::Value;
using O = V::Object;
using I = V::Integer;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

std::pair<w::Profile, w::State> seed() {
    w::Profile profile;
    profile.material = {1, 32, 2};
    profile.material.timber_sites = {{"tree-a", {{12, 0, 12}, 8}},
                                     {"tree-b", {{12, 0, 24}, 8}}};
    profile.material.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    profile.material.hand_carry_capacity = 24;
    profile.initial_units = 16;
    profile.actors = {"P", "Q"};
    profile.meters_per_grid_unit = 0.4125;
    profile.anchor_offset = {0, 1, 0};
    profile.build_reach = 4;
    w::State state;
    state.material.initial_units = 16;
    state.material.stock.source = 16;
    state.material.timber_remaining = {{"tree-a", 8}, {"tree-b", 8}};
    state.material.cargo = {{"P", {}}, {"Q", {}}};
    state.kits = {{"P", {}}, {"Q", {}}};
    return {profile, state};
}

O command(const char* actor, const char* client, const char* request, const char* target) {
    return {{"context", V("harvest-world")}, {"client", V(client)}, {"request", V(request)},
        {"actor", V(actor)}, {"action", V("harvest_source")}, {"target", V(target)}};
}

void harvest_and_restore() {
    auto [profile, state] = seed();
    auto world = w::World::create("harvest-world", profile, state);
    check(world != nullptr, "A native World accepts trusted tree and ore source facts.");
    const w::ObserveActor nearby = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, actor == "P" ? a::Point{1.65, 1, 6.6} : a::Point{-1.2375, 1, 0},
            3, true, 4};
    };
    const auto tree = command("P", "P-client", "tree-cut", "tree-a");
    const auto first = world->command({"P", "P-client"}, tree, nearby);
    check(first.completed() && std::get<bool>(first.result->at("accepted").storage()) &&
          world->snapshot().state.material.timber_remaining.at("tree-a") == 7 &&
          world->snapshot().state.material.cargo.at("P").timber == 1,
          "A physical P cut moves exactly one timber from the targeted tree.");
    const auto before_retry = world->snapshot();
    const auto retry = world->command({"P", "P-client"}, tree,
        [](const std::string&) -> std::optional<a::ActorCut> { return std::nullopt; });
    check(retry.completed() && std::get<bool>(retry.result->at("duplicate").storage()) &&
          world->snapshot().state == before_retry.state && world->snapshot().revision == before_retry.revision,
          "A cached retry is decided before observation and cannot duplicate wood.");
    const auto ore = world->command({"Q", "Q-client"}, command("Q", "Q-client", "ore-cut", "ore"), nearby);
    check(ore.completed() && std::get<bool>(ore.result->at("accepted").storage()) &&
          world->snapshot().state.material.stock.source == 15 &&
          world->snapshot().state.material.cargo.at("Q").raw_units == 1,
          "Q's hand cut debits the collector's one finite ore reserve.");
    const auto far = world->command({"P", "P-client"}, command("P", "P-client", "far-cut", "tree-b"), nearby);
    check(far.completed() && !std::get<bool>(far.result->at("accepted").storage()) &&
          std::get<std::string>(far.result->at("reason").storage()) == "out_of_reach" &&
          world->snapshot().state.material.timber_remaining.at("tree-b") == 8,
          "A distant tree cannot be harvested from a camera or another actor's body.");
    const auto unknown = world->command({"P", "P-client"}, command("P", "P-client", "fake-cut", "fake"), nearby);
    check(unknown.completed() && !std::get<bool>(unknown.result->at("accepted").storage()) &&
          world->snapshot().state.material.cargo.at("P").timber == 1,
          "A forged source identity does not mint timber.");
    const auto snapshot = world->snapshot();
    const auto saved = w::encode_checkpoint(profile, snapshot);
    check(std::holds_alternative<V>(saved), "The World checkpoint includes tree and ore custody.");
    const auto decoded = w::decode_checkpoint(profile, "harvest-world", std::get<V>(saved));
    check(std::holds_alternative<w::Snapshot>(decoded) &&
          std::get<w::Snapshot>(decoded).state == snapshot.state,
          "A late join decodes the same source balances and actor inventory.");
    auto restored = w::World::restore("harvest-world", profile, std::get<w::Snapshot>(decoded));
    check(restored && restored->snapshot().state == snapshot.state,
          "A fresh authority restores the exact material ledger.");
    auto forged = snapshot;
    ++forged.state.material.cargo.at("P").timber;
    check(!w::World::restore("harvest-world", profile, forged),
          "A restored actor cannot receive unmined timber.");
    forged = snapshot;
    --forged.state.material.cargo.at("P").timber;
    ++forged.state.material.cargo.at("Q").timber;
    check(!w::World::restore("harvest-world", profile, forged),
          "A checkpoint cannot move timber between actors without an accepted transfer.");
    auto moved_tree = profile;
    moved_tree.material.timber_sites.at("tree-a").center = {16, 0, 12};
    const auto moved = w::decode_checkpoint(moved_tree, "harvest-world", std::get<V>(saved));
    check(std::holds_alternative<w::CheckpointRefusal>(moved),
          "A site anchor cannot move under an existing save or history.");
}
}  // namespace

int main() {
    try {
        harvest_and_restore();
        std::cout << "harvest_world_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "harvest_world_test: " << error.what() << '\n';
        return 1;
    }
}
