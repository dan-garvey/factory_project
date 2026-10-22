#include "factory/checkpoint.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

namespace {
namespace w = factory::world;
namespace a = factory::authority;
namespace m = factory::materials;
namespace g = factory::mechanics;
namespace s = factory::stationary;
using V = factory::values::Value;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

struct Fixture { w::Profile profile; w::State state; };

Fixture fixture(g::Integer rate = 1) {
    Fixture result;
    auto& [profile, state] = result;
    profile.material = {1, 2, 2};
    profile.material.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    profile.material.timber_sites = {{"tree", {{12, 0, 12}, 7}}};
    profile.initial_units = 2;
    profile.actors = {"P"};
    profile.foundation_parts = 9;
    profile.starting_foundation_kits = {{"P", 0}};
    profile.landing_pod_center = g::Point{4, 0, 16};
    profile.collector_faces = {{{0, 0, 0}, {-1, 0, 0}}};
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1},
        {{s::Role::shaft, 0, 2}, 2}, {{s::Role::belt, 0, 0}, 1}};
    profile.waterwheel_rate = {rate, 1};
    profile.build_reach = 100;
    state.material.initial_units = 2;
    state.material.stock.source = 2;
    state.material.cargo = {{"P", {}}};
    state.material.timber_remaining = {{"tree", 7}};
    state.kits = {{"P", {}}};
    state.landing_pod = w::LandingPod{"landing-pod", *profile.landing_pod_center, 1};
    state.fabrication_hub = w::FabricationHub{"pod-fabrication-hub", w::landing_hub_center(*profile.landing_pod_center), 1};
    state.hand_crank = w::HandCrank{"pod-hand-crank", 1, std::nullopt};
    state.issued_entities = {{"landing-pod", 1}, {"pod-fabrication-hub", 1}, {"pod-hand-crank", 1}};
    const auto deck = w::landing_deck_centers(*profile.landing_pod_center);
    for (std::size_t index = 0; index < deck.size(); ++index) {
        const auto id = "pod-floor-" + std::to_string(index);
        state.foundations.emplace(id, w::Foundation{deck[index], 1});
        state.issued_entities.emplace(id, 1);
    }
    state.foundation_kits = {{"P", 0}};
    state.topology.parts = {
        {{"wheel", g::Kind::hub, {-4, 0, 4}, g::Axis::x, 0, 0}, 1, s::Role::waterwheel},
        {{"inlet", g::Kind::shaft, {0, 0, 4}, g::Axis::x, 0, 2}, 1, s::Role::shaft},
        {{"far", g::Kind::shaft, {0, 0, 8}, g::Axis::x, 0, 2}, 1, s::Role::shaft}};
    state.topology.sources = {{"wheel", profile.waterwheel_rate}};
    state.topology.drive_enabled = true;
    state.topology.belt_spans = {{{"span", "inlet", "far"}, 1}};
    state.material.belt_lanes.emplace("span", m::BeltLane{{std::nullopt, std::nullopt}, 0});
    for (const auto& part : state.topology.parts) state.issued_entities.emplace(part.geometry.id, 1);
    state.issued_entities.emplace("span", 1);
    return result;
}

std::unique_ptr<w::World> create(const Fixture& fixture) {
    check(m::validate(fixture.state.material, fixture.profile.material,
          w::material_path(fixture.state.topology)) == m::Error::none,
          "The test fixture conserves timber and ore through component, tray, and belt custody.");
    check(s::power_view(fixture.state.topology).mechanical.accepted(),
          "The seeded waterwheel and belt shaft geometry form a valid transmission.");
    auto world = w::World::create("collector-belt", fixture.profile, fixture.state);
    check(world != nullptr, "The conserved collector, pod, and real belt geometry initialize.");
    return world;
}

V::Object request(const std::string& id, const char* action) {
    return {{"context", V("collector-belt")}, {"client", V("P-client")},
        {"request", V(id)}, {"actor", V("P")}, {"action", V(action)}};
}

V::Object accepted(w::World& world, const V::Object& intent) {
    const w::ObserveActor nearby = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {0, 0, 0}, 1, true, 100};
    };
    const auto result = world.command({"P", "P-client"}, intent, nearby);
    if (!result.completed() || !result.result || !std::get<bool>(result.result->at("accepted").storage()))
        throw std::runtime_error("Setup action " + std::get<std::string>(intent.at("request").storage()) +
            " refused: " + (result.result ? std::get<std::string>(result.result->at("reason").storage()) : "no outcome"));
    ++checks;
    return *result.result;
}

std::unique_ptr<w::World> prepared(const Fixture& fixture) {
    auto world = create(fixture);
    for (int n = 0; n < 7; ++n) {
        auto wire = request("wood-" + std::to_string(n), "harvest_source");
        wire.emplace("target", V("tree"));
        accepted(*world, wire);
    }
    auto ore = request("ore-for-edge", "harvest_source");
    ore.emplace("target", V("ore"));
    accepted(*world, ore);
    struct Part { const char* name; g::Point center; };
    const Part parts[] = {{"wooden_frame", {0, 0, 0}}, {"tool_mount", {-1, 0, 0}},
        {"cutting_edge", {-2, 0, 0}}, {"receiver_tray", {0, 0, 1}},
        {"wooden_shaft", {1, 0, 0}}};
    std::string drive;
    for (const auto& part : parts) {
        auto craft = request(std::string("craft-") + part.name, "craft_component");
        craft.emplace("target", V("pod-fabrication-hub"));
        craft.emplace("generation", V(g::Integer{1}));
        craft.emplace("component", V(part.name));
        accepted(*world, craft);
        auto place = request(std::string("place-") + part.name, "place_component");
        place.emplace("component", V(part.name));
        place.emplace("center", V(V::Array{V(part.center[0]), V(part.center[1]), V(part.center[2])}));
        const auto placed = accepted(*world, place);
        if (std::string(part.name) == "wooden_shaft") drive = std::get<std::string>(placed.at("entity").storage());
    }
    auto take = request("take-crank", "take_hand_crank");
    take.emplace("target", V("pod-hand-crank"));
    take.emplace("generation", V(g::Integer{1}));
    accepted(*world, take);
    auto turn = request("cut-blank", "turn_hand_crank");
    turn.emplace("target", V(drive));
    turn.emplace("generation", V(g::Integer{5}));
    accepted(*world, turn);
    check(world->snapshot().state.material.dropped_material.contains({0, 0, 1}),
          "The real crank command leaves one raw blank in the assembled receiver.");
    return world;
}

void transfers_only_to_outward_belt() {
    auto f = fixture();
    auto world = prepared(f);
    const auto before = world->snapshot();
    check(world->tick().error == w::TransactionError::none, "A powered route accepts one ordinary tick.");
    const auto after = world->snapshot();
    check(after.state.material.dropped_material.empty() &&
          (after.state.material.belt_lanes.at("span").slots[0] ||
           after.state.material.belt_lanes.at("span").slots[1]),
          "The actual tray item enters an outward belt slot exactly once.");
    check(after.state.material.stock.source == before.state.material.stock.source &&
          after.state.material.initial_units == before.state.material.initial_units,
          "The handoff moves conserved raw custody without another ore debit.");
    const auto encoded = w::encode_checkpoint(f.profile, after);
    check(std::holds_alternative<V>(encoded), "The transferred item encodes in the canonical checkpoint.");
    const auto decoded = w::decode_checkpoint(f.profile, "collector-belt", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded) && std::get<w::Snapshot>(decoded).state == after.state,
          "A fresh World restores the same receiver and belt custody.");
    auto dismantle = request("remove-loaded-belt", "remove_belt_span");
    dismantle.emplace("target", V("span"));
    dismantle.emplace("generation", V(g::Integer{1}));
    const w::ObserveActor nearby = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {0, 0, 0}, 1, true, 100};
    };
    const auto loaded = world->command({"P", "P-client"}, dismantle, nearby);
    check(loaded.completed() && loaded.result &&
          std::get<std::string>(loaded.result->at("reason").storage()) == "occupied_target" &&
          world->snapshot().state.material.belt_lanes.at("span") == after.state.material.belt_lanes.at("span"),
          "A loaded belt refuses removal and retains its exact item.");
    const auto& slots = world->snapshot().state.material.belt_lanes.at("span").slots;
    const auto slot = slots.front() ? 0 : 1;
    auto recover = request("recover-belt-blank", "recover_belt_slot");
    recover.emplace("target", V("span"));
    recover.emplace("generation", V(g::Integer{1}));
    recover.emplace("slot", V(g::Integer{slot}));
    recover.emplace("expected", V(V::Object{{"raw", V(g::Integer{1})},
        {"products", V(g::Integer{0})}, {"work_lots", V(V::Array{})}}));
    accepted(*world, recover);
    auto remove_empty = request("remove-empty-belt", "remove_belt_span");
    remove_empty.emplace("target", V("span"));
    remove_empty.emplace("generation", V(g::Integer{1}));
    accepted(*world, remove_empty);
    check(world->snapshot().state.material.belt_lanes.empty() &&
          world->snapshot().state.material.cargo.at("P").raw_units == 1,
          "Recovering the blank before dismantling keeps it in actor cargo.");
    check(w::World::restore("collector-belt", f.profile, world->snapshot()) != nullptr,
          "A saved belt recovery restores the actor's raw balance.");
    check(world->tick().error == w::TransactionError::none,
          "A later tick does not invent another blank when the receiver is empty.");
    auto reverse = fixture(-1);
    auto wrong = prepared(reverse);
    check(wrong->tick().error == w::TransactionError::none &&
          wrong->snapshot().state.material.dropped_material.contains({0, 0, 1}),
          "A belt moving toward the collector cannot pull from its receiver.");
    auto inward = fixture(-1);
    inward.state.topology.parts.back().geometry.center = {0, 4, 0};
    auto approaching = prepared(inward);
    check(approaching->tick().error == w::TransactionError::none &&
          approaching->snapshot().state.material.dropped_material.contains({0, 0, 1}),
          "An inclined belt approaching the frame cannot claim the adjacent tray as an inlet.");
    auto stopped = fixture();
    stopped.state.topology.drive_enabled = false;
    auto idle = prepared(stopped);
    check(idle->tick().error == w::TransactionError::none &&
          idle->snapshot().state.material.dropped_material.contains({0, 0, 1}),
          "A stopped belt retains the item in the tray.");
    auto full = fixture();
    full.profile.initial_units = full.state.material.initial_units = 3;
    full.state.material.stock.source = 3;
    auto blocked = prepared(full);
    auto extra = request("extra-ore", "harvest_source");
    extra.emplace("target", V("ore"));
    accepted(*blocked, extra);
    auto load = request("fill-inlet", "load_belt_slot");
    load.emplace("target", V("span"));
    load.emplace("generation", V(g::Integer{1}));
    load.emplace("slot", V(g::Integer{0}));
    load.emplace("item", V("raw"));
    load.emplace("work_id", V(g::Integer{0}));
    accepted(*blocked, load);
    check(w::World::restore("collector-belt", full.profile, blocked->snapshot()) != nullptr,
          "A saved belt load restores after spending one actor-carried raw unit.");
    check(blocked->tick().error == w::TransactionError::none &&
          blocked->snapshot().state.material.dropped_material.contains({0, 0, 1}),
          "An occupied inlet holds the collector item without loss.");
    auto incomplete = prepared(fixture());
    auto remove_tray = request("remove-tray", "reclaim_component");
    remove_tray.emplace("target", V("native-part-4"));
    remove_tray.emplace("generation", V(g::Integer{4}));
    accepted(*incomplete, remove_tray);
    check(incomplete->tick().error == w::TransactionError::none &&
          incomplete->snapshot().state.material.dropped_material.contains({0, 0, 1}),
          "A loose item where an old receiver stood cannot bypass the missing tray.");
    auto no_belt = fixture();
    no_belt.state.topology.belt_spans.clear();
    no_belt.state.material.belt_lanes.clear();
    no_belt.state.issued_entities.erase("span");
    no_belt.state.kits.at("P")[{s::Role::belt, 0, 0}] = 1;
    auto disconnected = prepared(no_belt);
    check(disconnected->tick().error == w::TransactionError::none &&
          disconnected->snapshot().state.material.dropped_material.contains({0, 0, 1}),
          "An absent belt leaves the hand-cut blank in the ready receiver.");
}

} // namespace

int main() {
    try {
        transfers_only_to_outward_belt();
        std::cout << "collector_belt_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "collector_belt_test: " << error.what() << '\n';
        return 1;
    }
}
