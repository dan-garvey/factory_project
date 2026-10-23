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
    state.freight_beacon = w::FreightBeacon{"first-freight-beacon", w::landing_freight_center(*profile.landing_pod_center), 1};
    state.issued_entities.emplace("first-freight-beacon", 1);
    state.hand_crank = w::HandCrank{"pod-hand-crank", 1, std::nullopt};
    state.issued_entities.emplace("pod-hand-crank", 1);
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
        const auto result = world->command({"P", "P-client"}, cut, field);
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
          "A softmetal edge cannot be formed with the field multitool.");
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
    state.hand_crank.reset();
    check(!w::World::create("pod-world", profile, state),
          "A fresh pod cannot omit its detachable hand crank.");
    state = seed().second;
    state.hand_crank->holder = "Q";
    check(!w::World::create("pod-world", profile, state),
          "A hand crank cannot start in actor cargo without a take transaction.");
    state = seed().second;
    profile.material.manual_ore = m::OreSite{"pod-hand-crank", {-3, 0, 0}};
    check(!w::World::create("pod-world", profile, state),
          "A finite ore source cannot reuse the issued hand crank identity.");
    profile.material.manual_ore.reset();
    profile.material.timber_sites.emplace("pod-hand-crank", m::TimberSite{{12, 0, 12}, 8});
    state.material.timber_remaining.emplace("pod-hand-crank", 8);
    check(!w::World::create("pod-world", profile, state),
          "A finite tree cannot reuse the issued hand crank identity.");
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

void one_hand_crank_moves_between_pod_and_actors() {
    auto [profile, state] = seed();
    profile.build_reach = 4;
    auto world = w::World::create("pod-crank", profile, state);
    check(world != nullptr && world->snapshot().state.hand_crank->holder == std::nullopt,
          "One identified crank begins in the pod tray.");
    const auto near = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {4, 0, 16}, 2, true, 4};
    };
    const auto far = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {20, 0, 16}, 2, true, 4};
    };
    const auto request = [](const char* actor, const char* client, const char* name, const char* action) {
        return O{{"context", V("pod-crank")}, {"client", V(client)}, {"request", V(name)},
            {"actor", V(actor)}, {"action", V(action)},
            {"target", V("pod-hand-crank")}, {"generation", V(I{1})}};
    };
    const auto send = [&](const O& intent, const w::ObserveActor& pose) {
        const auto actor = std::get<std::string>(intent.at("actor").storage());
        const auto client = std::get<std::string>(intent.at("client").storage());
        return world->command({actor, client}, intent, pose);
    };
    const auto first = request("P", "P-client", "take-first", "take_hand_crank");
    const auto remote = send(first, far);
    check(remote.completed() && !std::get<bool>(remote.result->at("accepted").storage()) &&
          std::get<std::string>(remote.result->at("reason").storage()) == "out_of_reach" &&
          !world->snapshot().state.hand_crank->holder,
          "A remote actor cannot acquire the pod tool through the camera.");
    auto admitted = first;
    admitted.at("request") = V("take-near");
    const auto taken = send(admitted, near);
    check(taken.completed() && std::get<bool>(taken.result->at("accepted").storage()) &&
          world->snapshot().state.hand_crank->holder == "P",
          "A reachable actor takes the unique pod crank into actor custody.");
    const auto held = world->snapshot();
    const auto retry = send(admitted, [](const std::string&) -> std::optional<a::ActorCut> {
        return std::nullopt;
    });
    check(retry.completed() && std::get<bool>(retry.result->at("duplicate").storage()) &&
          world->snapshot().state == held.state,
          "An exact take retry cannot mint a second crank after movement.");
    auto stale = request("Q", "Q-client", "stale", "take_hand_crank");
    stale.at("generation") = V(I{2});
    const auto stale_result = send(stale, near);
    check(stale_result.completed() && !std::get<bool>(stale_result.result->at("accepted").storage()) &&
          std::get<std::string>(stale_result.result->at("reason").storage()) == "stale_generation",
          "A stale generation cannot retarget the unique crank.");
    const auto q_take = send(request("Q", "Q-client", "take-while-held", "take_hand_crank"), near);
    check(q_take.completed() && !std::get<bool>(q_take.result->at("accepted").storage()) &&
          std::get<std::string>(q_take.result->at("reason").storage()) == "crank_held" &&
          world->snapshot().state == held.state,
          "Q cannot take a crank already carried by P.");
    const auto q_return = send(request("Q", "Q-client", "return-other", "return_hand_crank"), near);
    check(q_return.completed() && !std::get<bool>(q_return.result->at("accepted").storage()) &&
          std::get<std::string>(q_return.result->at("reason").storage()) == "not_holder",
          "Q cannot return P's carried crank.");
    const auto p_return = request("P", "P-client", "return-first", "return_hand_crank");
    const auto remote_return = send(p_return, far);
    check(remote_return.completed() && !std::get<bool>(remote_return.result->at("accepted").storage()) &&
          std::get<std::string>(remote_return.result->at("reason").storage()) == "out_of_reach",
          "Returning the crank requires physical access to the pod tray.");
    auto near_return = p_return;
    near_return.at("request") = V("return-near");
    const auto returned = send(near_return, near);
    check(returned.completed() && std::get<bool>(returned.result->at("accepted").storage()) &&
          !world->snapshot().state.hand_crank->holder,
          "Returning moves the same crank to its pod tray.");
    const auto q_success = send(request("Q", "Q-client", "take-after-return", "take_hand_crank"), near);
    check(q_success.completed() && std::get<bool>(q_success.result->at("accepted").storage()) &&
          world->snapshot().state.hand_crank->holder == "Q",
          "The other actor can use the same tool after a real return.");
    const auto final_state = world->snapshot();
    const auto encoded = w::encode_checkpoint(profile, final_state);
    check(std::holds_alternative<V>(encoded), "A held crank checkpoint encodes.");
    const auto decoded = w::decode_checkpoint(profile, "pod-crank", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded) &&
          w::World::restore("pod-crank", profile, std::get<w::Snapshot>(decoded)) != nullptr,
          "A fresh World restores Q's exact crank custody and request history.");
    auto forged = final_state;
    forged.state.hand_crank->holder = "P";
    check(!w::World::restore("pod-crank", profile, forged),
          "Changing the held actor without a transaction is rejected on restore.");
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
        return world->command({actor, client}, request, pose ? pose : w::ObserveActor(near));
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
}  // namespace

int main() {
    try {
        settled_pod_and_checkpoint();
        field_wood_shaping_keeps_actor_custody();
        seed_cannot_duplicate_or_forge_pod();
        foundation_custody_cannot_change_actor_on_restore();
        one_hand_crank_moves_between_pod_and_actors();
        deck_recovery_is_a_normal_world_transaction();
        reachable_craft_uses_one_hub_and_owned_ingredients();
        placed_components_keep_custody_and_history();
        std::cout << "landing_pod_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "landing_pod_test: " << error.what() << '\n';
        return 1;
    }
}
