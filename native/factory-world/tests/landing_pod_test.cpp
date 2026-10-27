#include "factory/checkpoint.hpp"
#include "native/factory-world/tests/harvest_fixture.hpp"

#include <array>
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
    profile.starting_foundation_kits = {{"P", 15}, {"Q", 0}};
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

void field_wood_shaping_keeps_actor_custody() {
    auto [profile, state] = seed();
    profile.build_reach = 2;
    profile.material.timber_sites = {{"field-tree", {{20, 0, 16}, 8}}};
    profile.material.component_capacity = 1;
    state.material.timber_remaining = {{"field-tree", 8}};
    auto world = w::World::create("field-shaping", profile, state);
    check(world != nullptr, "Finite timber and the pod hub initialize for field shaping.");
    const auto field = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {20, 0, 16}, 1, true, 2};
    };
    for (int index = 0; index < 4; ++index) {
        const O cut{{"context", V("field-shaping")}, {"client", V("P-client")},
            {"request", V("cut-" + std::to_string(index))}, {"actor", V("P")},
            {"action", V("harvest_source")}, {"target", V("field-tree")}};
        const auto result = w::tests::complete_manual_cut(*world, {"P", "P-client"}, cut, field);
        check(result.completed() && std::get<bool>(result.result->at("accepted").storage()),
              "The field actor cuts one named finite timber at a time.");
    }
    const O craft{{"context", V("field-shaping")}, {"client", V("P-client")},
        {"request", V("shape-frame")}, {"actor", V("P")},
        {"action", V("field_craft")}, {"component", V("wooden_frame")}};
    const auto first = world->command({"P", "P-client"}, craft, field);
    check(first.completed() && std::get<bool>(first.result->at("accepted").storage()) &&
          world->snapshot().state.material.cargo.at("P").timber == 1 &&
          world->snapshot().state.material.cargo.at("P").components.at(m::Component::wooden_frame) == 1 &&
          world->snapshot().state.material.timber_remaining.at("field-tree") == 4,
          "The physical actor shapes a frame away from the hub using three carried timber.");
    const auto saved = world->snapshot();
    const auto duplicate = world->command({"P", "P-client"}, craft, field);
    check(duplicate.completed() && std::get<bool>(duplicate.result->at("duplicate").storage()) &&
          world->snapshot().state == saved.state,
          "A retried field craft cannot mint another component or spend more timber.");
    auto full = craft;
    full.at("request") = V("full-bag");
    full.at("component") = V("wooden_shaft");
    const auto refused_full = world->command({"P", "P-client"}, full, field);
    check(refused_full.completed() &&
          std::get<std::string>(refused_full.result->at("reason").storage()) == "inventory_full" &&
          world->snapshot().state == saved.state,
          "The field tool refuses a full component bag without consuming its last timber.");
    auto metal = craft;
    metal.at("request") = V("metal-field");
    metal.at("component") = V("cutting_edge");
    const auto refused_metal = world->command({"P", "P-client"}, metal, field);
    check(refused_metal.completed() &&
          std::get<std::string>(refused_metal.result->at("reason").storage()) == "unavailable_recipe" &&
          world->snapshot().state == saved.state,
          "A copper edge cannot be formed with the field multitool.");
    auto empty = craft;
    empty.at("client") = V("Q-client");
    empty.at("actor") = V("Q");
    empty.at("request") = V("empty-actor");
    const auto refused_empty = world->command({"Q", "Q-client"}, empty, field);
    check(refused_empty.completed() &&
          std::get<std::string>(refused_empty.result->at("reason").storage()) == "unavailable_input" &&
          world->snapshot().state == saved.state,
          "A second actor cannot shape from the first actor's timber.");
    check(w::World::restore("field-shaping", profile, world->snapshot()) != nullptr,
          "Field-shaped wood and all refused attempts survive native checkpoint validation.");
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
    state = seed().second;
    profile.material.manual_ore = m::OreSite{"pod-fabrication-hub", {-3, 0, 0}};
    check(!w::World::create("pod-world", profile, state),
          "A finite ore source cannot reuse the issued workshop identity.");
    profile.material.manual_ore.reset();
    profile.material.timber_sites.emplace("pod-fabrication-hub", m::TimberSite{{12, 0, 12}, 8});
    state.material.timber_remaining.emplace("pod-fabrication-hub", 8);
    check(!w::World::create("pod-world", profile, state),
          "A finite tree cannot reuse the issued workshop identity.");
}

void foundation_custody_cannot_change_actor_on_restore() {
    const auto [profile, state] = seed();
    auto world = w::World::create("pod-foundation-custody", profile, state);
    check(world != nullptr, "The actor custody fixture initializes.");
    auto forged = world->snapshot();
    --forged.state.foundation_kits.at("P");
    ++forged.state.foundation_kits.at("Q");
    check(!w::World::restore("pod-foundation-custody", profile, forged),
          "A checkpoint cannot transfer a carried foundation part between actors without a transaction.");
    const auto cut = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {4, 0, 16}, 7, true, 10};
    };
    const O recover{{"context", V("pod-foundation-custody")}, {"client", V("Q-client")},
        {"request", V("Q-recover-floor")}, {"actor", V("Q")},
        {"action", V("remove_foundation")}, {"target", V("pod-floor-0")},
        {"generation", V(I{1})}};
    const auto recovered = world->command({"Q", "Q-client"}, recover, cut);
    check(recovered.completed() && std::get<bool>(recovered.result->at("accepted").storage()) &&
          world->snapshot().state.foundation_kits.at("Q") == 1 &&
          w::World::restore("pod-foundation-custody", profile, world->snapshot()) != nullptr,
          "Q legitimately acquires one foundation part by recovering a real pod tile.");
    const O rebuild{{"context", V("pod-foundation-custody")}, {"client", V("Q-client")},
        {"request", V("Q-rebuild-floor")}, {"actor", V("Q")},
        {"action", V("place_foundation")},
        {"center", V(V::Array{V(I{0}), V(I{0}), V(I{12})})}};
    const auto rebuilt = world->command({"Q", "Q-client"}, rebuild, cut);
    check(rebuilt.completed() && std::get<bool>(rebuilt.result->at("accepted").storage()) &&
          world->snapshot().state.foundation_kits.at("Q") == 0 &&
          w::World::restore("pod-foundation-custody", profile, world->snapshot()) != nullptr,
          "The recovered actor can spend that part on the same global grid and restore.");
    const O area{{"context", V("pod-foundation-custody")}, {"client", V("P-client")},
        {"request", V("P-expand-two")}, {"actor", V("P")},
        {"action", V("place_foundations")},
        {"center", V(V::Array{V(I{12}), V(I{0}), V(I{12})})},
        {"end", V(V::Array{V(I{12}), V(I{0}), V(I{16})})}};
    const auto expanded = world->command({"P", "P-client"}, area, cut);
    check(expanded.completed() && std::get<bool>(expanded.result->at("accepted").storage()) &&
          world->snapshot().state.foundation_kits.at("P") == 13 &&
          w::World::restore("pod-foundation-custody", profile, world->snapshot()) != nullptr,
          "Area construction spends two pieces from P's kit and restores that actor's balance.");
    const auto saved = w::encode_checkpoint(profile, world->snapshot());
    check(std::holds_alternative<V>(saved), "The real two-actor construction history encodes.");
    auto substituted_profile = profile;
    --substituted_profile.starting_foundation_kits.at("P");
    ++substituted_profile.starting_foundation_kits.at("Q");
    check(std::holds_alternative<w::CheckpointRefusal>(w::decode_checkpoint(
              substituted_profile, "pod-foundation-custody", std::get<V>(saved))),
          "The trusted initial actor allocation belongs in the checkpoint profile fingerprint.");
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
        const auto result = w::tests::complete_manual_cut(*world, {"P", "P-client"}, harvest, near);
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
    const auto fourth_cut = w::tests::complete_manual_cut(*world, {"P", "P-client"}, more_wood, near);
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

void placed_components_keep_custody_and_history() {
    auto [profile, state] = seed();
    profile.build_reach = 4;
    profile.material.component_capacity = 1;
    profile.material.timber_sites = {{"tree", {{8, 0, 20}, 8}}};
    state.material.timber_remaining = {{"tree", 8}};
    auto world = w::World::create("placed-chapter", profile, state);
    check(world != nullptr, "The placement fixture begins with finite timber and no parts.");
    const auto near = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {8, 0, 16}, 2, true, 4};
    };
    const auto far = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {32, 0, 16}, 2, true, 4};
    };
    const auto send = [&](const O& request, w::ObserveActor pose = {}) {
        const auto actor = std::get<std::string>(request.at("actor").storage());
        const auto client = std::get<std::string>(request.at("client").storage());
        const auto observed = pose ? pose : w::ObserveActor(near);
        return std::get<std::string>(request.at("action").storage()) == "harvest_source" ?
            w::tests::complete_manual_cut(*world, {actor, client}, request, observed) :
            world->command({actor, client}, request, observed);
    };
    for (int cut = 0; cut < 3; ++cut) {
        const O harvest{{"context", V("placed-chapter")}, {"client", V("P-client")},
            {"request", V("harvest-" + std::to_string(cut))}, {"actor", V("P")},
            {"action", V("harvest_source")}, {"target", V("tree")}};
        const auto result = send(harvest);
        check(result.completed() && std::get<bool>(result.result->at("accepted").storage()),
            "Three physical cuts make one wooden frame affordable.");
    }
    const O craft{{"context", V("placed-chapter")}, {"client", V("P-client")},
        {"request", V("frame")}, {"actor", V("P")}, {"action", V("craft_component")},
        {"target", V("pod-fabrication-hub")}, {"generation", V(I{1})},
        {"component", V("wooden_frame")}};
    const auto made = send(craft);
    check(made.completed() && std::get<bool>(made.result->at("accepted").storage()),
        "The bench makes one frame from harvested timber.");
    const O place{{"context", V("placed-chapter")}, {"client", V("P-client")},
        {"request", V("place-frame")}, {"actor", V("P")}, {"action", V("place_component")},
        {"component", V("wooden_frame")},
        {"center", V(V::Array{V(I{8}), V(I{0}), V(I{12})})}};
    const auto remote = send(place, far);
    check(remote.completed() && !std::get<bool>(remote.result->at("accepted").storage()) &&
        std::get<std::string>(remote.result->at("reason").storage()) == "out_of_reach",
        "The actor cannot install a part from a remote camera.");
    auto q_place = place;
    q_place.at("actor") = V("Q");
    q_place.at("client") = V("Q-client");
    q_place.at("request") = V("q-place");
    const auto other = send(q_place);
    check(other.completed() && !std::get<bool>(other.result->at("accepted").storage()) &&
        std::get<std::string>(other.result->at("reason").storage()) == "no_component",
        "The second actor cannot place the first actor's carried frame.");
    auto admitted = place;
    admitted.at("request") = V("place-frame-near");
    const auto built = send(admitted);
    check(built.completed() && std::get<bool>(built.result->at("accepted").storage()),
        "Reachable placement consumes one carried part.");
    const auto id = std::get<std::string>(built.result->at("entity").storage());
    const auto serial = std::get<I>(built.result->at("generation").storage());
    const auto installed = world->snapshot();
    check(installed.state.material.cargo.at("P").components.empty() &&
          installed.state.material.placed_components.at(m::Component::wooden_frame) == 1 &&
          installed.state.placed_components.at(id).center == factory::mechanics::Point{8, 0, 12} &&
          installed.state.material.timber_remaining.at("tree") == 5,
        "The installed frame retains all three timber in the canonical material ledger.");
    const O remove_support{{"context", V("placed-chapter")}, {"client", V("P-client")},
        {"request", V("take-support")}, {"actor", V("P")}, {"action", V("remove_foundation")},
        {"target", V("pod-floor-6")}, {"generation", V(I{1})}};
    const auto supported = send(remove_support);
    check(supported.completed() && !std::get<bool>(supported.result->at("accepted").storage()) &&
          std::get<std::string>(supported.result->at("reason").storage()) == "foundation_in_use" &&
          world->snapshot().state == installed.state,
        "The support tile cannot be reclaimed while a built component occupies it.");
    const auto retry = send(admitted,
        [](const std::string&) -> std::optional<a::ActorCut> { return std::nullopt; });
    check(retry.completed() && std::get<bool>(retry.result->at("duplicate").storage()) &&
          world->snapshot().state == installed.state,
        "An exact placement retry cannot install a second frame.");
    auto overlap = place;
    overlap.at("request") = V("overlap");
    const auto occupied = send(overlap);
    check(occupied.completed() && !std::get<bool>(occupied.result->at("accepted").storage()) &&
          std::get<std::string>(occupied.result->at("reason").storage()) == "no_component",
        "A second placement cannot create a frame without another carried component.");
    const auto saved = w::encode_checkpoint(profile, installed);
    check(std::holds_alternative<V>(saved), "Installed component custody and geometry save together.");
    const auto decoded = w::decode_checkpoint(profile, "placed-chapter", std::get<V>(saved));
    check(std::holds_alternative<w::Snapshot>(decoded) &&
          w::World::restore("placed-chapter", profile, std::get<w::Snapshot>(decoded)) != nullptr,
        "Fresh World restore accepts the exact installed identity and material balance.");
    auto forged = installed;
    forged.state.material.cargo.at("P").components.emplace(m::Component::wooden_frame, 1);
    check(!w::World::restore("placed-chapter", profile, forged),
        "An installed part cannot also remain in carried cargo.");
    forged = installed;
    forged.state.placed_components.at(id).center[2] += 1;
    check(!w::World::restore("placed-chapter", profile, forged),
        "A save cannot move an installed part away from its checked placement history.");
    O reclaim{{"context", V("placed-chapter")}, {"client", V("Q-client")},
        {"request", V("reclaim-frame")}, {"actor", V("Q")}, {"action", V("reclaim_component")},
        {"target", V(id)}, {"generation", V(serial)}};
    auto stale = reclaim;
    stale.at("request") = V("stale-generation");
    stale.at("generation") = V(serial + 1);
    const auto wrong_generation = send(stale);
    check(wrong_generation.completed() && !std::get<bool>(wrong_generation.result->at("accepted").storage()) &&
          std::get<std::string>(wrong_generation.result->at("reason").storage()) == "stale_generation" &&
          world->snapshot().state == installed.state,
        "A stale generation cannot retarget a still installed part.");
    auto distant = reclaim;
    distant.at("request") = V("remote-reclaim");
    const auto remote_reclaim = send(distant, far);
    check(remote_reclaim.completed() && !std::get<bool>(remote_reclaim.result->at("accepted").storage()) &&
          std::get<std::string>(remote_reclaim.result->at("reason").storage()) == "out_of_reach" &&
          world->snapshot().state == installed.state,
        "Reclaim requires the second actor to reach the installed component.");
    const auto taken = send(reclaim);
    check(taken.completed() && std::get<bool>(taken.result->at("accepted").storage()) &&
          world->snapshot().state.placed_components.empty() &&
          world->snapshot().state.material.placed_components.empty() &&
          world->snapshot().state.material.cargo.at("Q").components.at(m::Component::wooden_frame) == 1,
        "Another nearby actor can reclaim the exact frame into their own cargo.");
    const auto reclaimed = world->snapshot();
    const auto again = send(reclaim);
    check(again.completed() && std::get<bool>(again.result->at("duplicate").storage()) &&
          world->snapshot().state == reclaimed.state,
        "A reclaim retry cannot credit another frame.");
    reclaim.at("request") = V("reclaim-again");
    const auto missing = send(reclaim);
    check(missing.completed() && !std::get<bool>(missing.result->at("accepted").storage()) &&
          std::get<std::string>(missing.result->at("reason").storage()) == "unknown_target",
        "A fresh command cannot reclaim a removed identity.");
    const auto final_save = w::encode_checkpoint(profile, world->snapshot());
    check(std::holds_alternative<V>(final_save) &&
          std::holds_alternative<w::Snapshot>(w::decode_checkpoint(profile, "placed-chapter", std::get<V>(final_save))),
        "The shared custody transfer survives strict checkpoint validation.");

    auto q_place_again = q_place;
    q_place_again.at("request") = V("q-place-frame-again");
    const auto frame = send(q_place_again);
    check(frame.completed() && std::get<bool>(frame.result->at("accepted").storage()) &&
          world->snapshot().state.material.cargo.at("Q").components.empty(),
          "Q can reinstall its reclaimed frame and free its one carried component slot.");
    const O harvest_more{{"context", V("placed-chapter")}, {"client", V("P-client")},
        {"request", V("harvest-for-shaft")}, {"actor", V("P")},
        {"action", V("harvest_source")}, {"target", V("tree")}};
    check(send(harvest_more).completed(), "P harvests one more finite timber piece.");
    const O craft_shaft{{"context", V("placed-chapter")}, {"client", V("P-client")},
        {"request", V("craft-shaft")}, {"actor", V("P")}, {"action", V("craft_component")},
        {"target", V("pod-fabrication-hub")}, {"generation", V(I{1})},
        {"component", V("wooden_shaft")}};
    check(send(craft_shaft).completed() &&
          world->snapshot().state.material.cargo.at("P").components.at(m::Component::wooden_shaft) == 1,
          "A distinct component type is made from P's own timber.");
    auto place_shaft = place;
    place_shaft.at("request") = V("place-shaft");
    place_shaft.at("component") = V("wooden_shaft");
    place_shaft.at("center") = V(V::Array{V(I{8}), V(I{0}), V(I{15})});
    const auto shaft = send(place_shaft);
    check(shaft.completed() && std::get<bool>(shaft.result->at("accepted").storage()),
          "P installs its shaft while Q's frame remains installed.");
    const auto shaft_id = std::get<std::string>(shaft.result->at("entity").storage());
    auto reclaim_frame = reclaim;
    reclaim_frame.at("request") = V("q-reclaim-frame-again");
    reclaim_frame.at("target") = frame.result->at("entity");
    reclaim_frame.at("generation") = frame.result->at("generation");
    check(send(reclaim_frame).completed() &&
          world->snapshot().state.material.cargo.at("Q").components.at(m::Component::wooden_frame) == 1,
          "Q reclaims its frame with one free slot.");
    auto q_reinstall = q_place_again;
    q_reinstall.at("request") = V("q-reinstall-frame");
    check(send(q_reinstall).completed() && world->snapshot().state.material.cargo.at("Q").components.empty(),
          "Q frees its slot again by reinstalling the frame.");
    auto q_reclaim_shaft = reclaim;
    q_reclaim_shaft.at("request") = V("q-reclaim-shaft");
    q_reclaim_shaft.at("target") = V(shaft_id);
    q_reclaim_shaft.at("generation") = shaft.result->at("generation");
    check(send(q_reclaim_shaft).completed() &&
          world->snapshot().state.material.cargo.at("Q").components.at(m::Component::wooden_shaft) == 1 &&
          w::World::restore("placed-chapter", profile, world->snapshot()) != nullptr,
          "A legitimate mixed-type placement sequence restores under capacity one.");
    auto impossible = world->snapshot();
    auto& records = impossible.history.records;
    std::swap(records[records.size() - 1], records[records.size() - 2]);
    std::swap(records[records.size() - 1].result.at("order"), records[records.size() - 2].result.at("order"));
    std::swap(records[records.size() - 1].result.at("revision"), records[records.size() - 2].result.at("revision"));
    check(!w::World::restore("placed-chapter", profile, impossible),
          "Restore rejects a forged history that temporarily carries a frame and shaft in one slot.");
}

void unbounded_component_reclaim_keeps_history() {
    auto [profile, state] = seed();
    profile.build_reach = 4;
    profile.material.hand_carry_capacity = 0;
    profile.material.component_capacity = 0;
    profile.material.timber_sites = {{"tree", {{8, 0, 20}, 8}}};
    state.material.timber_remaining = {{"tree", 8}};
    auto world = w::World::create("unbounded-chapter", profile, state);
    check(world != nullptr, "The uncapped chapter world starts with finite shared timber.");
    const auto near = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {8, 0, 16}, 2, true, 4};
    };
    const auto send = [&](O request) {
        const auto actor = std::get<std::string>(request.at("actor").storage());
        const auto client = std::get<std::string>(request.at("client").storage());
        return std::get<std::string>(request.at("action").storage()) == "harvest_source" ?
            w::tests::complete_manual_cut(*world, {actor, client}, request, near) :
            world->command({actor, client}, request, near);
    };
    const auto intent = [](const char* request, const char* action) {
        return O{{"context", V("unbounded-chapter")}, {"client", V("P-client")},
            {"request", V(request)}, {"actor", V("P")}, {"action", V(action)}};
    };
    for (int cut = 0; cut < 4; ++cut) {
        auto harvest = intent(("cut-" + std::to_string(cut)).c_str(), "harvest_source");
        harvest.emplace("target", V("tree"));
        const auto result = send(harvest);
        check(result.completed() && std::get<bool>(result.result->at("accepted").storage()),
              "Each finite cut reaches the real actor's inventory.");
    }
    auto frame = intent("frame", "craft_component");
    frame.emplace("target", V("pod-fabrication-hub"));
    frame.emplace("generation", V(I{1}));
    frame.emplace("component", V("wooden_frame"));
    check(std::get<bool>(send(frame).result->at("accepted").storage()),
          "The bench makes a frame from three finite timber units.");
    auto place = intent("place-frame", "place_component");
    place.emplace("component", V("wooden_frame"));
    place.emplace("center", V(V::Array{V(I{8}), V(I{0}), V(I{12})}));
    const auto placed = send(place);
    check(placed.completed() && std::get<bool>(placed.result->at("accepted").storage()),
          "The actor installs the same frame in the world.");
    auto shaft = frame;
    shaft.at("request") = V("shaft");
    shaft.at("component") = V("wooden_shaft");
    check(std::get<bool>(send(shaft).result->at("accepted").storage()),
          "The remaining timber makes a carried shaft.");
    auto reclaim = intent("reclaim-frame", "reclaim_component");
    reclaim.emplace("target", placed.result->at("entity"));
    reclaim.emplace("generation", placed.result->at("generation"));
    const auto returned = send(reclaim);
    check(returned.completed() && std::get<bool>(returned.result->at("accepted").storage()) &&
          world->snapshot().state.material.cargo.at("P").components.at(m::Component::wooden_frame) == 1 &&
          world->snapshot().state.material.cargo.at("P").components.at(m::Component::wooden_shaft) == 1,
          "Reclaim admits a second carried part without a component-slot refusal.");
    const auto snapshot = world->snapshot();
    const auto saved = w::encode_checkpoint(profile, snapshot);
    check(std::holds_alternative<V>(saved), "The uncapped placement and reclaim history encodes.");
    const auto restored = w::decode_checkpoint(profile, "unbounded-chapter", std::get<V>(saved));
    check(std::holds_alternative<w::Snapshot>(restored) &&
          w::World::restore("unbounded-chapter", profile, std::get<w::Snapshot>(restored)) != nullptr &&
          std::get<w::Snapshot>(restored).state == snapshot.state,
          "Restore replays the uncapped actor's exact finite custody and component history.");
}

void loose_shaft_cannot_hold_an_unusable_crank() {
    auto [profile, state] = seed();
    profile.material.timber_sites = {{"tree", {{8, 0, 8}, 4}}};
    state.material.timber_remaining = {{"tree", 4}};
    auto world = w::World::create("loose-crank", profile, state);
    check(world != nullptr, "A finite site initializes for the loose-shaft crank sequence.");
    const w::ObserveActor observe = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {8, 0, 8}, 1, true, 10};
    };
    const auto send = [&](O command) {
        command.emplace("context", V("loose-crank"));
        command.emplace("client", V("P-client"));
        command.emplace("actor", V("P"));
        return world->command({"P", "P-client"}, command, observe);
    };
    for (int cut = 0; cut < 3; ++cut) {
        O command{{"request", V("wood-" + std::to_string(cut))},
            {"action", V("harvest_source")}, {"target", V("tree")},
            {"context", V("loose-crank")}, {"client", V("P-client")},
            {"actor", V("P")}};
        const auto result = w::tests::complete_manual_cut(*world,
            {"P", "P-client"}, command, observe);
        check(result.completed() && std::get<bool>(result.result->at("accepted").storage()),
            "Finite timber pays for a shaft and a separate crank.");
    }
    const auto shaft_craft = send({{"request", V("craft-shaft")},
        {"action", V("field_craft")}, {"component", V("wooden_shaft")}});
    const auto crank_craft = send({{"request", V("craft-crank")},
        {"action", V("field_craft")}, {"component", V("hand_crank")}});
    check(shaft_craft.completed() && crank_craft.completed() &&
          std::get<bool>(shaft_craft.result->at("accepted").storage()) &&
          std::get<bool>(crank_craft.result->at("accepted").storage()),
          "The shaft and crank have separate paid identities.");
    const auto placed = send({{"request", V("place-shaft")},
        {"action", V("place_component")}, {"component", V("wooden_shaft")},
        {"center", V(V::Array{V(I{4}), V(I{0}), V(I{12})})}});
    check(placed.completed() && std::get<bool>(placed.result->at("accepted").storage()),
          "The loose shaft occupies a real supported component cell.");
    const auto fitted = send({{"request", V("fit-loose-shaft")},
        {"action", V("attach_hand_crank")}, {"target", placed.result->at("entity")},
        {"generation", placed.result->at("generation")},
        {"crank", crank_craft.result->at("crank_id")},
        {"crank_generation", crank_craft.result->at("crank_generation")},
        {"port", V(V::Array{V(I{4}), V(I{0}), V(I{12})})}});
    check(fitted.completed() &&
          !std::get<bool>(fitted.result->at("accepted").storage()) &&
          std::get<std::string>(fitted.result->at("reason").storage()) == "not_rotary_input" &&
          world->snapshot().state.crank_items.at(
              std::get<std::string>(crank_craft.result->at("crank_id").storage())).holder == "P",
          "A loose shaft cannot take custody of a crank until it has a native drive identity.");
    check(std::holds_alternative<V>(w::encode_checkpoint(profile, world->snapshot())),
          "Refused loose-shaft attachment keeps exact paid custody saveable.");
}

void portable_bench_crafts_with_finite_shared_stock() {
    auto [profile, state] = seed();
    profile.build_reach = 6;
    profile.material.timber_sites = {{"field-tree", {{20, 0, 16}, 8}}};
    profile.material.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    profile.material.component_capacity = 1;
    state.material.timber_remaining = {{"field-tree", 8}};
    auto world = w::World::create("portable-bench", profile, state);
    check(world != nullptr, "One pod and finite timber and ore initialize for bench relocation.");
    const auto send = [&](const O& intent, std::array<double, 3> position) {
        const auto actor = std::get<std::string>(intent.at("actor").storage());
        const auto client = std::get<std::string>(intent.at("client").storage());
        const w::ObserveActor observe = [position](const std::string& observed) -> std::optional<a::ActorCut> {
            return a::ActorCut{observed, position, 1, true, 6};
        };
        return std::get<std::string>(intent.at("action").storage()) == "harvest_source" ?
            w::tests::complete_manual_cut(*world, {actor, client}, intent, observe) :
            world->command({actor, client}, intent, observe);
    };
    for (int index = 0; index < 4; ++index) {
        const O cut{{"context", V("portable-bench")}, {"client", V("P-client")},
            {"request", V("wood-" + std::to_string(index))}, {"actor", V("P")},
            {"action", V("harvest_source")}, {"target", V("field-tree")}};
        const auto result = send(cut, {20, 0, 16});
        check(result.completed() && std::get<bool>(result.result->at("accepted").storage()),
              "P cuts each of four finite timber units for a portable bench.");
    }
    const O shape{{"context", V("portable-bench")}, {"client", V("P-client")},
        {"request", V("shape-bench")}, {"actor", V("P")}, {"action", V("field_craft")},
        {"component", V("wooden_workbench")}};
    const auto made = send(shape, {20, 0, 16});
    check(made.completed() && std::get<bool>(made.result->at("accepted").storage()) &&
          world->snapshot().state.material.cargo.at("P").components.at(m::Component::wooden_workbench) == 1 &&
          world->snapshot().state.material.timber_remaining.at("field-tree") == 4,
          "The multitool shapes a bench from four carried timber without pod access.");
    const O place{{"context", V("portable-bench")}, {"client", V("P-client")},
        {"request", V("place-bench")}, {"actor", V("P")}, {"action", V("place_component")},
        {"component", V("wooden_workbench")},
        {"center", V(V::Array{V(I{24}), V(I{0}), V(I{16})})}};
    const auto built = send(place, {20, 0, 16});
    check(built.completed() && std::get<bool>(built.result->at("accepted").storage()),
          "P installs the bench on the common tile grid away from the pod.");
    const auto bench_id = std::get<std::string>(built.result->at("entity").storage());
    const auto bench_generation = std::get<I>(built.result->at("generation").storage());
    check(world->snapshot().state.material.placed_components.at(m::Component::wooden_workbench) == 1 &&
          world->snapshot().state.material.cargo.at("P").components.empty(),
          "Placed bench timber stays in the same conserved component ledger.");
    const O stow_hub{{"context", V("portable-bench")}, {"client", V("P-client")},
        {"request", V("stow-pod-workshop")}, {"actor", V("P")},
        {"action", V("stow_fabrication_hub")}, {"target", V("pod-fabrication-hub")},
        {"generation", V(I{1})}};
    const auto stowed = send(stow_hub, {8, 0, 16});
    check(stowed.completed() && std::get<bool>(stowed.result->at("accepted").storage()) &&
          world->snapshot().state.fabrication_hub->holder == "P",
          "P unbolts the one issued pod workshop into explicit actor custody.");
    const O pod_craft{{"context", V("portable-bench")}, {"client", V("Q-client")},
        {"request", V("craft-at-stowed-pod")}, {"actor", V("Q")},
        {"action", V("craft_component")}, {"target", V("pod-fabrication-hub")},
        {"generation", V(I{1})}, {"component", V("cutting_edge")}};
    const auto absent_pod = send(pod_craft, {8, 0, 16});
    check(absent_pod.completed() && !std::get<bool>(absent_pod.result->at("accepted").storage()) &&
          std::get<std::string>(absent_pod.result->at("reason").storage()) == "unknown_target",
          "A stowed pod workshop cannot remain a hidden remote crafting authority.");
    const O ore{{"context", V("portable-bench")}, {"client", V("Q-client")},
        {"request", V("mine-ore")}, {"actor", V("Q")},
        {"action", V("harvest_source")}, {"target", V("ore")}};
    check(std::get<bool>(send(ore, {-3, 0, 0}).result->at("accepted").storage()),
          "Q hand mines one unit from the collector's finite ore source.");
    const O craft{{"context", V("portable-bench")}, {"client", V("Q-client")},
        {"request", V("shape-edge")}, {"actor", V("Q")}, {"action", V("craft_component")},
        {"target", V(bench_id)}, {"generation", V(bench_generation)},
        {"component", V("cutting_edge")}};
    const auto distant = send(craft, {-3, 0, 0});
    check(distant.completed() && !std::get<bool>(distant.result->at("accepted").storage()) &&
          std::get<std::string>(distant.result->at("reason").storage()) == "out_of_reach" &&
          world->snapshot().state.material.cargo.at("Q").raw_units == 1,
          "Q cannot spend carried ore at the remote placed bench.");
    auto near_craft = craft;
    near_craft.at("request") = V("shape-edge-near");
    const auto edge = send(near_craft, {24, 0, 16});
    if (!edge.completed() || !std::get<bool>(edge.result->at("accepted").storage()))
        throw std::runtime_error("Portable bench metal craft refused: " +
            (edge.result ? std::get<std::string>(edge.result->at("reason").storage()) :
                "transaction " + std::to_string(static_cast<int>(edge.error))));
    check(edge.completed() && std::get<bool>(edge.result->at("accepted").storage()) &&
          world->snapshot().state.material.cargo.at("Q").components.at(m::Component::cutting_edge) == 1 &&
          world->snapshot().state.material.cargo.at("Q").raw_units == 0,
          "A second actor cold shapes its own metal at P's shared placed bench.");
    const auto after_edge = world->snapshot();
    const auto duplicate_edge = send(near_craft, {24, 0, 16});
    check(duplicate_edge.completed() && std::get<bool>(duplicate_edge.result->at("duplicate").storage()) &&
          world->snapshot().state == after_edge.state,
          "Repeating the bench craft request does not spend or mint another component.");
    auto second_ore = ore;
    second_ore.at("request") = V("mine-second-ore");
    check(std::get<bool>(send(second_ore, {-3, 0, 0}).result->at("accepted").storage()),
          "Q carries a second ore blank while its component slot is full.");
    auto full_craft = near_craft;
    full_craft.at("request") = V("full-bench-cargo");
    const auto full = send(full_craft, {24, 0, 16});
    check(full.completed() && !std::get<bool>(full.result->at("accepted").storage()) &&
          std::get<std::string>(full.result->at("reason").storage()) == "inventory_full" &&
          world->snapshot().state.material.cargo.at("Q").raw_units == 1,
          "A full actor component slot refuses bench crafting without spending ore.");
    const auto saved = world->snapshot();
    const auto encoded = w::encode_checkpoint(profile, saved);
    check(std::holds_alternative<V>(encoded) &&
          std::holds_alternative<w::Snapshot>(w::decode_checkpoint(profile, "portable-bench", std::get<V>(encoded))) &&
          w::World::restore("portable-bench", profile, saved) != nullptr,
          "Checkpoint and strict history restore keep placed bench identity and both actors' custody.");
    const O reclaim{{"context", V("portable-bench")}, {"client", V("P-client")},
        {"request", V("reclaim-bench")}, {"actor", V("P")},
        {"action", V("reclaim_component")}, {"target", V(bench_id)},
        {"generation", V(bench_generation)}};
    auto stale_reclaim = reclaim;
    stale_reclaim.at("request") = V("stale-bench-reclaim");
    stale_reclaim.at("generation") = V(bench_generation + 1);
    const auto stale = send(stale_reclaim, {20, 0, 16});
    check(stale.completed() && !std::get<bool>(stale.result->at("accepted").storage()) &&
          std::get<std::string>(stale.result->at("reason").storage()) == "stale_generation" &&
          world->snapshot().state.placed_components.contains(bench_id),
          "A stale bench generation cannot reclaim a live workshop.");
    check(std::get<bool>(send(reclaim, {20, 0, 16}).result->at("accepted").storage()) &&
          world->snapshot().state.material.cargo.at("P").components.at(m::Component::wooden_workbench) == 1,
          "P reclaims the exact bench into carried component stock without a refund mint.");
    auto after_removal = craft;
    after_removal.at("request") = V("shape-at-missing-bench");
    const auto missing = send(after_removal, {24, 0, 16});
    check(missing.completed() && !std::get<bool>(missing.result->at("accepted").storage()) &&
          std::get<std::string>(missing.result->at("reason").storage()) == "unknown_target",
          "A removed bench cannot keep crafting through its historical identity.");
    auto raised = place;
    raised.at("request") = V("unsupported-bench");
    raised.at("center") = V(V::Array{V(I{24}), V(I{4}), V(I{16})});
    const auto unsupported = send(raised, {20, 0, 16});
    check(unsupported.completed() && !std::get<bool>(unsupported.result->at("accepted").storage()) &&
          std::get<std::string>(unsupported.result->at("reason").storage()) == "unsupported_bench" &&
          world->snapshot().state.material.cargo.at("P").components.at(m::Component::wooden_workbench) == 1,
          "An elevated bench needs an ordinary aligned foundation and cannot lose its component on refusal.");
    const O deploy_hub{{"context", V("portable-bench")}, {"client", V("P-client")},
        {"request", V("deploy-pod-workshop")}, {"actor", V("P")},
        {"action", V("deploy_fabrication_hub")}, {"target", V("pod-fabrication-hub")},
        {"generation", V(I{1})},
        {"center", V(V::Array{V(I{28}), V(I{0}), V(I{16})})}};
    const auto deployed = send(deploy_hub, {24, 0, 16});
    check(deployed.completed() && std::get<bool>(deployed.result->at("accepted").storage()) &&
          !world->snapshot().state.fabrication_hub->holder &&
          world->snapshot().state.fabrication_hub->center == factory::mechanics::Point{28, 0, 16} &&
          w::World::restore("portable-bench", profile, world->snapshot()) != nullptr,
          "The same issued pod workshop redeploys away from the pod and survives strict replay.");
    const O raised_floor{{"context", V("portable-bench")}, {"client", V("P-client")},
        {"request", V("raised-workshop-floor")}, {"actor", V("P")},
        {"action", V("place_foundation")},
        {"center", V(V::Array{V(I{24}), V(I{2}), V(I{16})})}};
    const auto floor = send(raised_floor, {20, 0, 16});
    check(floor.completed() && std::get<bool>(floor.result->at("accepted").storage()),
          "P places an ordinary foundation two shared height units above ground.");
    auto off_tile = place;
    off_tile.at("request") = V("off-tile-workshop");
    off_tile.at("center") = V(V::Array{V(I{25}), V(I{2}), V(I{16})});
    const auto misaligned = send(off_tile, {20, 0, 16});
    check(misaligned.completed() && !std::get<bool>(misaligned.result->at("accepted").storage()) &&
          std::get<std::string>(misaligned.result->at("reason").storage()) == "unsupported_bench" &&
          world->snapshot().state.material.cargo.at("P").components.at(m::Component::wooden_workbench) == 1,
          "A nearby quarter cell does not become a separate bench grid or consume its component.");
    auto reinstall = place;
    reinstall.at("request") = V("reinstall-bench");
    reinstall.at("center") = V(V::Array{V(I{24}), V(I{2}), V(I{16})});
    const auto reinstalled = send(reinstall, {20, 0, 16});
    check(reinstalled.completed() && std::get<bool>(reinstalled.result->at("accepted").storage()) &&
          world->snapshot().state.material.cargo.at("P").components.empty() &&
          w::World::restore("portable-bench", profile, world->snapshot()) != nullptr,
          "P reinstalls the reclaimed bench at the half-height foundation and frees its carried slot.");
    const O remove_floor{{"context", V("portable-bench")}, {"client", V("P-client")},
        {"request", V("remove-raised-workshop-floor")}, {"actor", V("P")},
        {"action", V("remove_foundation")}, {"target", floor.result->at("entity")},
        {"generation", floor.result->at("generation")}};
    const auto occupied_floor = send(remove_floor, {20, 0, 16});
    check(occupied_floor.completed() && !std::get<bool>(occupied_floor.result->at("accepted").storage()) &&
          std::get<std::string>(occupied_floor.result->at("reason").storage()) == "foundation_in_use",
          "The raised workshop keeps its exact supporting floor from removal.");
    const O more_wood{{"context", V("portable-bench")}, {"client", V("P-client")},
        {"request", V("fifth-wood")}, {"actor", V("P")},
        {"action", V("harvest_source")}, {"target", V("field-tree")}};
    check(std::get<bool>(send(more_wood, {20, 0, 16}).result->at("accepted").storage()),
          "P obtains one more finite timber for crafting after moving the pod hub.");
    const O moved_craft{{"context", V("portable-bench")}, {"client", V("P-client")},
        {"request", V("moved-hub-shaft")}, {"actor", V("P")},
        {"action", V("craft_component")}, {"target", V("pod-fabrication-hub")},
        {"generation", V(I{1})}, {"component", V("wooden_shaft")}};
    check(std::get<bool>(send(moved_craft, {28, 0, 16}).result->at("accepted").storage()) &&
          world->snapshot().state.material.cargo.at("P").components.at(m::Component::wooden_shaft) == 1,
          "The relocated pod workshop crafts from P's own new timber at its actual position.");
    const O install_shaft{{"context", V("portable-bench")}, {"client", V("P-client")},
        {"request", V("install-moved-shaft")}, {"actor", V("P")},
        {"action", V("place_component")}, {"component", V("wooden_shaft")},
        {"center", V(V::Array{V(I{20}), V(I{0}), V(I{20})})}};
    check(std::get<bool>(send(install_shaft, {20, 0, 16}).result->at("accepted").storage()),
          "Installing P's shaft frees the single carried component slot.");
    auto sixth_wood = more_wood;
    sixth_wood.at("request") = V("sixth-wood");
    check(std::get<bool>(send(sixth_wood, {20, 0, 16}).result->at("accepted").storage()),
          "A sixth cut provides finite timber for the raised bench.");
    auto raised_craft = moved_craft;
    raised_craft.at("request") = V("raised-bench-shaft");
    raised_craft.at("target") = reinstalled.result->at("entity");
    raised_craft.at("generation") = reinstalled.result->at("generation");
    check(std::get<bool>(send(raised_craft, {24, 2, 16}).result->at("accepted").storage()) &&
          world->snapshot().state.material.cargo.at("P").components.at(m::Component::wooden_shaft) == 1 &&
          w::World::restore("portable-bench", profile, world->snapshot()) != nullptr,
          "The half-height player-built bench crafts and restores on the same foundation level.");
}
void powered_slide_ticks_and_restores() {
    auto [profile, state] = seed();
    profile.material.timber_sites = {{"slide-tree", {{44, 0, 8}, 8}}};
    profile.material.component_capacity = 2;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}};
    profile.waterwheel_rate = {1, 2};
    state.material.timber_remaining = {{"slide-tree", 8}};
    state.kits.at("P")[{s::Role::waterwheel, 0, 0}] = 1;
    state.topology.drive_enabled = true;
    auto world = w::World::create("powered-slide", profile, state);
    check(world != nullptr, "A finite wheel kit and tree initialize beside the pod deck.");
    const auto actor = [](const std::string& name) -> std::optional<a::ActorCut> {
        return a::ActorCut{name, {44, 0, 8}, 1, true, 10};
    };
    const O wheel{{"context", V("powered-slide")}, {"client", V("P-client")},
        {"request", V("place-wheel")}, {"actor", V("P")}, {"action", V("place")},
        {"role", V("waterwheel")}, {"axis", V("x")}, {"wheel_tiles", V(I{3})},
        {"teeth", V(I{0})}, {"half_span", V(I{0})},
        {"center", V(V::Array{V(I{40}), V(I{4}), V(I{8})})}};
    check(std::get<bool>(world->command({"P", "P-client"}, wheel, actor).result->at("accepted").storage()),
          "The actor places the issued wheel before the slide connects.");
    for (int index = 0; index < 3; ++index) {
        const O cut{{"context", V("powered-slide")}, {"client", V("P-client")},
            {"request", V("wood-" + std::to_string(index))}, {"actor", V("P")},
            {"action", V("harvest_source")}, {"target", V("slide-tree")}};
        check(w::tests::complete_manual_cut(*world, {"P", "P-client"}, cut, actor).completed(),
              "The slide body uses three finite tree units.");
    }
    const O craft{{"context", V("powered-slide")}, {"client", V("P-client")},
        {"request", V("slide-body")}, {"actor", V("P")}, {"action", V("field_craft")},
        {"component", V("wooden_slide")}};
    check(std::get<bool>(world->command({"P", "P-client"}, craft, actor).result->at("accepted").storage()),
          "The actor shapes the slide from harvested wood.");
    const O place{{"context", V("powered-slide")}, {"client", V("P-client")},
        {"request", V("slide-place")}, {"actor", V("P")}, {"action", V("place_component")},
        {"component", V("wooden_slide")},
        {"center", V(V::Array{V(I{41}), V(I{4}), V(I{8})})}};
    const auto installed = world->command({"P", "P-client"}, place, actor);
    check(installed.completed() &&
          std::get<bool>(installed.result->at("accepted").storage()),
          "The slide connects to the trusted half-rate wheel at an adjacent shaft port.");
    const auto id = std::get<std::string>(installed.result->at("entity").storage());
    const auto drive = w::drive_power(profile, world->snapshot().state);
    check(drive.mechanical.motion.at(id).state == factory::mechanics::MotionState::rotating &&
          drive.mechanical.motion.at(id).rate == factory::mechanics::Rate{1, 2},
          "The placed slide receives its actual fractional rate from the nearby wheel.");
    const auto advance = world->tick(actor);
    check(advance.error == w::TransactionError::none &&
          world->snapshot().state.slide_phases.at(id).subticks == 2048,
          "One trusted powered tick moves the carriage by half a shaft turn.");
    const auto wheel_id = world->snapshot().state.topology.parts.front().geometry.id;
    const O stop{{"context", V("powered-slide")}, {"client", V("P-client")},
        {"request", V("stop-wheel")}, {"actor", V("P")}, {"action", V("set_drive")},
        {"target", V(wheel_id)}, {"generation", V(I{1})}, {"enabled", V(false)}};
    check(std::get<bool>(world->command({"P", "P-client"}, stop, actor).result->at("accepted").storage()) &&
          world->tick(actor).error == w::TransactionError::none &&
          world->snapshot().state.slide_phases.at(id).subticks == 2048,
          "Stopping the external wheel freezes the carriage at its last phase.");
    const auto saved = world->snapshot();
    const auto encoded = w::encode_checkpoint(profile, saved);
    check(std::holds_alternative<V>(encoded) &&
          std::holds_alternative<w::Snapshot>(w::decode_checkpoint(profile, "powered-slide", std::get<V>(encoded))) &&
          w::World::restore("powered-slide", profile, saved) != nullptr,
          "The powered carriage phase and its drive history survive save and restore.");
    const O reclaim{{"context", V("powered-slide")}, {"client", V("P-client")},
        {"request", V("reclaim-slide")}, {"actor", V("P")},
        {"action", V("reclaim_component")}, {"target", V(id)},
        {"generation", installed.result->at("generation")}};
    check(std::get<bool>(world->command({"P", "P-client"}, reclaim, actor).result->at("accepted").storage()) &&
          !world->snapshot().state.slide_phases.contains(id) &&
          w::World::restore("powered-slide", profile, world->snapshot()) != nullptr,
          "Reclaiming the slide removes its carriage phase without invalidating history.");
}

void first_plate_gate_admits_only_starter_parts() {
    auto [profile, state] = seed();
    profile.first_plate_unlock = true;
    auto world = w::World::create("first-plate-gate", profile, state);
    check(world != nullptr, "The staged arrival starts with finite stock and its ordinary pod.");
    const auto actor = [](const std::string& name) -> std::optional<a::ActorCut> {
        return a::ActorCut{name, {4, 0, 16}, 1, true, 10};
    };
    const auto send = [&](const std::string& who, O intent) {
        intent.emplace("context", V("first-plate-gate"));
        intent.emplace("client", V(who + "-client"));
        intent.emplace("actor", V(who));
        const auto reply = world->command({who, who + "-client"}, intent, actor);
        check(reply.completed() && reply.result &&
              !std::get<bool>(reply.result->at("accepted").storage()),
              "The empty staged inventory cannot fabricate a part without stock.");
        return std::get<std::string>(reply.result->at("reason").storage());
    };
    I serial = 0;
    for (const auto* who : {"P", "Q"}) {
        for (const auto* kind : {"wooden_cog", "receiver_tray", "sliding_guide",
                                 "ram_face", "wooden_shaft", "wooden_frame", "copper_slide"}) {
            const O intent{{"request", V("early-component-" + std::to_string(++serial))},
                {"action", V("craft_component")}, {"target", V("pod-fabrication-hub")},
                {"generation", V(I{1})}, {"component", V(kind)}};
            check(send(who, intent) == "first_plate_required",
                  "An actor cannot craft advanced components before carrying a plate.");
        }
        for (const auto* role : {"shaft", "belt", "waterwheel"}) {
            const O intent{{"request", V("early-part-" + std::to_string(++serial))},
                {"action", V("craft_part")}, {"target", V("pod-fabrication-hub")},
                {"generation", V(I{1})}, {"role", V(role)}, {"half_span", V(I{0})}};
            check(send(who, intent) == "first_plate_required",
                  "An actor cannot fabricate external transmission or a mill before a plate.");
        }
        const O place{{"request", V("early-placement-" + std::to_string(++serial))},
            {"action", V("place_component")}, {"component", V("receiver_tray")},
            {"center", V(V::Array{V(I{8}), V(I{0}), V(I{0})})}};
        check(send(who, place) == "first_plate_required",
              "Carried or forged advanced components cannot bypass the placement gate.");
        const O foundation{{"request", V("early-foundation-" + std::to_string(++serial))},
            {"action", V("place_foundation")},
            {"center", V(V::Array{V(I{8}), V(I{0}), V(I{0})})}};
        check(send(who, foundation) == "first_plate_required",
              "Issued foundation kits remain locked until their actor's first plate.");
        for (const auto* kind : {"anvil", "flat_head", "wooden_slide"}) {
            const O intent{{"request", V("starter-component-" + std::to_string(++serial))},
                {"action", V("craft_component")}, {"target", V("pod-fabrication-hub")},
                {"generation", V(I{1})}, {"component", V(kind)}};
            check(send(who, intent) != "first_plate_required",
                  "Anvil, separate flat head and wooden slide remain the three starter recipes.");
        }
    }
    check(world->snapshot().state == state &&
          w::World::restore("first-plate-gate", profile, world->snapshot()) != nullptr,
          "All early refusals retain finite stock and restore through the native history.");
}

void sized_cog_recipes_keep_finite_actor_custody() {
    auto [profile, state] = seed();
    profile.material.timber_sites = {{"cog-tree", {{8, 0, 20}, 8}}};
    profile.material.manual_ore = m::OreSite{"cog-ore", {-3, 0, 0}};
    state.material.timber_remaining = {{"cog-tree", 8}};
    profile.fabrication_parts = {{{s::Role::gear, 2, 0}, {1, 1}},
                                 {{s::Role::gear, 4, 0}, {2, 1}}};
    auto world = w::World::create("sized-cogs", profile, state);
    check(world != nullptr, "A pod workshop accepts two finite cogwheel sizes as native recipes.");
    const auto near_tree = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {8, 0, 20}, 1, true, 10};
    };
    const auto near_ore = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {-3, 0, 0}, 1, true, 10};
    };
    const auto near_hub = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {8, 0, 16}, 1, true, 10};
    };
    for (int index = 0; index < 3; ++index) {
        const O cut{{"context", V("sized-cogs")}, {"client", V("P-client")},
            {"request", V("cog-tree-" + std::to_string(index))}, {"actor", V("P")},
            {"action", V("harvest_source")}, {"target", V("cog-tree")}};
        const auto result = w::tests::complete_manual_cut(*world, {"P", "P-client"}, cut, near_tree);
        check(result.completed() && std::get<bool>(result.result->at("accepted").storage()),
              "Each cogwheel timber input is gathered from a finite source.");
    }
    for (int index = 0; index < 2; ++index) {
        const O cut{{"context", V("sized-cogs")}, {"client", V("P-client")},
            {"request", V("cog-ore-" + std::to_string(index))}, {"actor", V("P")},
            {"action", V("harvest_source")}, {"target", V("cog-ore")}};
        const auto result = w::tests::complete_manual_cut(*world, {"P", "P-client"}, cut, near_ore);
        check(result.completed() && std::get<bool>(result.result->at("accepted").storage()),
              "Each cogwheel copper input is gathered from the finite deposit.");
    }
    const auto craft = [](const std::string& request, I teeth, const std::string& actor) {
        return O{{"context", V("sized-cogs")}, {"client", V(actor + "-client")},
            {"request", V(request)}, {"actor", V(actor)}, {"action", V("craft_part")},
            {"target", V("pod-fabrication-hub")}, {"generation", V(I{1})},
            {"role", V("gear")}, {"teeth", V(teeth)}, {"half_span", V(I{0})}};
    };
    auto unsized = craft("unsized-cog", 2, "P");
    unsized.erase("teeth");
    const auto before_refusals = world->snapshot();
    const auto missing_size = world->command({"P", "P-client"}, unsized, near_hub);
    auto fractional = craft("fractional-cog", 2, "P");
    fractional.at("teeth") = V(2.5);
    const auto fractional_size = world->command({"P", "P-client"}, fractional, near_hub);
    check(missing_size.completed() && fractional_size.completed() &&
          std::get<std::string>(missing_size.result->at("reason").storage()) == "invalid_command" &&
          std::get<std::string>(fractional_size.result->at("reason").storage()) == "invalid_command" &&
          world->snapshot().state == before_refusals.state,
          "A missing or fractional tooth count cannot select a gear or spend any stock.");
    const auto without_stock = world->command({"Q", "Q-client"}, craft("q-cog", 2, "Q"), near_hub);
    check(without_stock.completed() && !std::get<bool>(without_stock.result->at("accepted").storage()) &&
          std::get<std::string>(without_stock.result->at("reason").storage()) == "unavailable_input",
          "A second actor cannot spend P's gathered materials at the same bench.");
    for (const I teeth : {I{2}, I{4}}) {
        const auto made = world->command({"P", "P-client"},
            craft("make-cog-" + std::to_string(teeth), teeth, "P"), near_hub);
        check(made.completed() && std::get<bool>(made.result->at("accepted").storage()) &&
              world->snapshot().state.kits.at("P").at({s::Role::gear, teeth, 0}) == 1,
              "Each selected cog size mints exactly one distinct native carried part.");
    }
    const auto saved = world->snapshot();
    check(saved.state.material.cargo.at("P").timber == 0 &&
          saved.state.material.cargo.at("P").raw_units == 0 &&
          saved.state.material.fabricated_timber == 3 &&
          saved.state.material.fabricated_raw == 2 &&
          w::World::restore("sized-cogs", profile, saved) != nullptr,
          "Both gear sizes, material bills and actor custody survive native restoration.");
    const auto encoded = w::encode_checkpoint(profile, saved);
    check(std::holds_alternative<V>(encoded),
          "A workshop with two crafted cog sizes produces a native checkpoint.");
    const auto reopened = w::decode_checkpoint(profile, "sized-cogs", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(reopened) &&
          std::get<w::Snapshot>(reopened).state == saved.state &&
          std::get<w::Snapshot>(reopened).history.order == saved.history.order,
          "An encoded save reopens both cog sizes without minting or losing actor stock.");
    auto forged = saved;
    ++forged.state.kits.at("P").at({s::Role::gear, 2, 0});
    check(w::World::restore("sized-cogs", profile, forged) == nullptr,
          "A saved cog count cannot be increased without a matching native craft transaction.");
    const auto duplicate = world->command({"P", "P-client"}, craft("make-cog-2", 2, "P"), near_hub);
    check(duplicate.completed() && std::get<bool>(duplicate.result->at("duplicate").storage()) &&
          world->snapshot().state == saved.state,
          "Retrying an issued cog recipe cannot mint another part or spend ingredients twice.");
    auto gated_profile = profile;
    gated_profile.first_plate_unlock = true;
    auto gated = w::World::create("sized-cogs-gated", gated_profile, state);
    check(gated != nullptr, "The two cog recipes can be present in a staged first-plate arrival.");
    auto early_cog = craft("before-first-plate", 2, "P");
    early_cog.at("context") = V("sized-cogs-gated");
    const auto early = gated->command({"P", "P-client"}, early_cog, near_hub);
    check(early.completed() && !std::get<bool>(early.result->at("accepted").storage()) &&
          std::get<std::string>(early.result->at("reason").storage()) == "first_plate_required" &&
          gated->snapshot().state == state,
          "Cogwheel fabrication stays locked until the player carries a first plate.");
}
}  // namespace

int main() {
    try {
        settled_pod_and_checkpoint();
        field_wood_shaping_keeps_actor_custody();
        seed_cannot_duplicate_or_forge_pod();
        foundation_custody_cannot_change_actor_on_restore();
        deck_recovery_is_a_normal_world_transaction();
        reachable_craft_uses_one_hub_and_owned_ingredients();
        placed_components_keep_custody_and_history();
        unbounded_component_reclaim_keeps_history();
        loose_shaft_cannot_hold_an_unusable_crank();
        portable_bench_crafts_with_finite_shared_stock();
        powered_slide_ticks_and_restores();
        first_plate_gate_admits_only_starter_parts();
        sized_cog_recipes_keep_finite_actor_custody();
        std::cout << "landing_pod_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "landing_pod_test: " << error.what() << '\n';
        return 1;
    }
}
