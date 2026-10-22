#include "factory/checkpoint.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

namespace {
namespace w = factory::world;
namespace a = factory::authority;
namespace s = factory::stationary;
namespace m = factory::materials;
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
    profile.initial_units = 16;
    profile.actors = {"P", "Q"};
    profile.foundation_parts = 24;
    profile.landing_pod_center = factory::mechanics::Point{4, 0, 16};
    profile.build_reach = 10;
    w::State state;
    state.material.initial_units = 16;
    state.material.stock.source = 16;
    state.material.cargo = {{"P", m::Cargo{}}, {"Q", m::Cargo{}}};
    state.kits = {{"P", s::Kit{}}, {"Q", s::Kit{}}};
    state.foundation_kits = {{"P", 15}, {"Q", 0}};
    state.landing_pod = w::LandingPod{"landing-pod", *profile.landing_pod_center, 1};
    state.issued_entities.emplace("landing-pod", 1);
    state.fabrication_hub = w::FabricationHub{"pod-fabrication-hub", w::landing_hub_center(*profile.landing_pod_center), 1};
    state.issued_entities.emplace("pod-fabrication-hub", 1);
    const auto deck = w::landing_deck_centers(*profile.landing_pod_center);
    for (std::size_t index = 0; index < deck.size(); ++index) {
        const auto id = "pod-floor-" + std::to_string(index);
        state.foundations.emplace(id, w::Foundation{deck[index], 1});
        state.issued_entities.emplace(id, 1);
    }
    return {profile, state};
}

void settled_pod_and_checkpoint() {
    const auto [profile, state] = seed();
    auto world = w::World::create("pod-world", profile, state);
    check(world != nullptr, "The one settled landing pod and nine ordinary deck tiles initialize.");
    const auto snapshot = world->snapshot();
    check(snapshot.revision == 0 && snapshot.state.landing_pod == state.landing_pod &&
          snapshot.state.foundations.size() == 9 && snapshot.state.foundation_kits.at("P") == 15,
          "Landing spends exactly nine of twenty-four foundation parts without a second stock owner.");
    const auto encoded = w::encode_checkpoint(profile, snapshot);
    check(std::holds_alternative<V>(encoded), "The landing pod checkpoint encodes.");
    const auto decoded = w::decode_checkpoint(profile, "pod-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded) &&
          std::get<w::Snapshot>(decoded).state == snapshot.state &&
          std::get<w::Snapshot>(decoded).revision == snapshot.revision &&
          std::get<w::Snapshot>(decoded).history.order == snapshot.history.order,
          "A late join or restore observes the same pod, deck and finite carried stock.");
    auto changed_site = profile;
    changed_site.landing_pod_center = factory::mechanics::Point{8, 0, 16};
    const auto mismatch = w::decode_checkpoint(changed_site, "pod-world", std::get<V>(encoded));
    check(std::holds_alternative<w::CheckpointRefusal>(mismatch),
          "A saved pod cannot be moved by changing trusted site profile facts.");
}

void seed_cannot_duplicate_or_forge_pod() {
    auto [profile, state] = seed();
    state.foundation_kits.at("P") += 9;
    check(!w::World::create("pod-world", profile, state),
          "The unfolded deck cannot also remain in the carried foundation kit.");
    state.foundation_kits.at("P") -= 9;
    state.foundations.erase("pod-floor-8");
    check(!w::World::create("pod-world", profile, state),
          "A fresh landing cannot omit a deck tile and keep a complete pod identity.");
    state = seed().second;
    state.landing_pod->id = "second-pod";
    check(!w::World::create("pod-world", profile, state),
          "A copied site pod cannot introduce an unissued identity.");
    state = seed().second;
    state.landing_pod.reset();
    check(!w::World::create("pod-world", profile, state),
          "The trusted landing profile cannot be silently stripped of its pod.");
    state = seed().second;
    state.fabrication_hub->center[0] += 4;
    check(!w::World::create("pod-world", profile, state),
          "The bench cannot move independently from its issued deck identity.");
    state = seed().second;
    state.fabrication_hub.reset();
    check(!w::World::create("pod-world", profile, state),
          "A pod save cannot omit the single fabrication hub.");
}

void deck_recovery_is_a_normal_world_transaction() {
    auto [profile, state] = seed();
    auto world = w::World::create("pod-world", profile, state);
    check(world != nullptr, "The recovery fixture initializes.");
    const O intent{{"context", V("pod-world")}, {"client", V("P-first")},
        {"request", V("take-floor")}, {"actor", V("P")}, {"action", V("remove_foundation")},
        {"target", V("pod-floor-0")}, {"generation", V(I{1})}};
    const auto cut = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {4, 0, 16}, 7, true, 10};
    };
    const auto first = world->command({"P", "P-first"}, intent, cut);
    check(first.completed() && std::get<bool>(first.result->at("accepted").storage()),
          "The player can recover a pod deck tile through the ordinary foundation command.");
    const auto after = world->snapshot();
    check(after.state.landing_pod == state.landing_pod && after.state.foundations.size() == 8 &&
          after.state.foundation_kits.at("P") == 16,
          "Dismantling returns one real tile and does not consume or duplicate the hub.");
    const auto retry = world->command({"P", "P-first"}, intent, cut);
    const auto retried = world->snapshot();
    check(retry.completed() && std::get<bool>(retry.result->at("duplicate").storage()) &&
          retried.state == after.state && retried.revision == after.revision &&
          retried.history.order == after.history.order,
          "An exact retry cannot recover the same deck tile a second time.");
    auto bench_floor = intent;
    bench_floor.at("request") = V("take-bench-floor");
    bench_floor.at("target") = V("pod-floor-7");
    const auto unsupported = world->command({"P", "P-first"}, bench_floor, cut);
    check(unsupported.completed() && !std::get<bool>(unsupported.result->at("accepted").storage()) &&
          std::get<std::string>(unsupported.result->at("reason").storage()) == "foundation_in_use" &&
          world->snapshot().state == after.state,
          "The bench's own deck support cannot be reclaimed while the bench occupies it.");
    const auto encoded = w::encode_checkpoint(profile, after);
    check(std::holds_alternative<V>(encoded), "A partly reclaimed deck saves.");
    const auto decoded = w::decode_checkpoint(profile, "pod-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded) &&
          std::get<w::Snapshot>(decoded).state == after.state &&
          std::get<w::Snapshot>(decoded).revision == after.revision &&
          std::get<w::Snapshot>(decoded).history.order == after.history.order,
          "Checkpoint continuation retains pod identity and the single recovered tile.");
}

void reachable_craft_uses_one_hub_and_owned_ingredients() {
    auto [profile, state] = seed();
    profile.build_reach = 4;
    profile.material.timber_sites = {{"tree-near-hub", {{8, 0, 20}, 8}}};
    profile.material.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    profile.material.component_capacity = 1;
    state.material.timber_remaining = {{"tree-near-hub", 8}};
    auto world = w::World::create("pod-craft", profile, state);
    check(world != nullptr, "The one seeded bench shares a finite resource world.");
    const auto near = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {8, 0, 16}, 4, true, 4};
    };
    const auto far = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {20, 0, 16}, 4, true, 4};
    };
    for (int cut = 0; cut < 3; ++cut) {
        const O harvest{{"context", V("pod-craft")}, {"client", V("P-client")},
            {"request", V("tree-" + std::to_string(cut))}, {"actor", V("P")},
            {"action", V("harvest_source")}, {"target", V("tree-near-hub")}};
        const auto result = world->command({"P", "P-client"}, harvest, near);
        check(result.completed() && std::get<bool>(result.result->at("accepted").storage()),
              "Each reachable cut supplies one carried timber from a named tree.");
    }
    const O craft{{"context", V("pod-craft")}, {"client", V("P-client")},
        {"request", V("first-frame")}, {"actor", V("P")}, {"action", V("craft_component")},
        {"target", V("pod-fabrication-hub")}, {"generation", V(I{1})},
        {"component", V("wooden_frame")}};
    const auto before = world->snapshot();
    const auto unreachable = world->command({"P", "P-client"}, craft, far);
    check(unreachable.completed() && !std::get<bool>(unreachable.result->at("accepted").storage()) &&
          std::get<std::string>(unreachable.result->at("reason").storage()) == "out_of_reach" &&
          world->snapshot().state == before.state,
          "A distant actor cannot craft at a camera or remote bench.");
    auto fresh_craft = craft;
    fresh_craft.at("request") = V("first-frame-near");
    const auto first = world->command({"P", "P-client"}, fresh_craft, near);
    check(first.completed() && std::get<bool>(first.result->at("accepted").storage()) &&
          world->snapshot().state.material.cargo.at("P").components.at(m::Component::wooden_frame) == 1 &&
          world->snapshot().state.material.cargo.at("P").timber == 0 &&
          world->snapshot().state.material.timber_remaining.at("tree-near-hub") == 5,
          "The bench converts exactly three of P's timber into one typed frame.");
    const auto committed = world->snapshot();
    const auto retry = world->command({"P", "P-client"}, fresh_craft,
        [](const std::string&) -> std::optional<a::ActorCut> { return std::nullopt; });
    check(retry.completed() && std::get<bool>(retry.result->at("duplicate").storage()) &&
          world->snapshot().state == committed.state && world->snapshot().revision == committed.revision,
          "An exact craft retry returns its first outcome before actor observation.");
    auto other = craft;
    other.at("client") = V("Q-client");
    other.at("actor") = V("Q");
    other.at("request") = V("Q-frame");
    const auto denied = world->command({"Q", "Q-client"}, other, near);
    check(denied.completed() && !std::get<bool>(denied.result->at("accepted").storage()) &&
          std::get<std::string>(denied.result->at("reason").storage()) == "unavailable_input" &&
          world->snapshot().state == committed.state,
          "Q cannot spend P's timber even while standing at the same hub.");
    auto invented = craft;
    invented.at("request") = V("invented-part");
    invented.at("component") = V("magic_motor");
    const auto unknown = world->command({"P", "P-client"}, invented, near);
    check(unknown.completed() && !std::get<bool>(unknown.result->at("accepted").storage()) &&
          std::get<std::string>(unknown.result->at("reason").storage()) == "unavailable_recipe" &&
          world->snapshot().state == committed.state,
          "An unlisted component recipe cannot spend or mint actor stock.");
    const O more_wood{{"context", V("pod-craft")}, {"client", V("P-client")},
        {"request", V("fourth-tree")}, {"actor", V("P")},
        {"action", V("harvest_source")}, {"target", V("tree-near-hub")}};
    const auto fourth_cut = world->command({"P", "P-client"}, more_wood, near);
    check(fourth_cut.completed() && std::get<bool>(fourth_cut.result->at("accepted").storage()),
          "One more physical cut supplies a second potential recipe input.");
    auto full_craft = craft;
    full_craft.at("request") = V("full-output");
    full_craft.at("component") = V("wooden_shaft");
    const auto full_before = world->snapshot();
    const auto full = world->command({"P", "P-client"}, full_craft, near);
    check(full.completed() && !std::get<bool>(full.result->at("accepted").storage()) &&
          std::get<std::string>(full.result->at("reason").storage()) == "inventory_full" &&
          world->snapshot().state == full_before.state &&
          world->snapshot().state.material.cargo.at("P").timber == 1,
          "A full component output leaves its newly mined ingredient in actor custody.");
    const auto snapshot = world->snapshot();
    const auto saved = w::encode_checkpoint(profile, snapshot);
    check(std::holds_alternative<V>(saved), "Craft history and the one hub encode together.");
    const auto decoded = w::decode_checkpoint(profile, "pod-craft", std::get<V>(saved));
    check(std::holds_alternative<w::Snapshot>(decoded) && std::get<w::Snapshot>(decoded).state == snapshot.state &&
          w::World::restore("pod-craft", profile, std::get<w::Snapshot>(decoded)) != nullptr,
          "A fresh World restores the exact frame, tree balance and bench identity.");
    auto forged = snapshot;
    ++forged.state.material.cargo.at("P").components.at(m::Component::wooden_frame);
    check(!w::World::restore("pod-craft", profile, forged),
          "A second component cannot appear without a matching transaction and timber debit.");
    auto wider_profile = profile;
    wider_profile.material.component_capacity = 2;
    forged = snapshot;
    --forged.state.material.cargo.at("P").timber;
    forged.state.material.cargo.at("P").components.emplace(m::Component::wooden_shaft, 1);
    check(m::validate(forged.state.material, wider_profile.material,
              w::material_path(forged.state.topology)) == m::Error::none &&
          !w::World::restore("pod-craft", wider_profile, forged),
          "Even conserved ingredient conversion cannot forge an unrecorded craft action.");
}
}  // namespace

int main() {
    try {
        settled_pod_and_checkpoint();
        seed_cannot_duplicate_or_forge_pod();
        deck_recovery_is_a_normal_world_transaction();
        reachable_craft_uses_one_hub_and_owned_ingredients();
        std::cout << "landing_pod_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "landing_pod_test: " << error.what() << '\n';
        return 1;
    }
}
