#include "factory/checkpoint.hpp"

#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>

namespace {
namespace w = factory::world;
namespace a = factory::authority;
namespace g = factory::mechanics;
namespace m = factory::materials;
using V = factory::values::Value;
using O = V::Object;
using I = V::Integer;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

struct Site { w::Profile profile; w::State state; };

Site site() {
    Site site;
    auto& [profile, state] = site;
    profile.material = {1, 1, 2};
    profile.material.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    profile.material.timber_sites = {{"tree", {{12, 0, 12}, 8}},
                                     {"tree-branch", {{12, 0, 24}, 4}}};
    profile.material.hand_carry_capacity = 24;
    profile.initial_units = 8;
    profile.actors = {"P", "Q"};
    profile.foundation_parts = 24;
    profile.starting_foundation_kits = {{"P", 15}, {"Q", 0}};
    profile.landing_pod_center = g::Point{4, 0, 16};
    profile.meters_per_grid_unit = 0.4125;
    profile.anchor_offset = {0, 0.825, 0};
    profile.build_reach = 4;
    state.material.initial_units = 8;
    state.material.stock.source = 8;
    state.material.cargo = {{"P", {}}, {"Q", {}}};
    state.material.timber_remaining = {{"tree", 8}, {"tree-branch", 4}};
    state.kits = {{"P", {}}, {"Q", {}}};
    state.foundation_kits = {{"P", 15}, {"Q", 0}};
    state.topology.drive_enabled = true;
    state.landing_pod = w::LandingPod{"landing-pod", *profile.landing_pod_center, 1};
    state.fabrication_hub = w::FabricationHub{"pod-fabrication-hub",
        w::landing_hub_center(*profile.landing_pod_center), 1};
    state.hand_crank = w::HandCrank{"pod-hand-crank", 1, std::nullopt};
    state.issued_entities = {{"landing-pod", 1}, {"pod-fabrication-hub", 1},
        {"pod-hand-crank", 1}};
    const auto deck = w::landing_deck_centers(*profile.landing_pod_center);
    for (std::size_t index = 0; index < deck.size(); ++index) {
        const auto id = "pod-floor-" + std::to_string(index);
        state.foundations.emplace(id, w::Foundation{deck[index], 1});
        state.issued_entities.emplace(id, 1);
    }
    return site;
}

O request(const std::string& actor, const std::string& id, const char* action) {
    return {{"context", V("press-feed")}, {"client", V(actor + "-client")},
        {"request", V(id)}, {"actor", V(actor)}, {"action", V(action)}};
}

struct Runner {
    std::unique_ptr<w::World> world;
    a::Point p{1.65, 1, 6.6};
    a::Point q{2, 1, 0};
    explicit Runner(const Site& site) : world(w::World::create("press-feed", site.profile, site.state)) {
        check(world != nullptr, "The finite pod site initializes with no gifted press parts.");
    }
    w::Delivery send(const std::string& actor, const O& intent) {
        const w::ObserveActor observe = [this](const std::string& selected) -> std::optional<a::ActorCut> {
            return a::ActorCut{selected, selected == "P" ? p : q, 1, true, 4};
        };
        return world->command({actor, actor + "-client"}, intent, observe);
    }
    O accept(const std::string& actor, const O& intent) {
        const auto result = send(actor, intent);
        if (!result.completed() || !result.result ||
            !std::get<bool>(result.result->at("accepted").storage()))
            throw std::runtime_error("Request " + std::get<std::string>(intent.at("request").storage()) +
                " refused: " + (result.result ?
                    std::get<std::string>(result.result->at("reason").storage()) : "no result"));
        ++checks;
        return *result.result;
    }
    void refuses(const std::string& actor, const O& intent, const char* reason) {
        const auto result = send(actor, intent);
        check(result.completed() && result.result &&
              !std::get<bool>(result.result->at("accepted").storage()) &&
              std::get<std::string>(result.result->at("reason").storage()) == reason,
              "The authoritative command refuses for the expected concrete reason.");
    }
};

V::Array point(g::Integer x, g::Integer y, g::Integer z) {
    return {V(x), V(y), V(z)};
}

void actor_feed_is_physical_custody() {
    const auto source = site();
    Runner run(source);
    for (int n = 0; n < 8; ++n) {
        auto cut = request("P", "wood-" + std::to_string(n), "harvest_source");
        cut.emplace("target", V("tree"));
        run.accept("P", cut);
    }
    run.p = {4.95, 1, 9.9};
    for (int n = 0; n < 4; ++n) {
        auto cut = request("P", "branch-" + std::to_string(n), "harvest_source");
        cut.emplace("target", V("tree-branch"));
        run.accept("P", cut);
    }
    run.p = {0, 1, 1.65};
    for (int n = 0; n < 6; ++n) {
        auto cut = request("P", "ore-" + std::to_string(n), "harvest_source");
        cut.emplace("target", V("ore"));
        run.accept("P", cut);
    }
    run.p = {1.65, 1, 6.6};
    for (const auto* name : {"wooden_frame", "anvil", "ram_face", "sliding_guide",
                              "tool_mount", "wooden_shaft", "wooden_cog"}) {
        auto craft = request("P", std::string("craft-") + name, "craft_component");
        craft.emplace("target", V("pod-fabrication-hub"));
        craft.emplace("generation", V(I{1}));
        craft.emplace("component", V(name));
        run.accept("P", craft);
    }
    for (const auto* name : {"tool_mount", "wooden_shaft", "wooden_cog"}) {
        auto craft = request("P", std::string("craft-extra-") + name, "craft_component");
        craft.emplace("target", V("pod-fabrication-hub"));
        craft.emplace("generation", V(I{1}));
        craft.emplace("component", V(name));
        run.accept("P", craft);
    }
    run.p = {2, 1, 0};
    struct Part { const char* name; g::Point center; };
    const Part parts[] = {{"wooden_frame", {8, 0, 0}}, {"anvil", {8, 1, 0}},
        {"ram_face", {8, 2, 0}}, {"sliding_guide", {8, 3, 0}},
        {"tool_mount", {8, 4, 0}}, {"wooden_shaft", {9, 4, 0}},
        {"wooden_cog", {10, 4, 0}}};
    std::string frame, shaft;
    g::Integer frame_generation{};
    for (const auto& part : parts) {
        auto place = request("P", std::string("place-") + part.name, "place_component");
        place.emplace("component", V(part.name));
        place.emplace("center", V(point(part.center[0], part.center[1], part.center[2])));
        const auto made = run.accept("P", place);
        if (std::string(part.name) == "wooden_frame") {
            frame = std::get<std::string>(made.at("entity").storage());
            frame_generation = std::get<I>(made.at("generation").storage());
        }
        if (std::string(part.name) == "wooden_shaft") shaft = std::get<std::string>(made.at("entity").storage());
        if (std::string(part.name) == "wooden_shaft") {
            auto incomplete = request("P", "feed-before-cog", "feed_press");
            incomplete.emplace("target", V(frame));
            incomplete.emplace("generation", V(frame_generation));
            incomplete.emplace("entry", V(point(9, 1, 0)));
            run.refuses("P", incomplete, "incomplete_assembly");
        }
    }
    auto feed = request("P", "feed-first", "feed_press");
    feed.emplace("target", V(frame));
    feed.emplace("generation", V(frame_generation));
    feed.emplace("entry", V(point(9, 1, 0)));
    auto obstruction = request("P", "place-feed-obstruction", "place_component");
    obstruction.emplace("component", V("tool_mount"));
    obstruction.emplace("center", V(point(9, 1, 0)));
    const auto obstacle = run.accept("P", obstruction);
    auto blocked = feed;
    blocked.at("request") = V("blocked-entry");
    run.refuses("P", blocked, "blocked_feed");
    auto reclaim_obstacle = request("P", "remove-feed-obstruction", "reclaim_component");
    reclaim_obstacle.emplace("target", obstacle.at("entity"));
    reclaim_obstacle.emplace("generation", obstacle.at("generation"));
    run.accept("P", reclaim_obstacle);
    auto mirror_shaft = request("P", "place-mirror-shaft", "place_component");
    mirror_shaft.emplace("component", V("wooden_shaft"));
    mirror_shaft.emplace("center", V(point(7, 4, 0)));
    const auto alternate_shaft = run.accept("P", mirror_shaft);
    auto mirror_cog = request("P", "place-mirror-cog", "place_component");
    mirror_cog.emplace("component", V("wooden_cog"));
    mirror_cog.emplace("center", V(point(6, 4, 0)));
    const auto alternate_cog = run.accept("P", mirror_cog);
    auto ambiguous = feed;
    ambiguous.at("request") = V("ambiguous-feed");
    run.refuses("P", ambiguous, "ambiguous_assembly");
    for (const auto& [record, id] : {std::pair{alternate_cog, "remove-mirror-cog"},
                                     std::pair{alternate_shaft, "remove-mirror-shaft"}}) {
        auto reclaim = request("P", id, "reclaim_component");
        reclaim.emplace("target", record.at("entity"));
        reclaim.emplace("generation", record.at("generation"));
        run.accept("P", reclaim);
    }
    run.p = {10, 1, 10};
    auto remote = feed;
    remote.at("request") = V("remote-feed");
    run.refuses("P", remote, "out_of_reach");
    run.p = {2, 1, 0};
    auto other = feed;
    other.at("client") = V("Q-client");
    other.at("actor") = V("Q");
    other.at("request") = V("q-feed");
    run.refuses("Q", other, "unavailable_input");
    const auto inserted = run.accept("P", feed);
    check(std::get<I>(inserted.at("moved_raw").storage()) == 1 &&
          run.world->snapshot().state.material.cargo.at("P").raw_units == 1 &&
          run.world->snapshot().state.material.dropped_material.at({8, 1, 0}).raw_units == 1,
          "One carried blank enters the recognized press work point.");
    const auto before_retry = run.world->snapshot();
    const auto retry = run.send("P", feed);
    check(retry.completed() && retry.result &&
          std::get<bool>(retry.result->at("duplicate").storage()) &&
          run.world->snapshot().state == before_retry.state,
          "The exact retry leaves the single work point unchanged.");
    auto full = feed;
    full.at("request") = V("feed-full");
    run.refuses("P", full, "input_full");
    const auto saved = run.world->snapshot();
    const auto encoded = w::encode_checkpoint(source.profile, saved);
    check(std::holds_alternative<V>(encoded), "Fed press state encodes in the canonical World checkpoint.");
    const auto decoded = w::decode_checkpoint(source.profile, "press-feed", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded) &&
          std::get<w::Snapshot>(decoded).state == saved.state,
          "Fresh World restore retains the actor, press and work-point material.");
    auto wrong_actor = saved;
    for (auto& record : wrong_actor.history.records) {
        if (std::get<std::string>(record.intent.at("request").storage()) == "feed-first") {
            record.intent.at("actor") = V("Q");
            record.result.at("actor") = V("Q");
        }
    }
    check(!w::World::restore("press-feed", source.profile, wrong_actor),
          "A checkpoint cannot attribute P's spent ore to Q's empty cargo.");
    auto forged = saved;
    const auto cargo = forged.state.material.dropped_material.at({8, 1, 0});
    forged.state.material.dropped_material.erase({8, 1, 0});
    forged.state.material.dropped_material.emplace(g::Point{8, 1, 1}, cargo);
    check(!w::World::restore("press-feed", source.profile, forged),
          "A checkpoint cannot relocate a fed blank without an accepted pickup.");
    auto remove = request("P", "remove-shaft", "reclaim_component");
    remove.emplace("target", V(shaft));
    remove.emplace("generation", V(I{6}));
    run.accept("P", remove);
    check(run.world->snapshot().state.material.dropped_material.at({8, 1, 0}).raw_units == 1,
          "Dismantling a drive leaves the real blank recoverable under the work head.");
    auto pickup = request("P", "recover-blank", "pickup_material");
    pickup.emplace("center", V(point(8, 1, 0)));
    pickup.emplace("expected", V(O{{"raw", V(I{1})}, {"products", V(I{0})},
        {"work_lots", V(V::Array{})}}));
    run.accept("P", pickup);
    check(run.world->snapshot().state.material.dropped_material.empty() &&
          run.world->snapshot().state.material.cargo.at("P").raw_units == 2,
          "Pickup after dismantling returns the same ore to the actor.");
    const auto recovered = run.world->snapshot();
    check(w::World::restore("press-feed", source.profile, recovered) != nullptr,
          "A saved harvest, craft, feed and pickup history restores with the actor's raw balance.");
}
} // namespace

int main() {
    try {
        actor_feed_is_physical_custody();
        std::cout << "press_feed_world_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "press_feed_world_test: " << error.what() << '\n';
        return 1;
    }
}
