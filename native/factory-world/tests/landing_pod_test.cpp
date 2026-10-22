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
          "The trusted landing profile cannot be silently stripped of its hub.");
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
    const auto encoded = w::encode_checkpoint(profile, after);
    check(std::holds_alternative<V>(encoded), "A partly reclaimed deck saves.");
    const auto decoded = w::decode_checkpoint(profile, "pod-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded) &&
          std::get<w::Snapshot>(decoded).state == after.state &&
          std::get<w::Snapshot>(decoded).revision == after.revision &&
          std::get<w::Snapshot>(decoded).history.order == after.history.order,
          "Checkpoint continuation retains pod identity and the single recovered tile.");
}
}  // namespace

int main() {
    try {
        settled_pod_and_checkpoint();
        seed_cannot_duplicate_or_forge_pod();
        deck_recovery_is_a_normal_world_transaction();
        std::cout << "landing_pod_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "landing_pod_test: " << error.what() << '\n';
        return 1;
    }
}
