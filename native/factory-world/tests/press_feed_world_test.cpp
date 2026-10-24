#include "factory/checkpoint.hpp"
#include "native/factory-world/tests/harvest_fixture.hpp"

#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>

namespace {
namespace w = factory::world;
namespace a = factory::authority;
namespace g = factory::mechanics;
namespace m = factory::materials;
namespace s = factory::stationary;
using V = factory::values::Value;
using O = V::Object;
using I = V::Integer;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

std::unique_ptr<w::World> codec_restore(const w::Profile& profile,
        const w::Snapshot& snapshot, const char* message) {
    const auto encoded = w::encode_checkpoint(profile, snapshot);
    if (!std::holds_alternative<V>(encoded))
        throw std::runtime_error(std::string(message) + " (checkpoint encoding refused)");
    ++checks;
    const auto decoded = w::decode_checkpoint(profile, "press-feed", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded), "The powered press checkpoint decodes.");
    auto restored = w::World::restore("press-feed", profile, std::get<w::Snapshot>(decoded));
    check(restored && restored->snapshot().state == snapshot.state &&
          restored->snapshot().revision == snapshot.revision, message);
    return restored;
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
    profile.initial_units = 10;
    profile.actors = {"P", "Q"};
    profile.foundation_parts = 24;
    profile.starting_foundation_kits = {{"P", 15}, {"Q", 0}};
    profile.landing_pod_center = g::Point{4, 0, 16};
    profile.meters_per_grid_unit = 0.4125;
    profile.anchor_offset = {0, 0.825, 0};
    profile.build_reach = 4;
    profile.waterwheel_rate = {2, 1};
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}};
    state.material.initial_units = 10;
    state.material.stock.source = 10;
    state.material.cargo = {{"P", {}}, {"Q", {}}};
    state.material.timber_remaining = {{"tree", 8}, {"tree-branch", 4}};
    state.kits = {{"P", {}}, {"Q", {}}};
    state.foundation_kits = {{"P", 15}, {"Q", 0}};
    state.topology.drive_enabled = true;
    state.topology.parts = {
        {{"press-wheel", g::Kind::hub, {4, 4, 0}, g::Axis::x, 0, 0}, 1, s::Role::waterwheel}};
    state.topology.sources = {{"press-wheel", profile.waterwheel_rate}};
    state.landing_pod = w::LandingPod{"landing-pod", *profile.landing_pod_center, 1};
    state.fabrication_hub = w::FabricationHub{"pod-fabrication-hub",
        w::landing_hub_center(*profile.landing_pod_center), 1};
    state.freight_beacon = w::FreightBeacon{"first-freight-beacon",
        w::landing_freight_center(*profile.landing_pod_center), 1};
    state.hand_crank = w::HandCrank{"pod-hand-crank", 1, std::nullopt};
    state.issued_entities = {{"landing-pod", 1}, {"pod-fabrication-hub", 1}, {"first-freight-beacon", 1},
        {"pod-hand-crank", 1}, {"press-wheel", 1}};
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
        return std::get<std::string>(intent.at("action").storage()) == "harvest_source" ?
            w::tests::complete_manual_cut(*world, {actor, actor + "-client"}, intent, observe) :
            world->command({actor, actor + "-client"}, intent, observe);
    }
    O accept(const std::string& actor, const O& intent) {
        const auto result = send(actor, intent);
        if (!result.completed() || !result.result ||
            !std::get<bool>(result.result->at("accepted").storage()))
            throw std::runtime_error("Request " + std::get<std::string>(intent.at("request").storage()) +
                " refused (transaction " + std::to_string(static_cast<int>(result.error)) + "): " + (result.result ?
                    std::get<std::string>(result.result->at("reason").storage()) : "no result"));
        ++checks;
        return *result.result;
    }
    void refuses(const std::string& actor, const O& intent, const char* reason) {
        const auto result = send(actor, intent);
        if (!result.completed() || !result.result ||
            std::get<bool>(result.result->at("accepted").storage()) ||
            std::get<std::string>(result.result->at("reason").storage()) != reason)
            throw std::runtime_error("Request " +
                std::get<std::string>(intent.at("request").storage()) +
                " expected refusal " + reason + ", received " +
                (result.result ? std::get<std::string>(result.result->at("reason").storage()) :
                    "no result"));
        ++checks;
    }
};

V::Array point(g::Integer x, g::Integer y, g::Integer z) {
    return {V(x), V(y), V(z)};
}

void frame_free_hand_press(g::Point center, g::Point direction) {
    auto source = site();
    source.profile.build_reach = 100;
    source.profile.material.raw_mass = 4;
    source.profile.material.plate_mass = 3;
    source.profile.material.sheet_mass = 12;
    source.profile.waterwheel_rate = {1, 1};
    source.state.topology.sources = {{"press-wheel", source.profile.waterwheel_rate}};
    auto& wheel = source.state.topology.parts.front().geometry;
    wheel.center = {center[0] - 4 * direction[0], center[1] + 4,
                    center[2] - 4 * direction[2]};
    wheel.axis = direction[0] ? g::Axis::x : g::Axis::z;
    Runner run(source);
    for (int index = 0; index < 5; ++index) {
        auto harvest = request("P", "guided-timber-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("tree"));
        run.accept("P", harvest);
    }
    if (center[1] == 0)
        for (int index = 0; index < 4; ++index) {
            auto harvest = request("P", "guided-offcut-timber-" + std::to_string(index),
                "harvest_source");
            harvest.emplace("target", V("tree-branch"));
            run.accept("P", harvest);
        }
    run.p = {0, 1, 1.65};
    for (int index = 0; index < 5; ++index) {
        auto harvest = request("P", "guided-ore-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("ore"));
        run.accept("P", harvest);
    }
    run.p = {1.65, 1, 6.6};
    for (const auto* kind : {"anvil", "ram_face", "sliding_guide", "wooden_shaft", "wooden_cog",
                             "tool_mount"}) {
        auto craft = request("P", std::string("guided-craft-") + kind, "craft_component");
        craft.emplace("target", V("pod-fabrication-hub"));
        craft.emplace("generation", V(I{1}));
        craft.emplace("component", V(kind));
        run.accept("P", craft);
    }
    run.p = {2, 1, 0};
    if (center[1] > 0) {
        auto foundation = request("P", "guided-raised-foundation", "place_foundation");
        foundation.emplace("center", V(point(center[0], center[1], center[2])));
        run.accept("P", foundation);
    }
    const std::pair<const char*, g::Point> parts[] = {
        {"anvil", center}, {"ram_face", {center[0], center[1] + 1, center[2]}},
        {"sliding_guide", {center[0], center[1] + 3, center[2]}},
        {"wooden_shaft", {center[0] + direction[0], center[1] + 4,
                           center[2] + direction[2]}},
        {"wooden_cog", {center[0] + 2 * direction[0], center[1] + 4,
                         center[2] + 2 * direction[2]}}};
    std::string anvil, shaft;
    I anvil_generation{};
    for (const auto& [kind, center] : parts) {
        auto place = request("P", std::string("guided-place-") + kind, "place_component");
        place.emplace("component", V(kind));
        place.emplace("center", V(point(center[0], center[1], center[2])));
        const auto made = run.accept("P", place);
        if (std::string(kind) == "anvil") {
            anvil = std::get<std::string>(made.at("entity").storage());
            anvil_generation = std::get<I>(made.at("generation").storage());
        }
        if (std::string(kind) == "wooden_shaft") shaft = std::get<std::string>(made.at("entity").storage());
        if (std::string(kind) == "wooden_shaft") {
            auto incomplete = request("P", "guided-incomplete-feed", "feed_press");
            incomplete.emplace("target", V(anvil));
            incomplete.emplace("generation", V(anvil_generation));
            incomplete.emplace("entry", V(point(center[0] + direction[0], center[1],
                                                center[2] + direction[2])));
            run.refuses("P", incomplete, "incomplete_assembly");
        }
    }
    auto feed = request("P", "guided-feed", "feed_press");
    feed.emplace("target", V(anvil));
    feed.emplace("generation", V(anvil_generation));
    feed.emplace("entry", V(point(center[0] + direction[0], center[1],
                                 center[2] + direction[2])));
    auto block_stroke = request("P", "guided-place-stroke-obstacle", "place_component");
    block_stroke.emplace("component", V("tool_mount"));
    block_stroke.emplace("center", V(point(center[0], center[1] + 2, center[2])));
    const auto obstruction = run.accept("P", block_stroke);
    const auto before_blocked_stroke = run.world->snapshot().state;
    auto blocked_feed = feed;
    blocked_feed.at("request") = V("guided-blocked-stroke-feed");
    run.refuses("P", blocked_feed, "incomplete_assembly");
    check(run.world->snapshot().state == before_blocked_stroke,
          "A blocked guided stroke refuses feed without debiting the actor's copper.");
    check(codec_restore(source.profile, run.world->snapshot(),
              "The blocked guided press retains its exact refusal and copper custody on reload.") != nullptr,
          "A blocked stroke and refused feed survive the normal World checkpoint.");
    auto clear_stroke = request("P", "guided-clear-stroke", "reclaim_component");
    clear_stroke.emplace("target", obstruction.at("entity"));
    clear_stroke.emplace("generation", obstruction.at("generation"));
    run.accept("P", clear_stroke);
    run.accept("P", feed);
    const auto power = w::drive_power(source.profile, run.world->snapshot().state);
    check(power.mechanical.accepted() && power.mechanical.motion.at(anvil).state ==
          g::MotionState::rotating,
          "A frame-free press projects an actual powered hub and signed drive shaft.");
    const auto fed = run.world->snapshot();
    check(fed.state.material.dropped_material.at(center).raw_units == 1 &&
          codec_restore(source.profile, fed, "A frame-free fed press restores with exact custody."),
          "A placed anvil owns the fed raw piece without a frame or mount.");
    Runner halted(source);
    halted.world = w::World::restore("press-feed", source.profile, fed);
    auto stop = request("P", "guided-stop-drive", "set_drive");
    stop.emplace("target", V("press-wheel"));
    stop.emplace("generation", V(I{1}));
    stop.emplace("enabled", V(false));
    halted.accept("P", stop);
    check(halted.world->tick().error == w::TransactionError::none &&
          halted.world->snapshot().state.material.dropped_material.at(center).raw_units == 1 &&
          w::World::restore("press-feed", source.profile, halted.world->snapshot()) != nullptr,
          "Stopping the drive retains the exact frame-free input for later continuation.");
    Runner automated(source);
    automated.world = w::World::restore("press-feed", source.profile, fed);
    check(automated.world != nullptr, "The same fed frame-free press restores for powered continuation.");
    const g::Point plate_exit{center[0] - direction[0], center[1], center[2] - direction[2]};
    const g::Point offcut_tray = direction[0] ?
        g::Point{center[0], center[1], center[2] + 1} :
        g::Point{center[0] + 1, center[1], center[2]};
    if (center[1] == 0) {
        for (const auto& [name, location] : {
                 std::pair{"offcut", offcut_tray}, std::pair{"plate", plate_exit}}) {
            auto craft = request("P", std::string("guided-") + name + "-craft-tray", "craft_component");
            craft.emplace("target", V("pod-fabrication-hub"));
            craft.emplace("generation", V(I{1}));
            craft.emplace("component", V("receiver_tray"));
            automated.accept("P", craft);
            auto place = request("P", std::string("guided-") + name + "-place-tray", "place_component");
            place.emplace("component", V("receiver_tray"));
            place.emplace("center", V(point(location[0], location[1], location[2])));
            automated.accept("P", place);
        }
    }
    for (int index = 0; index < 4; ++index)
        check(automated.world->tick().error == w::TransactionError::none,
              "The connected floating press advances under real signed shaft motion.");
    const auto automatic = automated.world->snapshot();
    const g::Point exit = plate_exit;
    check(automatic.state.material.dropped_material.at(exit).products == 1 &&
          automatic.state.material.dropped_material.at(center[1] == 0 ? offcut_tray : center).offcuts == 1 &&
          w::validate(source.profile, automatic),
          "Powered frame-free forming conserves one plate and its physical offcut destination.");
    codec_restore(source.profile, automatic,
                  "Powered frame-free production and its offcut survive checkpoint reload.");
    if (center[1] == 0) {
        auto displaced = automatic;
        const auto offcuts = displaced.state.material.dropped_material.at(offcut_tray);
        displaced.state.material.dropped_material.erase(offcut_tray);
        displaced.state.material.dropped_material.emplace(center, offcuts);
        check(!w::World::restore("press-feed", source.profile, displaced),
              "A checkpoint cannot silently return a delivered offcut to the work face.");
        auto wrong_route = automatic;
        wrong_route.state.press_offcut_deliveries.begin()->second.receiver = center;
        check(!w::World::restore("press-feed", source.profile, wrong_route),
              "A checkpoint cannot retarget the press discharge receipt to another point.");
        automated.p = {2, 1, 0};
        for (int index = 1; index < 4; ++index) {
            automated.p = {0, 1, 1.65};
            auto harvest = request("P", "guided-auto-ore-" + std::to_string(index),
                                   "harvest_source");
            harvest.emplace("target", V("ore"));
            automated.accept("P", harvest);
            automated.p = {2, 1, 0};
            auto next = feed;
            next.at("request") = V("guided-auto-feed-" + std::to_string(index));
            automated.accept("P", next);
            for (int tick = 0; tick < 4; ++tick)
                check(automated.world->tick().error == w::TransactionError::none,
                      "The powered press advances another finite raw piece.");
            const auto cycled = automated.world->snapshot();
            check(cycled.state.material.dropped_material.at(offcut_tray).offcuts == index + 1 &&
                  cycled.state.material.dropped_material.at(exit).products == index + 1 &&
                  cycled.state.press_output_at_receiver.at(exit).size() ==
                      static_cast<std::size_t>(index + 1) &&
                  w::validate(source.profile, cycled),
                  "Each powered stroke leaves its plate and offcut in separate fitted trays.");
        }
        const auto four = automated.world->snapshot();
        check(four.state.material.dropped_material.at(exit).products == 4 &&
              four.state.press_output_at_receiver.at(exit).size() == 4 &&
              four.state.material.dropped_material.at(offcut_tray).offcuts == 4,
              "Four powered strokes retain four identified plates and four offcuts without pickup.");
        codec_restore(source.profile, four,
                      "Four products in the fitted plate tray survive a checkpoint.");
        Runner finished_pickup(source);
        finished_pickup.world = w::World::restore("press-feed", source.profile, four);
        check(finished_pickup.world != nullptr, "Q can collect a full tray before another feed.");
        auto collect_finished = request("Q", "guided-auto-collect-finished-four", "pickup_material");
        collect_finished.emplace("center", V(point(exit[0], exit[1], exit[2])));
        collect_finished.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{4})},
            {"work_lots", V(V::Array{})}, {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
        finished_pickup.accept("Q", collect_finished);
        codec_restore(source.profile, finished_pickup.world->snapshot(),
                      "The fourth plate can leave a full receiver before any later feed.");
        auto duplicated = four;
        duplicated.state.press_output_at_receiver[exit].insert(
            *duplicated.state.press_output_at_receiver[exit].begin() + 1000);
        check(!w::World::restore("press-feed", source.profile, duplicated),
              "A checkpoint cannot invent another identified plate inside the tray.");
        automated.p = {0, 1, 1.65};
        auto harvest = request("P", "guided-auto-ore-full-tray", "harvest_source");
        harvest.emplace("target", V("ore"));
        automated.accept("P", harvest);
        automated.p = {2, 1, 0};
        auto fifth = feed;
        fifth.at("request") = V("guided-auto-feed-full-tray");
        automated.accept("P", fifth);
        for (int tick = 0; tick < 4; ++tick)
            check(automated.world->tick().error == w::TransactionError::none,
                  "The blocked fifth work piece remains governed by native ticks.");
        const auto blocked = automated.world->snapshot();
        check(blocked.state.material.dropped_material.at(offcut_tray).offcuts == 4 &&
              blocked.state.material.dropped_material.at(exit).products == 4 &&
              blocked.state.material.dropped_material.at(center).work_lots.size() == 1 &&
              blocked.state.material.dropped_material.at(center).work_lots.front().remaining_ticks == 0 &&
              w::validate(source.profile, blocked),
              "Both full trays hold the fifth ready work without creating a fifth plate.");
        codec_restore(source.profile, blocked,
                      "Full-tray backpressure and ready work survive checkpoint reload.");
        Runner resumed(source);
        resumed.world = w::World::restore("press-feed", source.profile, blocked);
        check(resumed.world != nullptr, "A second actor rejoins the exact blocked World.");
        auto clear_plates = request("Q", "guided-auto-clear-plates", "pickup_material");
        clear_plates.emplace("center", V(point(exit[0], exit[1], exit[2])));
        clear_plates.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{4})},
            {"work_lots", V(V::Array{})}, {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
        const auto collected = resumed.accept("Q", clear_plates);
        check(std::get<V::Array>(collected.at("press_output_work_ids").storage()).size() == 4,
              "Q's pickup names all four original plate work identities.");
        check(resumed.world->tick().error == w::TransactionError::none,
              "The offcut holder still blocks the fifth stroke after Q clears only the plates.");
        check(resumed.world->snapshot().state.material.dropped_material.at(center).work_lots.front().remaining_ticks == 0,
              "The fifth ready work remains in place while the side tray is full.");
        auto clear_tray = request("Q", "guided-auto-clear-tray", "pickup_material");
        clear_tray.emplace("center", V(point(offcut_tray[0], offcut_tray[1], offcut_tray[2])));
        clear_tray.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
            {"work_lots", V(V::Array{})}, {"offcuts", V(I{4})}, {"sheets", V(I{0})}}));
        resumed.accept("Q", clear_tray);
        codec_restore(source.profile, resumed.world->snapshot(),
                      "Q's recovery of both fitted trays survives a checkpoint.");
        check(resumed.world->tick().error == w::TransactionError::none,
              "Freeing both physical holders resumes the held fifth stroke.");
        const auto continued = resumed.world->snapshot();
        check(continued.state.material.cargo.at("Q").products == 4 &&
              continued.state.material.cargo.at("Q").offcuts == 4 &&
              continued.state.material.dropped_material.at(exit).products == 1 &&
              continued.state.press_output_at_receiver.at(exit).size() == 1 &&
              continued.state.material.dropped_material.at(offcut_tray).offcuts == 1 &&
              !continued.state.material.dropped_material.contains(center) &&
              w::validate(source.profile, continued),
              "Shared continuation releases exactly one fifth plate and one new offcut.");
        codec_restore(source.profile, continued,
                      "The resumed plate, old offcuts and new offcut restore without duplication.");
        Runner fifth_recovery(source);
        fifth_recovery.world = w::World::restore("press-feed", source.profile, continued);
        check(fifth_recovery.world != nullptr, "Q can resume before collecting the identified fifth plate.");
        auto clear_fifth = request("Q", "guided-auto-clear-fifth", "pickup_material");
        clear_fifth.emplace("center", V(point(exit[0], exit[1], exit[2])));
        clear_fifth.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{1})},
            {"work_lots", V(V::Array{})}, {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
        const auto fifth_pickup = fifth_recovery.accept("Q", clear_fifth);
        check(std::get<V::Array>(fifth_pickup.at("press_output_work_ids").storage()).size() == 1,
              "The later pickup preserves the fifth plate's identity.");
        codec_restore(source.profile, fifth_recovery.world->snapshot(),
                      "Q's pickup of the resumed fifth plate survives a second save.");
        auto next_ore = request("P", "guided-fitted-manual-ore", "harvest_source");
        next_ore.emplace("target", V("ore"));
        resumed.accept("P", next_ore);
        auto take_crank = request("P", "guided-fitted-take-crank", "take_hand_crank");
        take_crank.emplace("target", V("pod-hand-crank"));
        take_crank.emplace("generation", V(I{1}));
        resumed.accept("P", take_crank);
        auto manual_feed = feed;
        manual_feed.at("request") = V("guided-fitted-manual-feed");
        resumed.accept("P", manual_feed);
        auto manual_turn = request("P", "guided-fitted-manual-turn", "turn_press_crank");
        manual_turn.emplace("target", V(anvil));
        manual_turn.emplace("generation", V(anvil_generation));
        manual_turn.emplace("drive", V(shaft));
        manual_turn.emplace("exit", V(point(exit[0], exit[1], exit[2])));
        for (int index = 0; index < 3; ++index) {
            manual_turn.at("request") = V("guided-fitted-manual-turn-" + std::to_string(index));
            resumed.accept("P", manual_turn);
        }
        const auto manual = resumed.world->snapshot();
        check(manual.state.material.dropped_material.at(exit).products == 2 &&
              manual.state.press_output_at_receiver.at(exit).size() == 2 &&
              w::validate(source.profile, manual) &&
              codec_restore(source.profile, manual,
                  "A manually turned plate stacks with the powered fifth plate through a checkpoint."),
              "Manual and powered products share one finite physical plate receiver.");
    }
    run.p = {1.65, 1, 6.6};
    auto take = request("P", "guided-take-crank", "take_hand_crank");
    take.emplace("target", V("pod-hand-crank"));
    take.emplace("generation", V(I{1}));
    run.accept("P", take);
    run.p = {2, 1, 0};
    auto turn = request("P", "guided-turn", "turn_press_crank");
    turn.emplace("target", V(anvil));
    turn.emplace("generation", V(anvil_generation));
    turn.emplace("drive", V(shaft));
    turn.emplace("exit", V(point(exit[0], exit[1], exit[2])));
    auto wrong_drive = turn;
    wrong_drive.at("request") = V("guided-wrong-drive");
    wrong_drive.at("drive") = V(anvil);
    const auto before_wrong_drive = run.world->snapshot().state;
    run.refuses("P", wrong_drive, "wrong_drive_shaft");
    check(run.world->snapshot().state == before_wrong_drive,
          "A non-drive target cannot advance or discard frame-free work.");
    auto obstacle = request("P", "guided-block-exit", "place_component");
    obstacle.emplace("component", V("tool_mount"));
    obstacle.emplace("center", V(point(exit[0], exit[1], exit[2])));
    const auto placed_obstacle = run.accept("P", obstacle);
    const auto before_blocked = run.world->snapshot().state;
    auto blocked_turn = turn;
    blocked_turn.at("request") = V("guided-turn-blocked");
    run.refuses("P", blocked_turn, "blocked_exit");
    check(run.world->snapshot().state == before_blocked,
          "A blocked exit retains the same input and partial work.");
    auto clear = request("P", "guided-clear-exit", "reclaim_component");
    clear.emplace("target", placed_obstacle.at("entity"));
    clear.emplace("generation", placed_obstacle.at("generation"));
    run.accept("P", clear);
    for (int index = 0; index < 3; ++index) {
        turn.at("request") = V("guided-turn-" + std::to_string(index));
        run.accept("P", turn);
    }
    const auto finished = run.world->snapshot();
    check(finished.state.material.dropped_material.at(exit).products == 1 &&
          finished.state.material.dropped_material.at(center).offcuts == 1 &&
          w::validate(source.profile, finished),
          "A frame-free press makes one plate and one retained offcut from finite copper.");
    codec_restore(source.profile, finished,
                  "A frame-free finished press and its separate offcut survive checkpoint reload.");
    if (center[1] == 0) {
        const auto recover = [&](int index, g::Point at, I products, I offcuts) {
            auto pickup = request("P", "guided-recover-" + std::to_string(index) + "-" +
                std::to_string(products), "pickup_material");
            pickup.emplace("center", V(point(at[0], at[1], at[2])));
            pickup.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(products)},
                {"work_lots", V(V::Array{})}, {"offcuts", V(offcuts)}, {"sheets", V(I{0})}}));
            run.accept("P", pickup);
        };
        for (int index = 0; index < 4; ++index) {
            if (index > 0) {
                run.p = {0, 1, 1.65};
                auto harvest = request("P", "guided-recycle-ore-" + std::to_string(index),
                    "harvest_source");
                harvest.emplace("target", V("ore"));
                run.accept("P", harvest);
                run.p = {2, 1, 0};
                auto again = feed;
                again.at("request") = V("guided-recycle-feed-" + std::to_string(index));
                run.accept("P", again);
                for (int turn_index = 0; turn_index < 3; ++turn_index) {
                    turn.at("request") = V("guided-recycle-turn-" + std::to_string(index) +
                        "-" + std::to_string(turn_index));
                    run.accept("P", turn);
                }
            }
            recover(index, center, 0, 1);
            recover(index, exit, 1, 0);
        }
        const auto four = run.world->snapshot();
        check(four.state.material.cargo.at("P").products == 4 &&
              four.state.material.cargo.at("P").offcuts == 4 &&
              w::validate(source.profile, four),
              "Four real strokes leave four plates and four separately recovered offcuts.");
        auto compact = request("P", "guided-compact-offcuts", "compact_offcuts");
        compact.emplace("target", V(anvil));
        compact.emplace("generation", V(anvil_generation));
        compact.emplace("entry", V(point(center[0] + direction[0], center[1],
                                         center[2] + direction[2])));
        compact.emplace("drive", V(shaft));
        auto wrong = compact;
        wrong.at("request") = V("guided-compact-wrong-drive");
        wrong.at("drive") = V(anvil);
        run.refuses("P", wrong, "wrong_drive_shaft");
        check(run.world->snapshot().state == four.state,
              "A wrong compacting drive leaves every copper holder unchanged.");
        run.accept("P", compact);
        const auto compacted = run.world->snapshot();
        check(compacted.state.material.cargo.at("P").offcuts == 0 &&
              compacted.state.material.cargo.at("P").products == 4 &&
              compacted.state.material.dropped_material.at(center).raw_units == 1 &&
              w::validate(source.profile, compacted),
              "A held crank compacts four recovered offcuts into one full-mass work-face blank.");
        check(run.send("P", compact).completed() &&
              run.world->snapshot().state == compacted.state,
              "An exact compacting retry does not create another blank or debit copper twice.");
        auto forged = compacted;
        forged.state.material.dropped_material.erase(center);
        ++forged.state.material.cargo.at("Q").raw_units;
        check(!w::World::restore("press-feed", source.profile, forged),
              "A checkpoint cannot move the compacted blank to Q without a pickup receipt.");
        codec_restore(source.profile, compacted,
                      "A fresh World retains the compacted blank at its work point.");
        auto q_pickup = request("Q", "guided-q-pickup-recycled-blank", "pickup_material");
        q_pickup.emplace("center", V(point(center[0], center[1], center[2])));
        q_pickup.emplace("expected", V(O{{"raw", V(I{1})}, {"products", V(I{0})},
            {"work_lots", V(V::Array{})}, {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
        run.accept("Q", q_pickup);
        check(run.world->snapshot().state.material.cargo.at("Q").raw_units == 1 &&
              run.world->snapshot().state.material.cargo.at("P").products == 4 &&
              w::World::restore("press-feed", source.profile, run.world->snapshot()) != nullptr,
              "Q physically picks up the exact recycled blank without taking P's plates.");
    }
}

void actor_feed_is_physical_custody() {
    auto source = site();
    source.profile.finite_parts[{s::Role::waterwheel, 0, 0}] = 2;
    source.profile.finite_parts[{s::Role::shaft, 0, 2}] = 3;
    source.profile.finite_parts[{s::Role::belt, 0, 0}] = 1;
    source.state.topology.parts.push_back(
        {{"output-wheel", g::Kind::hub, {0, 0, -8}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel});
    for (const auto& [id, center] : {std::pair{"output-drive", g::Point{0, 0, -4}},
                                     std::pair{"output-west", g::Point{0, 0, 0}},
                                     std::pair{"output-mouth", g::Point{4, 0, 0}}})
        source.state.topology.parts.push_back({{id, g::Kind::shaft, center, g::Axis::z, 0, 2},
            1, s::Role::shaft});
    source.state.topology.belt_spans.push_back({{"press-output-belt", "output-mouth", "output-west"}, 1});
    source.state.topology.sources.push_back({"output-wheel", source.profile.waterwheel_rate});
    source.state.material.belt_lanes.emplace("press-output-belt", m::BeltLane{{std::nullopt, std::nullopt}, 0});
    for (const auto& part : source.state.topology.parts)
        source.state.issued_entities.emplace(part.geometry.id, part.generation);
    source.state.issued_entities.emplace("press-output-belt", 1);
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
    std::string frame, shaft, cog;
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
        if (std::string(part.name) == "wooden_cog") cog = std::get<std::string>(made.at("entity").storage());
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

    run.p = {1.65, 1, 6.6};
    auto take = request("P", "take-press-crank", "take_hand_crank");
    take.emplace("target", V("pod-hand-crank"));
    take.emplace("generation", V(I{1}));
    run.accept("P", take);
    run.p = {2, 1, 0};
    auto turn = request("P", "turn-press-start", "turn_press_crank");
    turn.emplace("target", V(frame));
    turn.emplace("generation", V(frame_generation));
    turn.emplace("drive", V(shaft));
    turn.emplace("exit", V(point(7, 1, 0)));
    // The same admitted construction history must remain valid when the
    // trusted arrival recipe assigns four mass units to a stock chunk.
    auto copper_site = source;
    copper_site.profile.material.raw_mass = 4;
    copper_site.profile.material.plate_mass = 3;
    copper_site.profile.material.sheet_mass = 12;
    Runner copper(copper_site);
    copper.p = run.p;
    copper.world = w::World::restore("press-feed", copper_site.profile, run.world->snapshot());
    check(copper.world != nullptr, "The built hand press restores under the copper mass profile.");
    if (copper.world) {
        for (int stroke = 0; stroke < 3; ++stroke) {
            auto copper_turn = turn;
            copper_turn.at("request") = V("copper-turn-" + std::to_string(stroke));
            copper.accept("P", copper_turn);
        }
        const auto pressed = copper.world->snapshot();
        check(pressed.state.material.dropped_material.at({7, 1, 0}).products == 1 &&
              pressed.state.material.dropped_material.at({8, 1, 0}).offcuts == 1 &&
              w::validate(copper_site.profile, pressed),
              "A real World press keeps its plate and recoverable offcut in separate custody.");
        auto relocated_offcut = pressed;
        const auto remnant = relocated_offcut.state.material.dropped_material.at({8, 1, 0});
        relocated_offcut.state.material.dropped_material.erase({8, 1, 0});
        relocated_offcut.state.material.dropped_material.emplace(g::Point{8, 1, 1}, remnant);
        check(!w::World::restore("press-feed", copper_site.profile, relocated_offcut),
              "A checkpoint cannot move the offcut away from its press without an accepted pickup.");
        const auto copper_save = w::encode_checkpoint(copper_site.profile, pressed);
        check(std::holds_alternative<V>(copper_save),
              "The World checkpoint accepts the mass-conserving pressed state.");
        if (const auto* bytes = std::get_if<V>(&copper_save)) {
            const auto copper_load = w::decode_checkpoint(copper_site.profile, "press-feed", *bytes);
            check(std::holds_alternative<w::Snapshot>(copper_load),
                  "The typed World checkpoint decodes the distinct plate and offcut.");
            if (const auto* restored = std::get_if<w::Snapshot>(&copper_load)) {
                Runner resumed(copper_site);
                resumed.world = w::World::restore("press-feed", copper_site.profile, *restored);
                resumed.p = run.p;
                check(resumed.world != nullptr, "Two actors resume one authoritative copper worksite.");
                if (resumed.world) {
                    auto offcut_pickup = request("Q", "q-pickup-copper-offcut", "pickup_material");
                    offcut_pickup.emplace("center", V(point(8, 1, 0)));
                    offcut_pickup.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
                        {"work_lots", V(V::Array{})}, {"offcuts", V(I{1})}, {"sheets", V(I{0})}}));
                    resumed.accept("Q", offcut_pickup);
                    check(resumed.world->snapshot().state.material.cargo.at("Q").offcuts == 1 &&
                          w::validate(copper_site.profile, resumed.world->snapshot()),
                          "Q retrieves the real offcut after restore without changing P's plate.");
                    const auto after_q = resumed.world->snapshot();
                    const auto q_retry = resumed.send("Q", offcut_pickup);
                    check(q_retry.completed() && q_retry.result &&
                          std::get<bool>(q_retry.result->at("duplicate").storage()) &&
                          resumed.world->snapshot().state == after_q.state,
                          "Q's exact pickup retry cannot duplicate the offcut.");
                    auto plate_pickup = request("P", "p-pickup-copper-plate", "pickup_material");
                    plate_pickup.emplace("center", V(point(7, 1, 0)));
                    plate_pickup.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{1})},
                        {"work_lots", V(V::Array{})}, {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
                    resumed.accept("P", plate_pickup);
                    const auto both_carried = resumed.world->snapshot();
                    check(both_carried.state.material.cargo.at("P").products == 1 &&
                          both_carried.state.material.cargo.at("Q").offcuts == 1 &&
                          w::validate(copper_site.profile, both_carried) &&
                          std::holds_alternative<V>(w::encode_checkpoint(copper_site.profile, both_carried)),
                          "P and Q retain separate physical forms through one saved World.");
                }
            }
        }
    }
    auto wrong_drive = turn;
    wrong_drive.at("request") = V("wrong-press-drive");
    wrong_drive.at("drive") = V(frame);
    run.refuses("P", wrong_drive, "wrong_drive_shaft");
    auto other_turn = turn;
    other_turn.at("client") = V("Q-client");
    other_turn.at("actor") = V("Q");
    other_turn.at("request") = V("q-turn-press");
    run.refuses("Q", other_turn, "not_crank_holder");
    auto output_obstruction = obstruction;
    output_obstruction.at("request") = V("block-press-output");
    output_obstruction.at("center") = V(point(7, 1, 0));
    const auto blocked_output = run.accept("P", output_obstruction);
    auto blocked_turn = turn;
    blocked_turn.at("request") = V("turn-blocked-output");
    run.refuses("P", blocked_turn, "blocked_exit");
    auto clear_output = reclaim_obstacle;
    clear_output.at("request") = V("clear-press-output");
    clear_output.at("target") = blocked_output.at("entity");
    clear_output.at("generation") = blocked_output.at("generation");
    run.accept("P", clear_output);
    run.p = {10, 1, 10};
    auto remote_turn = turn;
    remote_turn.at("request") = V("remote-press-turn");
    run.refuses("P", remote_turn, "out_of_reach");
    run.p = {2, 1, 0};
    const auto started = run.accept("P", turn);
    const auto first_work = run.world->snapshot();
    check(std::get<I>(started.at("formed_products").storage()) == 0 &&
          first_work.state.material.dropped_material.at({8, 1, 0}).work_lots.front().remaining_ticks == 2 &&
          std::holds_alternative<w::Snapshot>(w::decode_checkpoint(source.profile, "press-feed",
              std::get<V>(w::encode_checkpoint(source.profile, first_work)))),
          "The first crank allocates one persistent WorkLot without making a product.");
    auto false_output = first_work;
    for (auto& record : false_output.history.records)
        if (std::get<std::string>(record.intent.at("request").storage()) == "turn-press-start")
            record.result.at("formed_products") = V(I{1});
    check(!w::World::restore("press-feed", source.profile, false_output),
          "A saved crank receipt cannot report output absent from the physical exit.");
    const auto overloaded = w::drive_power(source.profile, first_work.state);
    check(overloaded.mechanical.accepted() &&
          overloaded.mechanical.motion.at(frame).state == g::MotionState::stalled &&
          overloaded.load.at(shaft).overloaded && overloaded.load.at(shaft).capacity == 8 &&
          overloaded.load.at(shaft).impact == 16 &&
          !overloaded.load.at(shaft).limiting_part.empty(),
          "The sourced press exceeds its actual wooden drive-part rating at double speed.");
    Runner unrelated_belt(source);
    unrelated_belt.world = w::World::restore("press-feed", source.profile, first_work);
    unrelated_belt.p = {2, 1, 0};
    auto load_unrelated = request("P", "load-unrelated-belt-work", "load_belt_slot");
    load_unrelated.emplace("target", V("press-output-belt"));
    load_unrelated.emplace("generation", V(I{1}));
    load_unrelated.emplace("slot", V(I{0}));
    load_unrelated.emplace("item", V("raw"));
    load_unrelated.emplace("work_id", V(I{0}));
    unrelated_belt.accept("P", load_unrelated);
    const auto before_unrelated_tick = unrelated_belt.world->snapshot();
    const auto belt_tick = unrelated_belt.world->tick();
    check(belt_tick.error == w::TransactionError::none && belt_tick.changed &&
          unrelated_belt.world->snapshot().state.material.dropped_material.at({8, 1, 0})
              .work_lots.front().remaining_ticks == 2 &&
          unrelated_belt.world->snapshot().state.material.belt_lanes !=
              before_unrelated_tick.state.material.belt_lanes,
          "A belt can advance the World revision while the overloaded press does no work.");
    auto turn_after_belt_tick = turn;
    turn_after_belt_tick.at("request") = V("turn-after-unrelated-belt-tick");
    unrelated_belt.accept("P", turn_after_belt_tick);
    check(unrelated_belt.world->snapshot().state.material.dropped_material.at({8, 1, 0})
              .work_lots.front().remaining_ticks == 1 &&
          w::World::restore("press-feed", source.profile, unrelated_belt.world->snapshot()) != nullptr,
          "The next real manual turn advances one tick despite unrelated belt movement.");
    auto later_stop = request("P", "stop-after-unrelated-belt-tick", "set_drive");
    later_stop.emplace("target", V("press-wheel"));
    later_stop.emplace("generation", V(I{1}));
    later_stop.emplace("enabled", V(false));
    unrelated_belt.accept("P", later_stop);
    auto later_resume = later_stop;
    later_resume.at("request") = V("resume-after-unrelated-belt-tick");
    later_resume.at("enabled") = V(true);
    unrelated_belt.accept("P", later_resume);
    const auto forge_later_press_tick = [&](w::Snapshot forged) {
        auto& lot = forged.state.material.dropped_material.at({8, 1, 0}).work_lots.front();
        const auto id = lot.id;
        lot.remaining_ticks = 0;
        for (auto& record : forged.history.records)
            if (std::get<std::string>(record.intent.at("request").storage()) ==
                    "turn-after-unrelated-belt-tick") {
                auto prior = std::get<V::Array>(record.result.at("prior_work_lots").storage());
                auto prior_lot = std::get<O>(prior.front().storage());
                prior_lot.at("remaining_ticks") = V(I{1});
                record.result.at("prior_work_lots") = V(V::Array{V(prior_lot)});
                auto lots = std::get<V::Array>(record.result.at("work_lots").storage());
                auto result_lot = std::get<O>(lots.front().storage());
                result_lot.at("remaining_ticks") = V(I{0});
                record.result.at("work_lots") = V(V::Array{V(result_lot)});
                record.result.at("prior_auto_remaining_ticks") = V(I{1});
            }
        auto& witness = forged.state.press_progress.at(id);
        witness.automatic_remaining_ticks = 1;
        witness.automatic_transitions.push_back({before_unrelated_tick.revision + 1,
            {8, 1, 0}, 2, 1});
        return forged;
    };
    const auto after_toggle = unrelated_belt.world->snapshot();
    check(!w::World::restore("press-feed", source.profile,
              forge_later_press_tick(after_toggle)),
          "Wheel toggles alone cannot lend an unrelated stalled tick to a press witness.");
    auto later_layout = output_obstruction;
    later_layout.at("request") = V("obstruct-after-unrelated-belt-tick");
    unrelated_belt.accept("P", later_layout);
    check(w::World::restore("press-feed", source.profile, unrelated_belt.world->snapshot()) != nullptr,
          "The genuine later component placement remains restorable.");
    check(!w::World::restore("press-feed", source.profile,
              forge_later_press_tick(unrelated_belt.world->snapshot())),
          "A later component placement cannot hide a forged stalled press tick.");
    Runner topology_after_tick(source);
    topology_after_tick.world = w::World::restore("press-feed", source.profile, after_toggle);
    topology_after_tick.p = {2, 1, 0};
    auto remove_wheel_after_tick = request("P", "remove-wheel-after-unrelated-belt-tick", "remove");
    remove_wheel_after_tick.emplace("target", V("press-wheel"));
    remove_wheel_after_tick.emplace("generation", V(I{1}));
    topology_after_tick.accept("P", remove_wheel_after_tick);
    const auto removed_wheel = topology_after_tick.world->snapshot();
    check(codec_restore(source.profile, removed_wheel,
              "The genuine later wheel removal survives the encoded checkpoint.") != nullptr,
          "The genuine later topology mutation remains restorable.");
    auto missing_removed_shape = removed_wheel;
    missing_removed_shape.history.records.back().result.erase("removed_part");
    check(!w::World::restore("press-feed", source.profile, missing_removed_shape),
          "A later removal cannot erase the geometry needed to verify an earlier tick.");
    auto displaced_removed_shape = removed_wheel;
    auto removed_shape = std::get<O>(displaced_removed_shape.history.records.back().result.at("removed_part").storage());
    removed_shape.at("center") = V(point(8, 4, 0));
    displaced_removed_shape.history.records.back().result.at("removed_part") = V(removed_shape);
    check(!w::World::restore("press-feed", source.profile, displaced_removed_shape),
          "A saved removed-part shape cannot move away from its accepted reach target.");
    check(!w::World::restore("press-feed", source.profile,
              forge_later_press_tick(removed_wheel)),
          "A later wheel removal cannot hide a forged stalled press tick.");
    check(run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state == first_work.state,
          "An overloaded native tick leaves the partial WorkLot and all placed parts intact.");
    const auto stalled_save = w::encode_checkpoint(source.profile, run.world->snapshot());
    check(std::holds_alternative<V>(stalled_save), "The overloaded press checkpoint encodes.");
    const auto stalled_decoded = w::decode_checkpoint(source.profile, "press-feed", std::get<V>(stalled_save));
    check(std::holds_alternative<w::Snapshot>(stalled_decoded), "The overloaded press checkpoint decodes.");
    auto stalled_restored = w::World::restore("press-feed", source.profile, std::get<w::Snapshot>(stalled_decoded));
    check(stalled_restored && stalled_restored->snapshot().state == first_work.state &&
          w::drive_power(source.profile, stalled_restored->snapshot().state).load.at(shaft).overloaded &&
          stalled_restored->tick().error == w::TransactionError::none &&
          stalled_restored->snapshot().state == first_work.state,
          "A fresh World recomputes the same non-destructive stall after checkpoint restore.");
    const auto turn_retry = run.send("P", turn);
    check(turn_retry.completed() && turn_retry.result &&
          std::get<bool>(turn_retry.result->at("duplicate").storage()) &&
          run.world->snapshot().state == first_work.state,
          "Retrying a crank request cannot advance its WorkLot twice.");
    auto second_turn = turn;
    second_turn.at("request") = V("turn-press-progress");
    run.accept("P", second_turn);
    check(run.world->snapshot().state.material.dropped_material.at({8, 1, 0}).work_lots.front().remaining_ticks == 1,
          "The second turn advances the same partial work by one shared material tick.");
    check(bool(w::World::restore("press-feed", source.profile, run.world->snapshot())),
          "A genuine stalled-tick manual-progress checkpoint restores before tamper checks.");
    auto forged_progress_witness = run.world->snapshot();
    const auto active_work_id = forged_progress_witness.state.material.dropped_material.at({8, 1, 0})
        .work_lots.front().id;
    forged_progress_witness.state.press_progress.at(active_work_id).automatic_remaining_ticks = 1;
    check(!w::World::restore("press-feed", source.profile, forged_progress_witness),
          "A saved automatic-progress witness must reconcile with the live press work item.");
    auto forged_manual_progress = run.world->snapshot();
    auto& forged_lot = forged_manual_progress.state.material.dropped_material.at({8, 1, 0}).work_lots.front();
    forged_lot.remaining_ticks = 0;
    for (auto& record : forged_manual_progress.history.records)
        if (std::get<std::string>(record.intent.at("request").storage()) == "turn-press-progress") {
            auto lots = std::get<V::Array>(record.result.at("work_lots").storage());
            auto lot = std::get<O>(lots.front().storage());
            lot.at("remaining_ticks") = V(I{0});
            record.result.at("work_lots") = V(V::Array{V(lot)});
        }
    check(!w::World::restore("press-feed", source.profile, forged_manual_progress),
          "One manual crank cannot claim more than one tick of work in a saved checkpoint.");
    auto forged_tick_progress = forged_manual_progress;
    for (auto& record : forged_tick_progress.history.records)
        if (std::get<std::string>(record.intent.at("request").storage()) == "turn-press-progress") {
            auto prior = std::get<V::Array>(record.result.at("prior_work_lots").storage());
            auto lot = std::get<O>(prior.front().storage());
            lot.at("remaining_ticks") = V(I{1});
            record.result.at("prior_work_lots") = V(V::Array{V(lot)});
        }
    check(!w::World::restore("press-feed", source.profile, forged_tick_progress),
          "Stalled World ticks cannot be presented as automatic press work before a manual turn.");
    auto forged_unrelated_tick = forged_tick_progress;
    ++forged_unrelated_tick.revision;
    for (auto& record : forged_unrelated_tick.history.records)
        if (std::get<std::string>(record.intent.at("request").storage()) == "turn-press-progress")
            record.result.at("revision") = V(std::get<I>(record.result.at("revision").storage()) + 1);
    check(!w::World::restore("press-feed", source.profile, forged_unrelated_tick),
          "An unrelated World revision cannot justify progress in a stalled press.");
    auto forged_auto_receipt = forged_unrelated_tick;
    for (auto& record : forged_auto_receipt.history.records)
        if (std::get<std::string>(record.intent.at("request").storage()) == "turn-press-progress")
            record.result.at("prior_auto_remaining_ticks") = V(I{1});
    check(!w::World::restore("press-feed", source.profile, forged_auto_receipt),
          "A claimed automatic tick must match the saved witness for that work ID.");
    auto forged_counter_and_receipt = forged_auto_receipt;
    forged_counter_and_receipt.state.press_progress.at(active_work_id).automatic_remaining_ticks = 1;
    check(!w::World::restore("press-feed", source.profile, forged_counter_and_receipt),
          "A forged automatic counter and matching receipt cannot borrow an unrelated World revision.");
    auto forged_transition = forged_counter_and_receipt;
    for (const auto& record : forged_transition.history.records)
        if (std::get<std::string>(record.intent.at("request").storage()) == "turn-press-progress")
            forged_transition.state.press_progress.at(active_work_id).automatic_transitions.push_back({
                std::get<I>(record.result.at("revision").storage()) - 1, {8, 1, 0}, 2, 1});
    check(!w::World::restore("press-feed", source.profile, forged_transition),
          "A claimed press transition during a stalled drive cannot justify forged automatic work.");
    auto forged_wrong_work = forged_transition;
    forged_wrong_work.state.press_progress.at(active_work_id).automatic_transitions.front().work = {0, 1, 0};
    check(!w::World::restore("press-feed", source.profile, forged_wrong_work),
          "A progress event for another press work point cannot justify this WorkLot.");
    auto third_turn = turn;
    third_turn.at("request") = V("turn-press-finish");
    const auto finished = run.accept("P", third_turn);
    check(std::get<I>(finished.at("formed_products").storage()) == 1 &&
          !run.world->snapshot().state.material.dropped_material.contains({8, 1, 0}) &&
          run.world->snapshot().state.material.dropped_material.at({7, 1, 0}).products == 1,
          "The finished product leaves the work point at the selected physical exit.");
    const auto formed = run.world->snapshot();
    check(std::holds_alternative<w::Snapshot>(w::decode_checkpoint(source.profile, "press-feed",
              std::get<V>(w::encode_checkpoint(source.profile, formed)))),
          "A formed product and the now empty work point survive strict checkpoint restore.");
    Runner manual_blocked(source);
    manual_blocked.world = w::World::restore("press-feed", source.profile, formed);
    manual_blocked.p = {2, 1, 0};
    auto blocked_feed = feed;
    blocked_feed.at("request") = V("feed-behind-manual-output");
    manual_blocked.accept("P", blocked_feed);
    for (int index = 0; index < 3; ++index) {
        auto blocked_turn = turn;
        blocked_turn.at("request") = V("turn-against-manual-output-" + std::to_string(index));
        manual_blocked.accept("P", blocked_turn);
    }
    const auto ready_behind_output = manual_blocked.world->snapshot();
    const auto ready_checkpoint = w::encode_checkpoint(source.profile, ready_behind_output);
    check(ready_behind_output.state.material.dropped_material.at({8, 1, 0})
              .work_lots.front().remaining_ticks == 0 &&
          ready_behind_output.state.material.dropped_material.at({7, 1, 0}).products == 1 &&
          std::holds_alternative<V>(ready_checkpoint) &&
          std::holds_alternative<w::Snapshot>(w::decode_checkpoint(source.profile, "press-feed",
              std::get<V>(ready_checkpoint))),
          "A manual ready lot remains at work behind a full exit and restores without losing progress.");
    auto clear_manual_output = request("P", "clear-manual-output", "pickup_material");
    clear_manual_output.emplace("center", V(point(7, 1, 0)));
    clear_manual_output.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{1})},
        {"work_lots", V(V::Array{})}}));
    manual_blocked.accept("P", clear_manual_output);
    auto release_ready = turn;
    release_ready.at("request") = V("release-ready-manual-output");
    const auto released = manual_blocked.accept("P", release_ready);
    check(std::get<I>(released.at("formed_products").storage()) == 1 &&
          !manual_blocked.world->snapshot().state.material.dropped_material.contains({8, 1, 0}) &&
          w::World::restore("press-feed", source.profile, manual_blocked.world->snapshot()) != nullptr,
          "Clearing the exit lets the exact ready manual lot form one product and restore.");
    auto exported = w::World::restore("press-feed", source.profile, formed);
    check(exported && exported->tick().error == w::TransactionError::none,
          "A powered outward belt accepts the finished modular press plate on a trusted tick.");
    const auto on_route = exported->snapshot();
    check(!on_route.state.material.dropped_material.contains({7, 1, 0}) &&
          on_route.state.press_output_at_exit.empty() &&
          on_route.state.press_output_exported.at({7, 1, 0}).size() == 1 &&
          w::validate(source.profile, on_route),
          "The plate leaves the quarter-grid exit once with its work identity and conserved material.");
    const auto saved_route = w::encode_checkpoint(source.profile, on_route);
    check(std::holds_alternative<V>(saved_route) &&
          std::holds_alternative<w::Snapshot>(w::decode_checkpoint(source.profile, "press-feed",
              std::get<V>(saved_route))),
          "A fresh checkpoint admits the identified product after belt export.");
    auto reverse_source = source;
    reverse_source.profile.waterwheel_rate = {-2, 1};
    auto reverse_state = formed;
    for (auto& power : reverse_state.state.topology.sources)
        power.rate = reverse_source.profile.waterwheel_rate;
    auto reverse = w::World::restore("press-feed", reverse_source.profile, reverse_state);
    check(reverse && reverse->tick().error == w::TransactionError::none &&
          reverse->snapshot().state.material.dropped_material.at({7, 1, 0}).products == 1 &&
          reverse->snapshot().state.press_output_at_exit.contains({7, 1, 0}),
          "A belt running toward the press cannot pull the plate from its outlet.");
    auto swapped = formed;
    auto& reversed_span = swapped.state.topology.belt_spans.front().geometry;
    std::swap(reversed_span.first_shaft, reversed_span.last_shaft);
    auto opposite_order = w::World::restore("press-feed", source.profile, swapped);
    check(opposite_order && opposite_order->tick().error == w::TransactionError::none &&
          !opposite_order->snapshot().state.material.dropped_material.contains({7, 1, 0}) &&
          opposite_order->snapshot().state.press_output_exported.at({7, 1, 0}).size() == 1,
          "The same physical outward route works with the belt endpoint order reversed.");
    Runner occupied(source);
    occupied.world = w::World::restore("press-feed", source.profile, formed);
    occupied.p = {2, 1, 0};
    auto load = request("P", "block-press-belt-inlet", "load_belt_slot");
    load.emplace("target", V("press-output-belt"));
    load.emplace("generation", V(I{1}));
    load.emplace("slot", V(I{0}));
    load.emplace("item", V("raw"));
    load.emplace("work_id", V(I{0}));
    occupied.accept("P", load);
    check(occupied.world->tick().error == w::TransactionError::none &&
          occupied.world->snapshot().state.material.dropped_material.at({7, 1, 0}).products == 1 &&
          occupied.world->snapshot().state.press_output_at_exit.contains({7, 1, 0}),
          "An occupied inlet retains the real press output even when the belt later clears.");
    check(occupied.world->tick().error == w::TransactionError::none &&
          !occupied.world->snapshot().state.material.dropped_material.contains({7, 1, 0}) &&
          occupied.world->snapshot().state.press_output_exported.at({7, 1, 0}).size() == 1,
          "The same plate exits after the inlet clears without another press cycle.");
    Runner obstructed(source);
    obstructed.world = w::World::restore("press-feed", source.profile, formed);
    obstructed.p = {2, 1, 0};
    auto obstruction_in_chute = request("P", "obstruct-press-chute", "place_component");
    obstruction_in_chute.emplace("component", V("tool_mount"));
    obstruction_in_chute.emplace("center", V(point(6, 1, 0)));
    const auto chute_obstacle = obstructed.accept("P", obstruction_in_chute);
    check(obstructed.world->tick().error == w::TransactionError::none &&
          obstructed.world->snapshot().state.material.dropped_material.at({7, 1, 0}).products == 1,
          "A real placed part in the short chute blocks automatic output without consuming it.");
    auto clear_chute = request("P", "clear-press-chute", "reclaim_component");
    clear_chute.emplace("target", chute_obstacle.at("entity"));
    clear_chute.emplace("generation", chute_obstacle.at("generation"));
    obstructed.accept("P", clear_chute);
    check(obstructed.world->tick().error == w::TransactionError::none &&
          !obstructed.world->snapshot().state.material.dropped_material.contains({7, 1, 0}),
          "Removing the obstacle releases the retained plate to the same belt.");
    Runner repeated(source);
    repeated.world = w::World::restore("press-feed", source.profile, on_route);
    repeated.p = {2, 1, 0};
    auto repeat_feed = feed;
    repeat_feed.at("request") = V("feed-after-export");
    repeated.accept("P", repeat_feed);
    for (int index = 0; index < 3; ++index) {
        auto next_turn = turn;
        next_turn.at("request") = V("turn-after-export-" + std::to_string(index));
        repeated.accept("P", next_turn);
    }
    check(repeated.world->tick().error == w::TransactionError::none &&
          repeated.world->snapshot().state.press_output_exported.at({7, 1, 0}).size() == 2 &&
          w::World::restore("press-feed", source.profile, repeated.world->snapshot()) != nullptr,
          "Two separately formed plates leave the same port once each and restore with distinct work identities.");
    auto forged_product = formed;
    const auto produced = forged_product.state.material.dropped_material.at({7, 1, 0});
    forged_product.state.material.dropped_material.erase({7, 1, 0});
    forged_product.state.material.dropped_material.emplace(g::Point{7, 1, 1}, produced);
    check(!w::World::restore("press-feed", source.profile, forged_product),
          "A checkpoint cannot relocate the formed product without an accepted pickup.");
    run.p = {1.65, 1, 6.6};
    auto return_crank = request("P", "return-crank-between-press-and-pickup", "return_hand_crank");
    return_crank.emplace("target", V("pod-hand-crank"));
    return_crank.emplace("generation", V(I{1}));
    run.accept("P", return_crank);
    run.p = {2, 1, 0};
    auto pickup_product = request("P", "pickup-formed-product", "pickup_material");
    pickup_product.emplace("center", V(point(7, 1, 0)));
    pickup_product.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{1})},
        {"work_lots", V(V::Array{})}}));
    run.accept("P", pickup_product);
    check(run.world->snapshot().state.material.cargo.at("P").products == 1,
          "A physical actor retrieves the single formed product.");
    auto forged_export = run.world->snapshot();
    check(forged_export.state.press_output_at_exit.empty() &&
          forged_export.state.press_output_exported.empty(),
          "The actor pickup fixture has no press output export witness.");
    forged_export.state.press_output_exported[{7, 1, 0}].insert(
        formed.state.press_output_at_exit.at({7, 1, 0}));
    check(!w::World::restore("press-feed", source.profile, forged_export),
          "A checkpoint cannot claim that an actor-picked plate was exported to a belt.");
    auto forged_finish = run.world->snapshot();
    V::Array prior_work;
    for (const auto& record : forged_finish.history.records)
        if (std::get<std::string>(record.intent.at("request").storage()) == "turn-press-progress")
            prior_work = std::get<V::Array>(record.result.at("work_lots").storage());
    check(prior_work.size() == 1, "The tamper control starts from the real earlier partial lot.");
    auto fake_ready = std::get<O>(prior_work.front().storage());
    fake_ready.at("remaining_ticks") = V(I{0});
    for (auto& record : forged_finish.history.records)
        if (std::get<std::string>(record.intent.at("request").storage()) == "turn-press-finish") {
            record.result.at("work_lots") = V(V::Array{V(fake_ready)});
            record.result.at("formed_products") = V(I{0});
        }
    check(!w::World::restore("press-feed", source.profile, forged_finish),
          "An unrelated accepted command cannot impersonate an automatic press tick in a saved pickup.");
    Runner freight(source);
    freight.world = w::World::restore("press-feed", source.profile, run.world->snapshot());
    check(freight.world != nullptr, "The formed plate has a valid native shipment starting state.");
    freight.p = {9.9, 1, 6.6};
    auto repeat_order = request("P", "early-repeat-shipment", "deliver_repeat_plate");
    repeat_order.emplace("target", V("first-freight-beacon"));
    repeat_order.emplace("generation", V(I{1}));
    freight.refuses("P", repeat_order, "first_order_open");
    check(freight.world->snapshot().state.material.cargo.at("P").products == 1,
          "An early follow-up request leaves the physically carried plate untouched.");
    auto first_order = repeat_order;
    first_order.at("request") = V("ship-first-native-plate");
    first_order.at("action") = V("deliver_first_plate");
    check(std::get<I>(freight.accept("P", first_order).at("shipped_products").storage()) == 1 &&
          freight.world->snapshot().state.material.cargo.at("P").products == 0 &&
          w::World::restore("press-feed", source.profile, freight.world->snapshot()) != nullptr,
          "The direct World route ships one real plate and restores its first-order receipt.");
    repeat_order.at("request") = V("empty-native-repeat");
    freight.refuses("P", repeat_order, "no_plate");
    auto retake_crank = take;
    retake_crank.at("request") = V("retake-press-crank");
    run.p = {1.65, 1, 6.6};
    run.accept("P", retake_crank);
    run.p = {2, 1, 0};
    auto second_feed = feed;
    second_feed.at("request") = V("feed-second");
    run.accept("P", second_feed);
    auto fourth_turn = turn;
    fourth_turn.at("request") = V("turn-second-start");
    run.accept("P", fourth_turn);
    const auto partial = run.world->snapshot().state.material.dropped_material.at({8, 1, 0}).work_lots.front();
    auto remove = request("P", "remove-shaft", "reclaim_component");
    remove.emplace("target", V(shaft));
    remove.emplace("generation", V(I{6}));
    run.accept("P", remove);
    check(run.world->snapshot().state.material.dropped_material.at({8, 1, 0}).work_lots ==
          std::vector<m::WorkLot>{partial},
          "Dismantling a drive leaves the exact partial WorkLot under the work head.");
    auto pickup = request("P", "recover-partial-work", "pickup_material");
    pickup.emplace("center", V(point(8, 1, 0)));
    pickup.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
        {"work_lots", V(V::Array{V(O{{"id", V(partial.id)}, {"recipe_input", V(I{1})},
            {"cycle_ticks", V(I{2})}, {"remaining", V(partial.remaining_ticks)},
            {"completed_subticks", V(partial.completed_subticks)},
            {"work_remainder", V(partial.work_remainder)},
            {"work_remainder_denominator", V(partial.work_remainder_denominator)}})})}}));
    run.accept("P", pickup);
    check(run.world->snapshot().state.material.dropped_material.empty() &&
          run.world->snapshot().state.material.cargo.at("P").work_lots == std::vector<m::WorkLot>{partial},
          "Pickup after dismantling returns the same partial work to actor custody.");
    const auto recovered = run.world->snapshot();
    check(w::World::restore("press-feed", source.profile, recovered) != nullptr,
          "A saved harvest, craft, feed, form and pickup history restores with partial work in actor cargo.");
    Runner refeed(source);
    refeed.world = w::World::restore("press-feed", source.profile, recovered);
    refeed.p = {2, 1, 0};
    auto reinsert = request("P", "reinsert-recovered-work", "refeed_press_work");
    reinsert.emplace("target", V(frame));
    reinsert.emplace("generation", V(frame_generation));
    reinsert.emplace("entry", V(point(9, 1, 0)));
    reinsert.emplace("work_id", V(partial.id));
    auto incomplete_refeed = reinsert;
    incomplete_refeed.at("request") = V("reinsert-without-drive");
    refeed.refuses("P", incomplete_refeed, "incomplete_assembly");
    auto replace_shaft = request("P", "replace-recovered-shaft", "place_component");
    replace_shaft.emplace("component", V("wooden_shaft"));
    replace_shaft.emplace("center", V(point(9, 4, 0)));
    const auto replacement_shaft = refeed.accept("P", replace_shaft);
    auto wrong_work = reinsert;
    wrong_work.at("request") = V("reinsert-wrong-work-id");
    wrong_work.at("work_id") = V(partial.id + 1);
    refeed.refuses("P", wrong_work, "unavailable_work");
    refeed.p = {10, 1, 10};
    auto remote_refeed = reinsert;
    remote_refeed.at("request") = V("remote-reinsert-work");
    refeed.refuses("P", remote_refeed, "out_of_reach");
    refeed.p = {2, 1, 0};
    const auto inserted_work = refeed.accept("P", reinsert);
    check(std::get<V::Array>(inserted_work.at("moved_work").storage()).size() == 1 &&
          refeed.world->snapshot().state.material.cargo.at("P").work_lots.empty() &&
          refeed.world->snapshot().state.material.dropped_material.at({8, 1, 0}).work_lots ==
              std::vector<m::WorkLot>{partial},
          "Exact-ID hand refeed restores the recovered WorkLot to the same physical work point.");
    const auto reinserted = refeed.world->snapshot();
    check(w::World::restore("press-feed", source.profile, reinserted) != nullptr &&
          std::get<bool>(refeed.send("P", reinsert).result->at("duplicate").storage()),
          "A fresh restore retains the reinserted partial lot and an exact request retry is idempotent.");
    auto forged_reinsert = reinserted;
    for (auto& record : forged_reinsert.history.records)
        if (std::get<std::string>(record.intent.at("request").storage()) == "reinsert-recovered-work") {
            auto work = std::get<V::Array>(record.result.at("moved_work").storage());
            auto lot = std::get<O>(work.front().storage());
            lot.at("remaining_ticks") = V(I{0});
            work.front() = V(lot);
            record.result.at("moved_work") = V(work);
        }
    check(!w::World::restore("press-feed", source.profile, forged_reinsert),
          "A forged hand-refeed receipt cannot change the recovered WorkLot progress.");
    auto remaining_turn = turn;
    remaining_turn.at("request") = V("advance-reinserted-work");
    remaining_turn.at("drive") = replacement_shaft.at("entity");
    refeed.accept("P", remaining_turn);
    remaining_turn.at("request") = V("finish-reinserted-work");
    const auto reformed = refeed.accept("P", remaining_turn);
    check(std::get<I>(reformed.at("formed_products").storage()) == 1 &&
          refeed.world->snapshot().state.material.dropped_material.at({7, 1, 0}).products == 1 &&
          w::World::restore("press-feed", source.profile, refeed.world->snapshot()) != nullptr,
          "The reinserted lot completes with its retained progress and one formed plate.");
    auto pick_reformed = request("P", "pickup-reinserted-plate", "pickup_material");
    pick_reformed.emplace("center", V(point(7, 1, 0)));
    pick_reformed.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{1})},
        {"work_lots", V(V::Array{})}}));
    refeed.accept("P", pick_reformed);
    check(refeed.world->snapshot().state.material.cargo.at("P").products == 2 &&
          w::World::restore("press-feed", source.profile, refeed.world->snapshot()) != nullptr,
          "The recovered work yields exactly one pickable plate in restored actor custody.");
    run.p = {0, 1, 1.65};
    for (int n = 0; n < 4; ++n) {
        auto ore = request("P", "upgrade-ore-" + std::to_string(n), "harvest_source");
        ore.emplace("target", V("ore"));
        run.accept("P", ore);
    }
    run.p = {1.65, 1, 6.6};
    for (const auto* name : {"softmetal_shaft", "softmetal_cog"}) {
        auto craft = request("P", std::string("craft-upgrade-") + name, "craft_component");
        craft.emplace("target", V("pod-fabrication-hub"));
        craft.emplace("generation", V(I{1}));
        craft.emplace("component", V(name));
        run.accept("P", craft);
    }
    run.p = {2, 1, 0};
    auto remove_cog = request("P", "remove-wooden-cog", "reclaim_component");
    remove_cog.emplace("target", V(cog));
    remove_cog.emplace("generation", V(I{7}));
    run.accept("P", remove_cog);
    for (const auto& [name, center] : {std::pair{"softmetal_shaft", g::Point{9, 4, 0}},
                                      std::pair{"softmetal_cog", g::Point{10, 4, 0}}}) {
        auto place = request("P", std::string("place-upgrade-") + name, "place_component");
        place.emplace("component", V(name));
        place.emplace("center", V(point(center[0], center[1], center[2])));
        run.accept("P", place);
    }
    const auto upgraded = run.world->snapshot();
    const auto powered = w::drive_power(source.profile, upgraded.state);
    check(powered.mechanical.accepted() &&
          powered.mechanical.motion.at(frame).state == g::MotionState::rotating &&
          powered.load.at(frame).impact == 16 && powered.load.at(frame).capacity == 24 &&
          !powered.load.at(frame).overloaded,
          "Replacing both wooden press drive parts with metal runs the same powered press at unchanged load.");
    check(run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state == upgraded.state &&
          run.world->snapshot().state.material.cargo.at("P").work_lots ==
              std::vector<m::WorkLot>{partial},
          "The upgraded empty press does not consume the retained partial WorkLot in actor custody.");
    const auto upgraded_save = w::encode_checkpoint(source.profile, upgraded);
    check(std::holds_alternative<V>(upgraded_save) &&
          std::holds_alternative<w::Snapshot>(w::decode_checkpoint(source.profile, "press-feed",
              std::get<V>(upgraded_save))),
          "The upgraded drive identities and retained work survive the canonical checkpoint.");
}

void two_placed_presses_advance_distinct_powered_work() {
    auto source = site();
    source.profile.build_reach = 100;
    source.profile.material.hand_carry_capacity = 64;
    source.profile.initial_units = source.state.material.initial_units =
        source.state.material.stock.source = 24;
    source.profile.waterwheel_rate = {1, 1};
    source.state.topology.sources = {{"press-wheel", source.profile.waterwheel_rate}};
    Runner run(source);
    for (int index = 0; index < 8; ++index) {
        auto harvest = request("P", "two-press-tree-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("tree"));
        run.accept("P", harvest);
    }
    for (int index = 0; index < 2; ++index) {
        auto harvest = request("P", "two-press-branch-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("tree-branch"));
        run.accept("P", harvest);
    }
    for (int index = 0; index < 21; ++index) {
        auto harvest = request("P", "two-press-ore-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("ore"));
        run.accept("P", harvest);
    }
    struct Part { const char* name; g::Point center; };
    std::vector<std::string> frames, shafts;
    std::vector<I> frame_generations;
    for (int index = 0; index < 2; ++index) {
        const I x = index * 8;
        const Part parts[] = {{"wooden_frame", {x, 0, 0}}, {"anvil", {x, 1, 0}},
            {"ram_face", {x, 2, 0}}, {"sliding_guide", {x, 3, 0}},
            {"tool_mount", {x, 4, 0}}, {"softmetal_shaft", {x + 1, 4, 0}},
            {"softmetal_cog", {x + 2, 4, 0}}};
        for (const auto& part : parts) {
            const auto tag = std::to_string(index) + "-" + part.name;
            auto craft = request("P", "craft-powered-" + tag, "craft_component");
            craft.emplace("target", V("pod-fabrication-hub"));
            craft.emplace("generation", V(I{1}));
            craft.emplace("component", V(part.name));
            run.accept("P", craft);
            auto place = request("P", "place-powered-" + tag, "place_component");
            place.emplace("component", V(part.name));
            place.emplace("center", V(point(part.center[0], part.center[1], part.center[2])));
            const auto placed = run.accept("P", place);
            if (std::string(part.name) == "wooden_frame") {
                frames.push_back(std::get<std::string>(placed.at("entity").storage()));
                frame_generations.push_back(std::get<I>(placed.at("generation").storage()));
            }
            if (std::string(part.name) == "softmetal_shaft")
                shafts.push_back(std::get<std::string>(placed.at("entity").storage()));
        }
    }
    const auto drive = w::drive_power(source.profile, run.world->snapshot().state);
    check(drive.mechanical.accepted() &&
          drive.mechanical.motion.at(shafts[0]).state == g::MotionState::rotating &&
          drive.mechanical.motion.at(shafts[1]).state == g::MotionState::rotating &&
          frames[0] != frames[1] && shafts[0] != shafts[1],
          "Two placed press frames and shafts receive distinct actual rotating identities.");
    auto copper_site = source;
    copper_site.profile.material.raw_mass = 4;
    copper_site.profile.material.plate_mass = 3;
    copper_site.profile.material.sheet_mass = 12;
    Runner copper(copper_site);
    copper.world = w::World::restore("press-feed", copper_site.profile, run.world->snapshot());
    check(copper.world != nullptr, "The complete powered press restores under copper mass custody.");
    if (copper.world) {
        auto feed = request("P", "copper-auto-feed", "feed_press");
        feed.emplace("target", V(frames[0]));
        feed.emplace("generation", V(frame_generations[0]));
        feed.emplace("entry", V(point(1, 1, 0)));
        copper.accept("P", feed);
        for (int tick = 0; tick < 3; ++tick)
            check(copper.world->tick().error == w::TransactionError::none,
                  "A powered copper press advances a real stock lot without losing mass.");
        const auto automatic = copper.world->snapshot();
        check(automatic.state.material.dropped_material.at({0, 1, 0}).offcuts == 1 &&
              automatic.state.material.dropped_material.at({-1, 1, 0}).products == 1 &&
              w::validate(copper_site.profile, automatic) &&
              std::holds_alternative<V>(w::encode_checkpoint(copper_site.profile, automatic)),
              "Automatic copper output preserves its plate and work-face offcut in one saved World.");
        auto relocated = automatic;
        const auto loose_offcut = relocated.state.material.dropped_material.at({0, 1, 0});
        relocated.state.material.dropped_material.erase({0, 1, 0});
        relocated.state.material.dropped_material.emplace(g::Point{0, 1, 1}, loose_offcut);
        check(!w::World::restore("press-feed", copper_site.profile, relocated),
              "An automatic press offcut cannot relocate in a forged checkpoint.");
        Runner product_first(copper_site);
        product_first.world = w::World::restore("press-feed", copper_site.profile, automatic);
        check(product_first.world != nullptr, "The automatic copper product restores before either pickup.");
        if (product_first.world) {
            auto plate_pickup = request("P", "p-pickup-auto-copper-plate", "pickup_material");
            plate_pickup.emplace("center", V(point(-1, 1, 0)));
            plate_pickup.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{1})},
                {"work_lots", V(V::Array{})}, {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
            product_first.accept("P", plate_pickup);
            check(w::validate(copper_site.profile, product_first.world->snapshot()),
                  "Picking the automatic plate first still binds its uncollected offcut to the press.");
        }
        auto offcut_pickup = request("Q", "q-pickup-automatic-copper-offcut", "pickup_material");
        offcut_pickup.emplace("center", V(point(0, 1, 0)));
        offcut_pickup.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
            {"work_lots", V(V::Array{})}, {"offcuts", V(I{1})}, {"sheets", V(I{0})}}));
        copper.accept("Q", offcut_pickup);
        check(copper.world->snapshot().state.material.cargo.at("Q").offcuts == 1 &&
              w::validate(copper_site.profile, copper.world->snapshot()),
              "Q may recover the automatic press offcut while P retains the plate route.");
        if (product_first.world) {
            product_first.accept("Q", offcut_pickup);
            check(product_first.world->snapshot().state.material.cargo.at("P").products == 1 &&
                  product_first.world->snapshot().state.material.cargo.at("Q").offcuts == 1 &&
                  w::validate(copper_site.profile, product_first.world->snapshot()),
                  "Both pickup orders retain separate P and Q custody after automatic forming.");
        }
    }
    auto half_source = source;
    half_source.profile.waterwheel_rate = {1, 2};
    for (auto& power : half_source.state.topology.sources)
        power.rate = half_source.profile.waterwheel_rate;
    auto half_ready = run.world->snapshot();
    for (auto& power : half_ready.state.topology.sources)
        power.rate = half_source.profile.waterwheel_rate;
    Runner fractional(half_source);
    fractional.world = w::World::restore("press-feed", half_source.profile, half_ready);
    check(fractional.world != nullptr,
          "The same assembled press site restores with a half-speed wheel before feeding.");
    auto fractional_feed = request("P", "feed-half-speed-press", "feed_press");
    fractional_feed.emplace("target", V(frames[0]));
    fractional_feed.emplace("generation", V(frame_generations[0]));
    fractional_feed.emplace("entry", V(point(1, 1, 0)));
    fractional.accept("P", fractional_feed);
    check(fractional.world->tick().error == w::TransactionError::none &&
          fractional.world->tick().error == w::TransactionError::none,
          "Two half-speed ticks allocate then fractionally advance a real WorkLot.");
    const auto half_lot = fractional.world->snapshot().state.material.dropped_material.at({0, 1, 0})
        .work_lots.front();
    check(half_lot.remaining_ticks == 2 &&
          half_lot.completed_subticks == m::work_subticks_per_tick / 2 &&
          w::World::restore("press-feed", half_source.profile, fractional.world->snapshot()) != nullptr,
          "The automatic partial WorkLot retains its exact half-tick progress in a checkpoint.");
    auto recover_fractional = request("P", "recover-fractional-work", "pickup_material");
    recover_fractional.emplace("center", V(point(0, 1, 0)));
    recover_fractional.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
        {"work_lots", V(V::Array{V(O{{"id", V(half_lot.id)}, {"recipe_input", V(I{1})},
            {"cycle_ticks", V(I{2})}, {"remaining", V(half_lot.remaining_ticks)},
            {"completed_subticks", V(half_lot.completed_subticks)},
            {"work_remainder", V(half_lot.work_remainder)},
            {"work_remainder_denominator", V(half_lot.work_remainder_denominator)}})})}}));
    fractional.accept("P", recover_fractional);
    auto reinsert_fractional = request("P", "reinsert-fractional-work", "refeed_press_work");
    reinsert_fractional.emplace("target", V(frames[0]));
    reinsert_fractional.emplace("generation", V(frame_generations[0]));
    reinsert_fractional.emplace("entry", V(point(1, 1, 0)));
    reinsert_fractional.emplace("work_id", V(half_lot.id));
    fractional.accept("P", reinsert_fractional);
    const auto half_reinserted = fractional.world->snapshot();
    check(half_reinserted.state.material.cargo.at("P").work_lots.empty() &&
          half_reinserted.state.material.dropped_material.at({0, 1, 0}).work_lots ==
              std::vector<m::WorkLot>{half_lot} &&
          w::World::restore("press-feed", half_source.profile, half_reinserted) != nullptr,
          "Hand refeed preserves the original ID and fractional progress on the powered work point.");
    fractional.world = codec_restore(half_source.profile, half_reinserted,
          "The serialized half-speed hand refeed retains its exact WorkLot and revision.");
    auto forged_half_finish = half_reinserted;
    forged_half_finish.state.material.dropped_material.erase({0, 1, 0});
    forged_half_finish.state.material.dropped_material.emplace(g::Point{-1, 1, 0}, m::Cargo{0, 1, {}});
    forged_half_finish.state.press_output_at_exit[{ -1, 1, 0 }] = half_lot.id;
    forged_half_finish.state.press_progress.erase(half_lot.id);
    check(!w::World::restore("press-feed", half_source.profile, forged_half_finish),
          "A forged instant product cannot skip the remaining fractional power after hand refeed.");
    for (int tick = 0; tick < 3; ++tick) {
        check(fractional.world->tick().error == w::TransactionError::none,
              "The restored half-speed press advances one real powered step.");
        fractional.world = codec_restore(half_source.profile, fractional.world->snapshot(),
              "Each half-speed continuation round trip retains its WorkLot or product exactly.");
        if (tick == 0) {
            auto premature = fractional.world->snapshot();
            premature.state.material.dropped_material.erase({0, 1, 0});
            premature.state.material.dropped_material.emplace(g::Point{-1, 1, 0}, m::Cargo{0, 1, {}});
            premature.state.press_output_at_exit[{ -1, 1, 0 }] = half_lot.id;
            premature.state.press_progress.erase(half_lot.id);
            check(!w::World::restore("press-feed", half_source.profile, premature),
                  "One half-speed continuation tick cannot claim a fully formed reinserted plate.");
            premature.state.press_progress[half_lot.id].automatic_remaining_ticks =
                half_lot.remaining_ticks;
            check(!w::World::restore("press-feed", half_source.profile, premature),
                  "An inflated saved progress counter cannot claim a plate before enough powered ticks.");
        }
    }
    check(fractional.world->snapshot().state.material.dropped_material.at({-1, 1, 0}).products == 1 &&
          !fractional.world->snapshot().state.material.dropped_material.contains({0, 1, 0}),
          "The retained half-tick plus three later half-speed ticks form exactly one plate.");
    const auto finished_half = w::encode_checkpoint(half_source.profile, fractional.world->snapshot());
    check(std::holds_alternative<V>(finished_half), "The genuine half-speed plate encodes.");
    auto premature_save = std::get<V>(finished_half);
    auto root = std::get<O>(premature_save.storage());
    root.at("revision") = V(fractional.world->snapshot().revision - 2);
    premature_save = V(std::move(root));
    const auto premature_decoded = w::decode_checkpoint(half_source.profile, "press-feed", premature_save);
    check(std::holds_alternative<w::CheckpointRefusal>(premature_decoded) &&
          std::get<w::CheckpointRefusal>(premature_decoded).reason == w::CheckpointReason::invalid_world,
          "A serialized plate with only one continuation tick fails World work validation.");
    for (int index = 0; index < 2; ++index) {
        auto feed = request("P", "feed-powered-" + std::to_string(index), "feed_press");
        feed.emplace("target", V(frames[index]));
        feed.emplace("generation", V(frame_generations[index]));
        feed.emplace("entry", V(point(index * 8 + 1, 1, 0)));
        run.accept("P", feed);
    }
    check(run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state.material.dropped_material.at({0, 1, 0}).work_lots.front().id == 1 &&
          run.world->snapshot().state.material.dropped_material.at({8, 1, 0}).work_lots.front().id == 2,
          "One native tick starts two independent WorkLots at their placed press work points.");
    const auto partial = run.world->snapshot();
    const auto encoded = w::encode_checkpoint(source.profile, partial);
    check(std::holds_alternative<V>(encoded) &&
          std::holds_alternative<w::Snapshot>(w::decode_checkpoint(source.profile, "press-feed", std::get<V>(encoded))) &&
          w::World::restore("press-feed", source.profile, partial) != nullptr,
          "Both partial lots and placed drive identities survive checkpoint and restore.");
    auto stop = request("P", "stop-powered-presses", "set_drive");
    stop.emplace("target", V("press-wheel"));
    stop.emplace("generation", V(I{1}));
    stop.emplace("enabled", V(false));
    run.accept("P", stop);
    const auto stopped = run.world->snapshot();
    check(run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state.material == stopped.state.material,
          "Stopping the real wheel pauses both partial lots without loss.");
    auto resume = stop;
    resume.at("request") = V("resume-powered-presses");
    resume.at("enabled") = V(true);
    run.accept("P", resume);
    check(run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state.material.dropped_material.at({0, 1, 0}).work_lots.front().remaining_ticks == 1 &&
          run.world->snapshot().state.material.dropped_material.at({8, 1, 0}).work_lots.front().remaining_ticks == 1,
          "Both retained lots advance one cycle tick when their shafts resume.");
    check(run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state.material.dropped_material.at({-1, 1, 0}) == m::Cargo{0, 1, {}} &&
          run.world->snapshot().state.material.dropped_material.at({7, 1, 0}) == m::Cargo{0, 1, {}} &&
          !run.world->snapshot().state.material.dropped_material.contains({0, 1, 0}) &&
          !run.world->snapshot().state.material.dropped_material.contains({8, 1, 0}),
          "Two plates leave separate drive-opposed exits after distinct finite work cycles.");
    auto feed_again = request("P", "feed-powered-again", "feed_press");
    feed_again.emplace("target", V(frames[0]));
    feed_again.emplace("generation", V(frame_generations[0]));
    feed_again.emplace("entry", V(point(1, 1, 0)));
    run.accept("P", feed_again);
    for (int index = 0; index < 3; ++index)
        check(run.world->tick().error == w::TransactionError::none,
              "A ready WorkLot may advance while its own output is full.");
    const auto blocked = run.world->snapshot();
    check(blocked.state.material.dropped_material.at({0, 1, 0}).work_lots.front().remaining_ticks == 0 &&
          blocked.state.material.dropped_material.at({-1, 1, 0}) == m::Cargo{0, 1, {}} &&
          blocked.state.material.dropped_material.at({7, 1, 0}) == m::Cargo{0, 1, {}} &&
          run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state.material == blocked.state.material,
          "A full first exit retains exactly its ready work while the second product remains separate.");
    auto pickup = request("P", "clear-powered-exit", "pickup_material");
    pickup.emplace("center", V(point(-1, 1, 0)));
    pickup.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{1})},
        {"work_lots", V(V::Array{})}}));
    run.accept("P", pickup);
    check(run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state.material.dropped_material.at({-1, 1, 0}) == m::Cargo{0, 1, {}} &&
          !run.world->snapshot().state.material.dropped_material.contains({0, 1, 0}) &&
          w::World::restore("press-feed", source.profile, run.world->snapshot()) != nullptr,
          "Clearing the blocked exit releases the same ready lot and restores without duplication.");
    auto clear_again = pickup;
    clear_again.at("request") = V("clear-powered-exit-again");
    run.accept("P", clear_again);
    auto feed_manual = feed_again;
    feed_manual.at("request") = V("feed-powered-for-crank");
    run.accept("P", feed_manual);
    check(run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state.material.dropped_material.at({0, 1, 0}).work_lots.front().id == 4,
          "The fourth blank starts a new automatically powered lot.");
    auto take = request("P", "take-crank-with-power", "take_hand_crank");
    take.emplace("target", V("pod-hand-crank"));
    take.emplace("generation", V(I{1}));
    run.accept("P", take);
    auto turn = request("P", "turn-after-powered-start", "turn_press_crank");
    turn.emplace("target", V(frames[0]));
    turn.emplace("generation", V(frame_generations[0]));
    turn.emplace("drive", V(shafts[0]));
    turn.emplace("exit", V(point(-1, 1, 0)));
    Runner powered_then_manual(source);
    powered_then_manual.world = w::World::restore("press-feed", source.profile, run.world->snapshot());
    check(powered_then_manual.world &&
          powered_then_manual.world->tick().error == w::TransactionError::none &&
          powered_then_manual.world->snapshot().state.material.dropped_material.at({0, 1, 0})
              .work_lots.front().remaining_ticks == 1,
          "A native powered tick advances the identified lot before the next manual turn.");
    Runner edited_after_power(source);
    edited_after_power.world = w::World::restore("press-feed", source.profile,
        powered_then_manual.world->snapshot());
    edited_after_power.p = {2, 1, 0};
    auto reclaim_after_power = request("P", "reclaim-press-shaft-after-real-tick", "reclaim_component");
    reclaim_after_power.emplace("target", V(shafts[0]));
    reclaim_after_power.emplace("generation", V(
        edited_after_power.world->snapshot().state.placed_components.at(shafts[0]).generation));
    edited_after_power.accept("P", reclaim_after_power);
    check(w::World::restore("press-feed", source.profile, edited_after_power.world->snapshot()) != nullptr,
          "Real powered progress remains valid after reclaiming its drive component.");
    Runner stopped_after_power(source);
    stopped_after_power.world = w::World::restore("press-feed", source.profile,
        powered_then_manual.world->snapshot());
    stopped_after_power.p = {2, 1, 0};
    auto remove_wheel_after_power = request("P", "remove-wheel-after-real-tick", "remove");
    remove_wheel_after_power.emplace("target", V("press-wheel"));
    remove_wheel_after_power.emplace("generation", V(I{1}));
    stopped_after_power.accept("P", remove_wheel_after_power);
    check(w::World::restore("press-feed", source.profile, stopped_after_power.world->snapshot()) != nullptr,
          "Real powered progress remains valid after removing its wheel.");
    powered_then_manual.p = {2, 1, 0};
    auto stop_after_real_progress = request("P", "stop-after-real-press-tick", "set_drive");
    stop_after_real_progress.emplace("target", V("press-wheel"));
    stop_after_real_progress.emplace("generation", V(I{1}));
    stop_after_real_progress.emplace("enabled", V(false));
    powered_then_manual.accept("P", stop_after_real_progress);
    Runner stopped_then_manual(source);
    stopped_then_manual.world = w::World::restore("press-feed", source.profile,
        powered_then_manual.world->snapshot());
    stopped_then_manual.p = {2, 1, 0};
    auto finish_while_stopped = turn;
    finish_while_stopped.at("request") = V("finish-after-real-press-tick-while-stopped");
    const auto stopped_finish = stopped_then_manual.accept("P", finish_while_stopped);
    check(std::get<I>(stopped_finish.at("prior_auto_remaining_ticks").storage()) == 1 &&
          w::World::restore("press-feed", source.profile, stopped_then_manual.world->snapshot()),
          "Real powered progress remains valid after the wheel stops and a manual turn finishes it.");
    auto resume_after_real_progress = stop_after_real_progress;
    resume_after_real_progress.at("request") = V("resume-after-real-press-tick");
    resume_after_real_progress.at("enabled") = V(true);
    powered_then_manual.accept("P", resume_after_real_progress);
    auto finish_after_power = turn;
    finish_after_power.at("request") = V("finish-after-powered-progress");
    const auto powered_finish = powered_then_manual.accept("P", finish_after_power);
    check(std::get<I>(powered_finish.at("formed_products").storage()) == 1 &&
          std::get<I>(powered_finish.at("prior_auto_remaining_ticks").storage()) == 1 &&
          w::World::restore("press-feed", source.profile, powered_then_manual.world->snapshot()) != nullptr,
          "Real automatic progress survives later wheel toggles and a completing manual turn.");
    run.accept("P", turn);
    check(run.world->snapshot().state.material.dropped_material.at({0, 1, 0})
              .work_lots.front().remaining_ticks == 1 &&
          run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state.material.dropped_material.at({-1, 1, 0}) == m::Cargo{0, 1, {}} &&
          w::World::restore("press-feed", source.profile, run.world->snapshot()) != nullptr,
          "A manual crank and a powered tick share the same retained lot and valid checkpoint.");
    auto clear_manual = pickup;
    clear_manual.at("request") = V("clear-cranked-powered-exit");
    run.accept("P", clear_manual);
    auto feed_recovery = feed_again;
    feed_recovery.at("request") = V("feed-powered-for-recovery");
    run.accept("P", feed_recovery);
    check(run.world->tick().error == w::TransactionError::none,
          "Power starts the fifth blank before actor recovery.");
    check(run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state.material.dropped_material.at({0, 1, 0})
              .work_lots.front().remaining_ticks == 1,
          "A powered tick advances the fifth WorkLot before it leaves the press.");
    const auto recoverable = run.world->snapshot().state.material.dropped_material.at({0, 1, 0})
        .work_lots.front();
    auto recover = request("P", "recover-powered-partial", "pickup_material");
    recover.emplace("center", V(point(0, 1, 0)));
    recover.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
        {"work_lots", V(V::Array{V(O{{"id", V(recoverable.id)}, {"recipe_input", V(I{1})},
            {"cycle_ticks", V(I{2})}, {"remaining", V(recoverable.remaining_ticks)},
            {"completed_subticks", V(recoverable.completed_subticks)},
            {"work_remainder", V(recoverable.work_remainder)},
            {"work_remainder_denominator", V(recoverable.work_remainder_denominator)}})})}}));
    run.accept("P", recover);
    check(recoverable.id == 5 &&
          run.world->snapshot().state.material.cargo.at("P").work_lots.back() == recoverable &&
          !run.world->snapshot().state.material.dropped_material.contains({0, 1, 0}) &&
          w::World::restore("press-feed", source.profile, run.world->snapshot()) != nullptr,
          "Actor recovery returns the exact automatically advanced partial lot and valid checkpoint.");
    Runner refeed_powered(source);
    refeed_powered.world = w::World::restore("press-feed", source.profile, run.world->snapshot());
    auto hand_refeed = request("P", "refeed-powered-partial", "refeed_press_work");
    hand_refeed.emplace("target", V(frames[0]));
    hand_refeed.emplace("generation", V(frame_generations[0]));
    hand_refeed.emplace("entry", V(point(1, 1, 0)));
    hand_refeed.emplace("work_id", V(recoverable.id));
    auto wrong_powered_id = hand_refeed;
    wrong_powered_id.at("request") = V("refeed-wrong-powered-id");
    wrong_powered_id.at("work_id") = V(recoverable.id + 1);
    refeed_powered.refuses("P", wrong_powered_id, "unavailable_work");
    refeed_powered.accept("P", hand_refeed);
    const auto reinserted_powered = refeed_powered.world->snapshot();
    check(reinserted_powered.state.material.cargo.at("P").work_lots.empty() &&
          reinserted_powered.state.material.dropped_material.at({0, 1, 0}).work_lots ==
              std::vector<m::WorkLot>{recoverable} &&
          w::World::restore("press-feed", source.profile, reinserted_powered) != nullptr,
          "Exact-ID hand refeed preserves an automatically advanced lot under its original press.");
    refeed_powered.world = codec_restore(source.profile, reinserted_powered,
          "The serialized full-speed hand refeed retains its exact powered WorkLot.");
    const auto products_before = reinserted_powered.state.material.cargo.at("P").products;
    check(refeed_powered.world->tick().error == w::TransactionError::none,
          "The reinserted partial WorkLot accepts one more real powered tick.");
    check(refeed_powered.world->snapshot().state.material.dropped_material.at({-1, 1, 0}).products == 1,
          "One remaining powered tick forms a single product from the reinserted WorkLot.");
    refeed_powered.world = codec_restore(source.profile, refeed_powered.world->snapshot(),
          "The powered plate retains its identity and custody through checkpoint serialization.");
    auto pick_reformed = pickup;
    pick_reformed.at("request") = V("pickup-refed-powered-product");
    refeed_powered.accept("P", pick_reformed);
    check(refeed_powered.world->snapshot().state.material.cargo.at("P").products == products_before + 1 &&
          codec_restore(source.profile, refeed_powered.world->snapshot(),
              "The picked plate round trips through the actual checkpoint codec.") != nullptr,
          "The reformed product enters actor cargo once with valid powered history.");
}

void belt_feeds_a_placed_press() {
    auto source = site();
    source.profile.build_reach = 100;
    source.profile.material.hand_carry_capacity = 64;
    source.profile.waterwheel_rate = {1, 1};
    source.profile.finite_parts[{s::Role::waterwheel, 0, 0}] = 2;
    source.profile.finite_parts[{s::Role::shaft, 0, 2}] = 3;
    source.profile.finite_parts[{s::Role::belt, 0, 0}] = 1;
    source.state.topology.sources = {{"press-wheel", source.profile.waterwheel_rate},
        {"feed-wheel", source.profile.waterwheel_rate}};
    source.state.topology.parts.push_back(
        {{"feed-wheel", g::Kind::hub, {8, 0, -8}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel});
    for (const auto& [id, center] : {std::pair{"feed-drive", g::Point{8, 0, -4}},
                                     std::pair{"feed-outside", g::Point{8, 0, 0}},
                                     std::pair{"feed-mouth", g::Point{4, 0, 0}}})
        source.state.topology.parts.push_back({{id, g::Kind::shaft, center, g::Axis::z, 0, 2},
            1, s::Role::shaft});
    source.state.topology.belt_spans.push_back({{"press-input-belt", "feed-outside", "feed-mouth"}, 1});
    source.state.material.belt_lanes.emplace("press-input-belt", m::BeltLane{{std::nullopt, std::nullopt}, 0});
    for (const auto& part : source.state.topology.parts)
        source.state.issued_entities.emplace(part.geometry.id, part.generation);
    source.state.issued_entities.emplace("press-input-belt", 1);
    Runner run(source);
    run.p = {4.95, 1, 9.9};
    for (int n = 0; n < 8; ++n) {
        auto cut = request("P", "inlet-wood-" + std::to_string(n), "harvest_source");
        cut.emplace("target", V("tree"));
        run.accept("P", cut);
    }
    for (int n = 0; n < 4; ++n) {
        auto cut = request("P", "inlet-branch-" + std::to_string(n), "harvest_source");
        cut.emplace("target", V("tree-branch"));
        run.accept("P", cut);
    }
    run.p = {0, 1, 1.65};
    for (int n = 0; n < 6; ++n) {
        auto cut = request("P", "inlet-ore-" + std::to_string(n), "harvest_source");
        cut.emplace("target", V("ore"));
        run.accept("P", cut);
    }
    run.p = {1.65, 1, 6.6};
    std::string frame, original_shaft, original_cog;
    I frame_generation{};
    I original_shaft_generation{}, original_cog_generation{};
    for (const auto* name : {"wooden_frame", "anvil", "ram_face", "sliding_guide",
                              "tool_mount", "wooden_shaft", "wooden_cog"}) {
        auto craft = request("P", std::string("inlet-craft-") + name, "craft_component");
        craft.emplace("target", V("pod-fabrication-hub"));
        craft.emplace("generation", V(I{1}));
        craft.emplace("component", V(name));
        run.accept("P", craft);
        auto place = request("P", std::string("inlet-place-") + name, "place_component");
        place.emplace("component", V(name));
        const g::Point center = std::string(name) == "wooden_shaft" ? g::Point{1, 4, 0} :
            std::string(name) == "wooden_cog" ? g::Point{2, 4, 0} :
            g::Point{0, std::string(name) == "wooden_frame" ? I{0} :
                std::string(name) == "anvil" ? I{1} :
                std::string(name) == "ram_face" ? I{2} :
                std::string(name) == "sliding_guide" ? I{3} : I{4}, 0};
        place.emplace("center", V(point(center[0], center[1], center[2])));
        const auto made = run.accept("P", place);
        if (std::string(name) == "wooden_frame") {
            frame = std::get<std::string>(made.at("entity").storage());
            frame_generation = std::get<I>(made.at("generation").storage());
        } else if (std::string(name) == "wooden_shaft") {
            original_shaft = std::get<std::string>(made.at("entity").storage());
            original_shaft_generation = std::get<I>(made.at("generation").storage());
        } else if (std::string(name) == "wooden_cog") {
            original_cog = std::get<std::string>(made.at("entity").storage());
            original_cog_generation = std::get<I>(made.at("generation").storage());
        }
    }
    const auto empty_press = run.world->snapshot();
    check(w::World::restore("press-feed", source.profile, empty_press) != nullptr,
          "The assembled press and its actual belt route restore before any feed.");
    auto load = request("P", "inlet-load-raw", "load_belt_slot");
    load.emplace("target", V("press-input-belt"));
    load.emplace("generation", V(I{1}));
    load.emplace("slot", V(I{0}));
    load.emplace("item", V("raw"));
    load.emplace("work_id", V(I{0}));
    run.accept("P", load);
    const auto loaded = run.world->snapshot();
    check(run.world->tick().error == w::TransactionError::none,
          "A powered inlet belt moves its real blank toward a placed press.");
    check(run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state.material.dropped_material.at({0, 1, 0}) == m::Cargo{1, 0, {}},
          "The belt delivers exactly one blank to the press work point.");
    const auto fed_save = w::encode_checkpoint(source.profile, run.world->snapshot());
    check(std::holds_alternative<V>(fed_save) &&
          std::holds_alternative<w::Snapshot>(w::decode_checkpoint(source.profile, "press-feed", std::get<V>(fed_save))),
          "The unworked belt-fed blank survives the canonical checkpoint codec.");
    check(run.world->tick().error == w::TransactionError::none,
          "The fed press starts one retained WorkLot under power.");
    const auto working_save = w::encode_checkpoint(source.profile, run.world->snapshot());
    check(std::holds_alternative<V>(working_save) &&
          std::holds_alternative<w::Snapshot>(w::decode_checkpoint(source.profile, "press-feed", std::get<V>(working_save))),
          "The identified partial WorkLot survives the canonical checkpoint codec.");
    check(run.world->tick().error == w::TransactionError::none,
          "The fed press advances the retained WorkLot under power.");
    check(run.world->tick().error == w::TransactionError::none,
          "The fed press completes its retained WorkLot under power.");
    check(run.world->snapshot().state.material.dropped_material.at({-1, 1, 0}) == m::Cargo{0, 1, {}},
          "A belt-fed blank becomes one plate at the placed press exit.");
    const auto finished = run.world->snapshot();
    const auto saved = w::encode_checkpoint(source.profile, finished);
    check(std::holds_alternative<V>(saved) &&
          std::holds_alternative<w::Snapshot>(w::decode_checkpoint(source.profile, "press-feed", std::get<V>(saved))) &&
          w::World::restore("press-feed", source.profile, finished) != nullptr,
          "The formed belt-fed plate and its work identity restore from the canonical checkpoint.");
    const auto restore = [&](Runner& scenario, const w::Snapshot& snapshot) {
        scenario.world = w::World::restore("press-feed", source.profile, snapshot);
        check(scenario.world != nullptr, "An exact physical inlet state restores into a fresh World.");
    };
    Runner picked(source);
    restore(picked, finished);
    auto pickup_plate = request("P", "inlet-pickup-plate", "pickup_material");
    pickup_plate.emplace("center", V(point(-1, 1, 0)));
    pickup_plate.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{1})},
        {"work_lots", V(V::Array{})}}));
    const auto plate_id = finished.state.press_output_at_exit.at({-1, 1, 0});
    const auto picked_result = picked.accept("P", pickup_plate);
    check(std::get<I>(picked_result.at("press_output_work_id").storage()) == plate_id &&
          picked.world->snapshot().state.belt_press_products.empty() &&
          w::World::restore("press-feed", source.profile, picked.world->snapshot()) != nullptr,
          "Picking up the belt-fed plate records and clears its exact output claim.");
    auto forged_export = picked.world->snapshot();
    forged_export.state.belt_press_products[{-1, 1, 0}].insert(plate_id);
    forged_export.state.press_output_exported[{-1, 1, 0}].insert(plate_id);
    check(!w::World::restore("press-feed", source.profile, forged_export),
          "An actor-picked belt-fed plate cannot be forged into a later belt export.");
    Runner swapped_order(source);
    auto swapped = loaded;
    std::swap(swapped.state.topology.belt_spans.front().geometry.first_shaft,
        swapped.state.topology.belt_spans.front().geometry.last_shaft);
    std::swap(swapped.state.material.belt_lanes.at("press-input-belt").slots.front(),
        swapped.state.material.belt_lanes.at("press-input-belt").slots.back());
    restore(swapped_order, swapped);
    check(swapped_order.world->tick().error == w::TransactionError::none &&
          swapped_order.world->tick().error == w::TransactionError::none &&
          swapped_order.world->snapshot().state.material.dropped_material.at({0, 1, 0}) == m::Cargo{1, 0, {}},
          "Reversing endpoint storage order preserves the same physical inlet direction.");
    Runner occupied(source);
    restore(occupied, loaded);
    auto actor_feed = request("P", "inlet-actor-occupies-work", "feed_press");
    actor_feed.emplace("target", V(frame));
    actor_feed.emplace("generation", V(frame_generation));
    actor_feed.emplace("entry", V(point(1, 1, 0)));
    occupied.accept("P", actor_feed);
    for (int n = 0; n < 2; ++n)
        check(occupied.world->tick().error == w::TransactionError::none,
              "A full work point does not invalidate belt motion.");
    check(occupied.world->snapshot().state.material.belt_lanes.at("press-input-belt").slots.back() ==
              m::Cargo{1, 0, {}} && !occupied.world->snapshot().state.belt_press_work.contains({0, 1, 0}),
          "An occupied press retains the incoming blank on the actual belt mouth.");
    Runner stopped(source);
    restore(stopped, loaded);
    auto stop = request("P", "inlet-stop-drive", "set_drive");
    stop.emplace("target", V("feed-wheel"));
    stop.emplace("generation", V(I{1}));
    stop.emplace("enabled", V(false));
    stopped.accept("P", stop);
    const auto stationary = stopped.world->snapshot();
    check(stopped.world->tick().error == w::TransactionError::none &&
          stopped.world->snapshot().state.material.belt_lanes == stationary.state.material.belt_lanes &&
          !stopped.world->snapshot().state.material.dropped_material.contains({0, 1, 0}),
          "A stopped input belt retains its blank without feeding the press.");
    auto reverse_source = source;
    reverse_source.profile.waterwheel_rate = {-1, 1};
    for (auto& power : reverse_source.state.topology.sources)
        power.rate = reverse_source.profile.waterwheel_rate;
    Runner reverse(reverse_source);
    auto reversed = loaded;
    for (auto& power : reversed.state.topology.sources)
        power.rate = reverse_source.profile.waterwheel_rate;
    reverse.world = w::World::restore("press-feed", reverse_source.profile, reversed);
    check(reverse.world != nullptr && reverse.world->tick().error == w::TransactionError::none &&
          !reverse.world->snapshot().state.material.dropped_material.contains({0, 1, 0}) &&
          w::World::restore("press-feed", reverse_source.profile, reverse.world->snapshot()) != nullptr,
          "A reversed belt cannot feed the press and preserves the physical blank on restore.");
    Runner wrong_mouth(source);
    auto unsupported = loaded;
    for (auto& part : unsupported.state.topology.parts)
        if (part.geometry.id == "feed-mouth") part.geometry.center = {12, 0, 0};
    restore(wrong_mouth, unsupported);
    for (int n = 0; n < 2; ++n)
        check(wrong_mouth.world->tick().error == w::TransactionError::none,
              "A supported belt at a different endpoint advances without changing the press.");
    check(!wrong_mouth.world->snapshot().state.material.dropped_material.contains({0, 1, 0}) &&
          w::World::restore("press-feed", source.profile, wrong_mouth.world->snapshot()) != nullptr,
          "A belt ending away from the press cannot create work or lose its material.");
    Runner blocked_chute(source);
    restore(blocked_chute, empty_press);
    auto craft_obstacle = request("P", "inlet-craft-obstacle", "craft_component");
    craft_obstacle.emplace("target", V("pod-fabrication-hub"));
    craft_obstacle.emplace("generation", V(I{1}));
    craft_obstacle.emplace("component", V("tool_mount"));
    blocked_chute.accept("P", craft_obstacle);
    auto place_obstacle = request("P", "inlet-place-obstacle", "place_component");
    place_obstacle.emplace("component", V("tool_mount"));
    place_obstacle.emplace("center", V(point(2, 1, 0)));
    const auto obstacle = blocked_chute.accept("P", place_obstacle);
    blocked_chute.accept("P", load);
    for (int n = 0; n < 2; ++n)
        check(blocked_chute.world->tick().error == w::TransactionError::none,
              "A physical chute obstruction leaves the belt step valid.");
    check(blocked_chute.world->snapshot().state.material.belt_lanes.at("press-input-belt").slots.back() ==
              m::Cargo{1, 0, {}} &&
          !blocked_chute.world->snapshot().state.material.dropped_material.contains({0, 1, 0}),
          "A placed part between the belt and feed face retains the blank at the inlet.");
    auto clear_obstacle = request("P", "inlet-clear-obstacle", "reclaim_component");
    clear_obstacle.emplace("target", obstacle.at("entity"));
    clear_obstacle.emplace("generation", obstacle.at("generation"));
    blocked_chute.accept("P", clear_obstacle);
    check(blocked_chute.world->tick().error == w::TransactionError::none &&
          blocked_chute.world->snapshot().state.material.dropped_material.at({0, 1, 0}) == m::Cargo{1, 0, {}},
          "Clearing the short chute delivers that same retained blank once.");
    Runner mirrored(source);
    restore(mirrored, empty_press);
    std::string mirror_shaft;
    for (const auto& [name, center] : {std::pair{"wooden_shaft", g::Point{-1, 4, 0}},
                                      std::pair{"wooden_cog", g::Point{-2, 4, 0}}}) {
        auto craft = request("P", std::string("inlet-mirror-craft-") + name, "craft_component");
        craft.emplace("target", V("pod-fabrication-hub"));
        craft.emplace("generation", V(I{1}));
        craft.emplace("component", V(name));
        mirrored.accept("P", craft);
        auto place = request("P", std::string("inlet-mirror-place-") + name, "place_component");
        place.emplace("component", V(name));
        place.emplace("center", V(point(center[0], center[1], center[2])));
        const auto made = mirrored.accept("P", place);
        if (std::string(name) == "wooden_shaft") {
            mirror_shaft = std::get<std::string>(made.at("entity").storage());
        }
    }
    mirrored.accept("P", load);
    for (int n = 0; n < 2; ++n)
        check(mirrored.world->tick().error == w::TransactionError::none,
              "An ambiguous press cannot consume a belt item.");
    check(mirrored.world->snapshot().state.material.belt_lanes.at("press-input-belt").slots.back() ==
              m::Cargo{1, 0, {}} &&
          !mirrored.world->snapshot().state.material.dropped_material.contains({0, 1, 0}),
          "Competing complete drives leave the incoming blank at the belt mouth.");
    for (const auto& [id, generation, label] : {
             std::tuple{original_cog, original_cog_generation, "cog"},
             std::tuple{original_shaft, original_shaft_generation, "shaft"}}) {
        auto reclaim = request("P", std::string("inlet-remove-original-") + label, "reclaim_component");
        reclaim.emplace("target", V(id));
        reclaim.emplace("generation", V(generation));
        mirrored.accept("P", reclaim);
    }
    check(mirrored.world->tick().error == w::TransactionError::none &&
          mirrored.world->snapshot().state.material.dropped_material.at({0, 1, 0}) == m::Cargo{1, 0, {}},
          "The same belt feeds the newly unambiguous mirrored press orientation.");
    auto take = request("P", "inlet-take-crank", "take_hand_crank");
    take.emplace("target", V("pod-hand-crank"));
    take.emplace("generation", V(I{1}));
    mirrored.accept("P", take);
    w::Snapshot belt_manual_partial;
    for (int n = 0; n < 3; ++n) {
        auto turn = request("P", "inlet-mirror-turn-" + std::to_string(n), "turn_press_crank");
        turn.emplace("target", V(frame));
        turn.emplace("generation", V(frame_generation));
        turn.emplace("drive", V(mirror_shaft));
        turn.emplace("exit", V(point(-1, 1, 0)));
        mirrored.accept("P", turn);
        if (n == 1) belt_manual_partial = mirrored.world->snapshot();
    }
    check(w::World::restore("press-feed", source.profile, belt_manual_partial) != nullptr,
          "A belt-fed manual partial WorkLot restores with its exact progress witness.");
    auto forged_belt_turn = belt_manual_partial;
    forged_belt_turn.state.material.dropped_material.at({0, 1, 0}).work_lots.front().remaining_ticks = 0;
    for (auto& record : forged_belt_turn.history.records)
        if (std::get<std::string>(record.intent.at("request").storage()) == "inlet-mirror-turn-1") {
            auto lots = std::get<V::Array>(record.result.at("work_lots").storage());
            auto lot = std::get<O>(lots.front().storage());
            lot.at("remaining_ticks") = V(I{0});
            record.result.at("work_lots") = V(V::Array{V(lot)});
        }
    check(!w::World::restore("press-feed", source.profile, forged_belt_turn),
          "A belt-fed manual turn cannot claim two ticks of progress.");
    check(mirrored.world->snapshot().state.material.dropped_material.at({-1, 1, 0}) == m::Cargo{0, 1, {}} &&
          w::World::restore("press-feed", source.profile, mirrored.world->snapshot()) != nullptr,
          "A belt-fed mirrored press produces one plate through the same manual crank and restores.");
    Runner recovered(source);
    restore(recovered, loaded);
    for (int n = 0; n < 3; ++n)
        check(recovered.world->tick().error == w::TransactionError::none,
              "The separate belt-fed partial fixture advances without losing material.");
    const auto partial = recovered.world->snapshot().state.material.dropped_material.at({0, 1, 0}).work_lots.front();
    auto pickup = request("P", "inlet-recover-partial", "pickup_material");
    pickup.emplace("center", V(point(0, 1, 0)));
    pickup.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
        {"work_lots", V(V::Array{V(O{{"id", V(partial.id)}, {"recipe_input", V(I{1})},
            {"cycle_ticks", V(I{2})}, {"remaining", V(partial.remaining_ticks)},
            {"completed_subticks", V(partial.completed_subticks)},
            {"work_remainder", V(partial.work_remainder)},
            {"work_remainder_denominator", V(partial.work_remainder_denominator)}})})}}));
    recovered.accept("P", pickup);
    check(!recovered.world->snapshot().state.belt_press_work.contains({0, 1, 0}) &&
          recovered.world->snapshot().state.material.cargo.at("P").work_lots.back() == partial &&
          w::World::restore("press-feed", source.profile, recovered.world->snapshot()) != nullptr,
          "Actor pickup recovers the same partial WorkLot from the belt-fed press.");
    auto reload = load;
    reload.at("request") = V("inlet-reload-partial");
    reload.at("item") = V("work");
    reload.at("work_id") = V(partial.id);
    recovered.accept("P", reload);
    for (int n = 0; n < 4; ++n)
        check(recovered.world->tick().error == w::TransactionError::none,
              "The recovered WorkLot returns through the belt and resumes under power.");
    check(recovered.world->snapshot().state.material.dropped_material.at({-1, 1, 0}) == m::Cargo{0, 1, {}} &&
          w::World::restore("press-feed", source.profile, recovered.world->snapshot()) != nullptr,
          "The same recovered work identity produces one plate after belt re-entry.");
}

void belt_feeds_a_guided_press(bool copper) {
    auto source = site();
    if (copper) {
        source.profile.material.raw_mass = 4;
        source.profile.material.plate_mass = 3;
        source.profile.material.sheet_mass = 12;
    }
    source.profile.build_reach = 100;
    source.profile.material.hand_carry_capacity = 64;
    source.profile.waterwheel_rate = {1, 1};
    source.profile.finite_parts[{s::Role::waterwheel, 0, 0}] = 2;
    source.profile.finite_parts[{s::Role::shaft, 0, 2}] = 3;
    source.profile.finite_parts[{s::Role::belt, 0, 0}] = 1;
    source.state.topology.sources = {{"press-wheel", source.profile.waterwheel_rate},
        {"feed-wheel", source.profile.waterwheel_rate}};
    source.state.topology.parts.push_back(
        {{"feed-wheel", g::Kind::hub, {8, 0, -8}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel});
    for (const auto& [id, center] : {std::pair{"feed-drive", g::Point{8, 0, -4}},
                                     std::pair{"feed-outside", g::Point{8, 0, 0}},
                                     std::pair{"feed-mouth", g::Point{4, 0, 0}}})
        source.state.topology.parts.push_back({{id, g::Kind::shaft, center, g::Axis::z, 0, 2},
            1, s::Role::shaft});
    source.state.topology.belt_spans.push_back({{"guided-input-belt", "feed-outside", "feed-mouth"}, 1});
    source.state.material.belt_lanes.emplace("guided-input-belt", m::BeltLane{{std::nullopt, std::nullopt}, 0});
    for (const auto& part : source.state.topology.parts)
        source.state.issued_entities.emplace(part.geometry.id, part.generation);
    source.state.issued_entities.emplace("guided-input-belt", 1);
    Runner run(source);
    run.p = {4.95, 1, 9.9};
    for (int index = 0; index < 5; ++index) {
        auto cut = request("P", "belt-guided-wood-" + std::to_string(index), "harvest_source");
        cut.emplace("target", V("tree"));
        run.accept("P", cut);
    }
    run.p = {0, 1, 1.65};
    for (int index = 0; index < 5; ++index) {
        auto cut = request("P", "belt-guided-ore-" + std::to_string(index), "harvest_source");
        cut.emplace("target", V("ore"));
        run.accept("P", cut);
    }
    run.p = {1.65, 1, 6.6};
    for (const auto* kind : {"anvil", "ram_face", "sliding_guide", "wooden_shaft", "wooden_cog"}) {
        auto craft = request("P", std::string("belt-guided-craft-") + kind, "craft_component");
        craft.emplace("target", V("pod-fabrication-hub"));
        craft.emplace("generation", V(I{1}));
        craft.emplace("component", V(kind));
        run.accept("P", craft);
    }
    run.p = {2, 1, 0};
    for (const auto& [kind, center] : {std::pair{"anvil", g::Point{0, 0, 0}},
                                      std::pair{"ram_face", g::Point{0, 1, 0}},
                                      std::pair{"sliding_guide", g::Point{0, 3, 0}},
                                      std::pair{"wooden_shaft", g::Point{1, 4, 0}},
                                      std::pair{"wooden_cog", g::Point{2, 4, 0}}}) {
        auto place = request("P", std::string("belt-guided-place-") + kind, "place_component");
        place.emplace("component", V(kind));
        place.emplace("center", V(point(center[0], center[1], center[2])));
        run.accept("P", place);
    }
    const auto empty = run.world->snapshot();
    check(w::World::restore("press-feed", source.profile, empty) != nullptr,
          "A belt beside five guided parts restores without a frame or mount.");
    auto load = request("P", "belt-guided-load", "load_belt_slot");
    load.emplace("target", V("guided-input-belt"));
    load.emplace("generation", V(I{1}));
    load.emplace("slot", V(I{0}));
    load.emplace("item", V("raw"));
    load.emplace("work_id", V(I{0}));
    run.accept("P", load);
    const auto loaded = run.world->snapshot();
    Runner stopped(source);
    stopped.world = w::World::restore("press-feed", source.profile, loaded);
    check(stopped.world != nullptr, "The loaded guided belt restores before movement.");
    auto stop = request("P", "belt-guided-stop", "set_drive");
    stop.emplace("target", V("press-wheel"));
    stop.emplace("generation", V(I{1}));
    stop.emplace("enabled", V(false));
    stopped.accept("P", stop);
    check(stopped.world->tick().error == w::TransactionError::none &&
          stopped.world->snapshot().state.material.belt_lanes.at("guided-input-belt").slots.front() ==
              m::Cargo{1, 0, {}} &&
          !stopped.world->snapshot().state.material.dropped_material.contains({0, 0, 0}) &&
          w::World::restore("press-feed", source.profile, stopped.world->snapshot()) != nullptr,
          "Stopped power retains the exact belt blank before guided press feed.");
    check(run.world->tick().error == w::TransactionError::none &&
          run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state.material.dropped_material.at({0, 0, 0}).raw_units == 1,
          "The powered belt feeds exactly one blank to a frame-free anvil.");
    const auto fed = run.world->snapshot();
    check(w::validate(source.profile, fed), "A belt-fed guided blank has valid World history.");
    check(codec_restore(source.profile, fed, "A belt-fed guided blank restores at its anvil.") != nullptr,
          "The belt feed retains exact input custody through checkpoint serialization.");
    for (int index = 0; index < 3; ++index)
        check(run.world->tick().error == w::TransactionError::none,
              "The frame-free belt-fed press advances under signed power.");
    const auto finished = run.world->snapshot();
    check(w::validate(source.profile, finished), "A belt-fed guided product has valid World history.");
    check(finished.state.material.dropped_material.at({-1, 0, 0}).products == 1 &&
          (!copper || finished.state.material.dropped_material.at({0, 0, 0}).offcuts == 1) &&
          codec_restore(source.profile, finished,
              "The guided belt-fed plate survives checkpoint reload.") != nullptr,
          "The guided press forms one plate and any required offcut from its belt-fed blank.");
    if (copper) {
        auto moved = finished;
        moved.state.material.dropped_material.at({0, 0, 0}).offcuts = 0;
        moved.state.material.dropped_material.emplace(g::Point{0, 0, 4},
            m::Cargo{0, 0, {}, 1});
        check(!w::World::restore("press-feed", source.profile, moved),
              "A saved copper offcut cannot move away from its belt-fed work point.");
        auto doubled = finished;
        doubled.state.material.dropped_material.emplace(g::Point{0, 0, 4},
            m::Cargo{0, 0, {}, 1});
        check(!w::World::restore("press-feed", source.profile, doubled),
              "A second belt-fed copper offcut cannot be invented at another work point.");
        auto attributed = finished;
        attributed.state.material.dropped_material.at({0, 0, 0}).offcuts = 0;
        attributed.state.material.dropped_material.emplace(g::Point{0, 0, 4},
            m::Cargo{0, 0, {}, 1});
        for (auto& [id, witness] : attributed.state.press_progress) {
            if (!attributed.state.belt_press_work_ids.contains(id)) continue;
            for (auto& event : witness.automatic_transitions) event.work = {0, 0, 4};
        }
        check(!w::World::restore("press-feed", source.profile, attributed),
              "Forged transition coordinates cannot attribute the offcut to another work point.");
        auto recover = request("Q", "belt-guided-recover-offcut", "pickup_material");
        recover.emplace("center", V(point(0, 0, 0)));
        recover.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
            {"work_lots", V(V::Array{})}, {"offcuts", V(I{1})}, {"sheets", V(I{0})}}));
        run.accept("Q", recover);
        const auto recovered = run.world->snapshot();
        check(recovered.state.material.cargo.at("Q").offcuts == 1 &&
              !recovered.state.material.dropped_material.contains({0, 0, 0}) &&
              codec_restore(source.profile, recovered,
                  "The second actor's recovered belt offcut survives a fresh checkpoint.") != nullptr,
              "Q can recover the one real offcut without disturbing the finished plate.");
    }
}

void powered_broad_sheet_custody() {
    auto source = site();
    source.profile.initial_units = 80;
    source.state.material.initial_units = 80;
    source.state.material.stock.source = 80;
    source.profile.material.hand_carry_capacity = 40;
    source.profile.material.raw_mass = 4;
    source.profile.material.plate_mass = 3;
    source.profile.material.sheet_mass = 12;
    source.profile.waterwheel_rate = {1, 2};
    source.state.topology.parts.front().geometry.center = {8, 4, 0};
    source.state.topology.sources = {{"press-wheel", source.profile.waterwheel_rate}};
    source.profile.finite_parts[{s::Role::shaft, 0, 2}] = 1;
    source.state.kits.at("P")[{s::Role::shaft, 0, 2}] = 1;
    source.profile.finite_parts[{s::Role::waterwheel, 0, 0}] = 2;
    source.state.kits.at("P")[{s::Role::waterwheel, 0, 0}] = 1;
    Runner run(source);
    run.p = {5.8, 1, 0.8};
    auto cross = request("P", "sheet-place-cross-shaft", "place");
    cross.emplace("role", V("shaft"));
    cross.emplace("center", V(point(14, 4, 0)));
    cross.emplace("axis", V("x"));
    cross.emplace("teeth", V(I{0}));
    cross.emplace("half_span", V(I{2}));
    auto misaligned = cross;
    misaligned.at("request") = V("sheet-cross-shaft-wrong-grid");
    misaligned.at("center") = V(point(14, 4, 2));
    run.refuses("P", misaligned, "invalid_cell");
    run.accept("P", cross);
    run.p = {0, 1, 1.65};
    for (int index = 0; index < 32; ++index) {
        auto harvest = request("P", "sheet-ore-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("ore"));
        run.accept("P", harvest);
    }
    run.p = {4.95, 1, 4.95};
    for (int index = 0; index < 4; ++index) {
        auto harvest = request("P", "sheet-tree-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("tree"));
        run.accept("P", harvest);
    }
    run.p = {1.65, 1, 6.6};
    for (const auto* kind : {"anvil", "ram_face", "sliding_guide",
                             "softmetal_shaft", "softmetal_cog"})
        for (int index = 0; index < 4; ++index) {
            auto craft = request("P", std::string("sheet-craft-") + kind + std::to_string(index),
                "craft_component");
            craft.emplace("target", V("pod-fabrication-hub"));
            craft.emplace("generation", V(I{1}));
            craft.emplace("component", V(kind));
            run.accept("P", craft);
        }
    run.p = {5.8, 1, 0.8};
    std::string first_anvil;
    I first_generation{};
    for (int index = 0; index < 4; ++index) {
        const I x = 12 + (index % 2) * 4;
        const I z = (index / 2) * 4;
        const I outward = index % 2 == 0 ? -1 : 1;
        const std::pair<const char*, g::Point> parts[] = {
            {"anvil", {x, 0, z}}, {"ram_face", {x, 1, z}},
            {"sliding_guide", {x, 3, z}},
            {"softmetal_shaft", {x + outward, 4, z}},
            {"softmetal_cog", {x + outward * 2, 4, z}}};
        for (const auto& [kind, center] : parts) {
            auto place = request("P", std::string("sheet-place-") + kind + std::to_string(index),
                "place_component");
            place.emplace("component", V(kind));
            place.emplace("center", V(point(center[0], center[1], center[2])));
            const auto made = run.accept("P", place);
            if (index == 0 && std::string(kind) == "anvil") {
                first_anvil = std::get<std::string>(made.at("entity").storage());
                first_generation = std::get<I>(made.at("generation").storage());
            }
        }
    }
    const auto geometry = factory::assembly::inspect_broad_press([&] {
        std::vector<factory::assembly::Part> parts;
        for (const auto& [id, placed] : run.world->snapshot().state.placed_components)
            parts.push_back({id, placed.kind, placed.center, placed.generation});
        return parts;
    }(), {12, 0, 0});
    check(geometry.press && w::BroadPressDriveIndex(w::drive_power(source.profile,
        run.world->snapshot().state)).inspect(*geometry.press).status ==
            w::BroadPressDriveStatus::ready,
        "Twenty placed parts and the actual half-speed source form one live four-pad head.");
    run.p = {0, 1, 1.65};
    for (int index = 32; index < 35; ++index) {
        auto harvest = request("P", "sheet-ore-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("ore"));
        run.accept("P", harvest);
    }
    run.p = {5.8, 1, 0.8};
    auto feed = request("P", "sheet-feed", "feed_broad_press");
    feed.emplace("target", V(first_anvil));
    feed.emplace("generation", V(first_generation));
    const auto before_distant_feed = run.world->snapshot().state;
    run.p = {1.05, 1, 0};
    auto distant_feed = feed;
    distant_feed.at("request") = V("sheet-feed-far-corner-out-of-reach");
    run.refuses("P", distant_feed, "out_of_reach");
    check(run.world->snapshot().state == before_distant_feed,
        "Broad feed cannot place three stock chunks across an unreachable far corner.");
    run.p = {5.8, 1, 0.8};
    run.accept("P", feed);
    const auto fed = run.world->snapshot();
    check(fed.state.material.cargo.at("P").raw_units == 0 &&
          fed.state.material.dropped_material.at({12, 0, 0}).work_lots.front().recipe.output ==
              m::WorkOutput::sheet &&
          codec_restore(source.profile, fed, "The newly fed broad lot restores at its anvil."),
        "Feeding three finite stock chunks creates exactly one located sheet-bound lot.");
    auto forged_feed_reach = fed;
    for (auto& record : forged_feed_reach.history.records)
        if (std::get<std::string>(record.intent.at("request").storage()) == "sheet-feed") {
            auto targets = std::get<V::Array>(record.result.at("targets").storage());
            auto distances = std::get<V::Array>(record.result.at("distances_squared").storage());
            check(targets.size() == 4 && distances.size() == 4,
                "The accepted broad feed witnesses all four physical work cells.");
            targets[3] = targets[0];
            distances[3] = distances[0];
            record.result.at("targets") = V(std::move(targets));
            record.result.at("distances_squared") = V(std::move(distances));
        }
    check(!w::World::restore("press-feed", source.profile, forged_feed_reach),
        "A saved broad feed cannot replace far-corner reach with a second origin claim.");
    Runner stopped(source);
    stopped.world = w::World::restore("press-feed", source.profile, fed);
    stopped.p = {5.8, 1, 0.8};
    auto stop = request("P", "sheet-stop", "set_drive");
    stop.emplace("target", V("press-wheel"));
    stop.emplace("generation", V(I{1}));
    stop.emplace("enabled", V(false));
    stopped.accept("P", stop);
    check(stopped.world->tick().error == w::TransactionError::none &&
          stopped.world->snapshot().state.material.dropped_material.at(
              {12, 0, 0}).work_lots.front().remaining_ticks == 2 &&
          codec_restore(source.profile, stopped.world->snapshot(),
              "The stopped broad work restores without invented progress."),
        "An assembled but stopped four-pad drive leaves the exact batch untouched.");
    Runner disconnected(source);
    disconnected.world = w::World::restore("press-feed", source.profile, fed);
    disconnected.p = {5.8, 1, 0.8};
    auto reclaim = request("P", "sheet-disconnect", "reclaim_component");
    const auto& live_parts = fed.state.placed_components;
    const auto missing = std::find_if(live_parts.begin(), live_parts.end(), [](const auto& entry) {
        return entry.second.kind == m::Component::softmetal_cog &&
            entry.second.center == g::Point{10, 4, 0};
    });
    check(missing != live_parts.end(), "The powered broad fixture has a removable pad cog.");
    reclaim.emplace("target", V(missing->first));
    reclaim.emplace("generation", V(missing->second.generation));
    disconnected.accept("P", reclaim);
    check(disconnected.world->tick().error == w::TransactionError::none &&
          disconnected.world->snapshot().state.material.dropped_material.at(
              {12, 0, 0}).work_lots.front().remaining_ticks == 2 &&
          codec_restore(source.profile, disconnected.world->snapshot(),
              "The disconnected broad work restores without invented progress."),
        "Removing one cog stops all four pads without losing the unfinished sheet.");
    auto spare = request("P", "sheet-spare-after-disconnect", "harvest_source");
    spare.emplace("target", V("ore"));
    disconnected.p = {0, 1, 1.65};
    disconnected.accept("P", spare);
    disconnected.p = {5.8, 1, 0.8};
    const auto second = std::find_if(fed.state.placed_components.begin(),
        fed.state.placed_components.end(), [](const auto& entry) {
            return entry.second.kind == m::Component::anvil &&
                entry.second.center == g::Point{16, 0, 0};
        });
    check(second != fed.state.placed_components.end(),
        "The second cell retains its own anvil identity after a pad is dismantled.");
    auto overlapping_small = request("P", "sheet-overlap-small", "feed_press");
    overlapping_small.emplace("target", V(second->first));
    overlapping_small.emplace("generation", V(second->second.generation));
    overlapping_small.emplace("entry", V(point(17, 0, 0)));
    disconnected.refuses("P", overlapping_small, "broad_work_occupied");
    for (int index = 0; index < 2; ++index)
        check(run.world->tick().error == w::TransactionError::none,
            "The connected half-speed broad head can advance one real authority tick.");
    const auto partial = run.world->snapshot();
    check(partial.state.material.dropped_material.at({12, 0, 0}).work_lots.front().remaining_ticks == 1 &&
          codec_restore(source.profile, partial, "The partial broad lot restores with exact work."),
        "Two half-speed ticks retain the one-stroke partial work and its original identity.");
    auto forged_partial = partial;
    forged_partial.state.material.dropped_material.at({12, 0, 0}).work_lots.front().remaining_ticks = 2;
    check(!w::World::restore("press-feed", source.profile, forged_partial),
        "A mass-balanced checkpoint cannot rewrite the broad lot's proven powered progress.");
    Runner refed(source);
    refed.world = w::World::restore("press-feed", source.profile, partial);
    refed.p = {5.8, 1, 0.8};
    const auto& partial_lot = partial.state.material.dropped_material.at({12, 0, 0}).work_lots.front();
    auto recover_partial = request("P", "sheet-recover-partial", "pickup_material");
    recover_partial.emplace("center", V(point(12, 0, 0)));
    recover_partial.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
        {"work_lots", V(V::Array{V(O{{"id", V(partial_lot.id)},
            {"recipe_input", V(I{3})}, {"cycle_ticks", V(I{2})},
            {"remaining", V(partial_lot.remaining_ticks)},
            {"completed_subticks", V(partial_lot.completed_subticks)},
            {"work_remainder", V(partial_lot.work_remainder)},
            {"work_remainder_denominator", V(partial_lot.work_remainder_denominator)},
            {"output_form", V("sheet")}})})},
        {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
    refed.accept("P", recover_partial);
    check(w::validate(source.profile, refed.world->snapshot()),
        "The picked broad partial lot has valid replay before refeed.");
    auto fake_refeed = request("P", "sheet-wrong-refeed", "refeed_broad_press_work");
    fake_refeed.emplace("target", V(first_anvil));
    fake_refeed.emplace("generation", V(first_generation));
    fake_refeed.emplace("work_id", V(partial_lot.id + 1));
    refed.refuses("P", fake_refeed, "incompatible_work");
    fake_refeed.at("request") = V("sheet-real-refeed");
    fake_refeed.at("work_id") = V(partial_lot.id);
    const auto before_distant_refeed = refed.world->snapshot().state;
    refed.p = {1.05, 1, 0};
    auto distant_refeed = fake_refeed;
    distant_refeed.at("request") = V("sheet-refeed-far-corner-out-of-reach");
    refed.refuses("P", distant_refeed, "out_of_reach");
    check(refed.world->snapshot().state == before_distant_refeed,
        "Broad refeed keeps the same partial lot when the far corner is out of reach.");
    refed.p = {5.8, 1, 0.8};
    refed.accept("P", fake_refeed);
    check(w::validate(source.profile, refed.world->snapshot()),
        "The reinserted broad partial lot has valid replay after refeed.");
    check(codec_restore(source.profile, refed.world->snapshot(),
              "The same partial broad serial survives recovery and refeed.") != nullptr,
        "The original partial workpiece returns to its four-pad face without new mass.");
    for (int index = 0; index < 2; ++index)
        check(run.world->tick().error == w::TransactionError::none,
            "Two further half-speed ticks can finish the broad batch.");
    const auto finished = run.world->snapshot();
    check(finished.state.material.dropped_material.at({12, 0, 0}).sheets.size() == 1 &&
          finished.state.material.dropped_material.at({12, 0, 0}).sheets.front().id ==
              fed.state.material.dropped_material.at({12, 0, 0}).work_lots.front().id &&
          codec_restore(source.profile, finished, "The formed twelve-mass sheet restores."),
        "Four powered half-speed ticks form one sheet on the same four-cell work face.");
    run.p = {0, 1, 1.65};
    for (int index = 35; index < 38; ++index) {
        auto harvest = request("P", "sheet-later-ore-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("ore"));
        run.accept("P", harvest);
    }
    run.p = {5.8, 1, 0.8};
    auto blocked_feed = feed;
    blocked_feed.at("request") = V("sheet-blocked-feed");
    run.refuses("P", blocked_feed, "input_full");
    auto forged = finished;
    forged.state.material.dropped_material.at({12, 0, 0}).sheets.front().rotation = 1;
    check(!w::World::restore("press-feed", source.profile, forged),
        "Fresh World restore refuses a sheet orientation invented after the powered stroke.");
    auto pickup = request("Q", "sheet-pickup", "pickup_material");
    pickup.emplace("center", V(point(12, 0, 0)));
    pickup.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
        {"work_lots", V(V::Array{})}, {"offcuts", V(I{0})}, {"sheets", V(I{1})},
        {"sheet_items", V(V::Array{V(O{{"id", V(finished.state.material.dropped_material.at(
            {12, 0, 0}).sheets.front().id)}, {"rotation", V(I{0})}})})}}));
    run.q = {200, 1, 200};
    run.refuses("Q", pickup, "out_of_reach");
    check(run.world->snapshot().state.material.dropped_material.at({12, 0, 0}).sheets.size() == 1,
        "A remote actor cannot claim the four-cell sheet by naming its origin.");
    run.q = {5.5, 1, 1.0};
    pickup.at("request") = V("sheet-near-pickup");
    run.accept("Q", pickup);
    const auto recovered = run.world->snapshot();
    check(recovered.state.material.cargo.at("Q").sheets.size() == 1 &&
          !recovered.state.material.dropped_material.contains({12, 0, 0}) &&
          codec_restore(source.profile, recovered, "Q's exact sheet identity restores."),
        "A second actor physically clears the completed sheet with exact checkpoint custody.");
    const auto sheet_id = recovered.state.material.cargo.at("Q").sheets.front().id;
    auto stage = request("Q", "sheet-stage", "place_sheet");
    stage.emplace("center", V(point(24, 0, 0)));
    stage.emplace("sheet_id", V(sheet_id));
    run.q = {10.7, 1, 0.8};
    auto no_support = stage;
    no_support.at("request") = V("sheet-stage-no-support");
    run.refuses("Q", no_support, "missing_support");
    run.p = {0, 1, 1.65};
    for (int index = 38; index < 46; ++index) {
        auto harvest = request("P", "sheet-stage-ore-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("ore"));
        run.accept("P", harvest);
    }
    run.p = {1.65, 1, 6.6};
    for (int index = 0; index < 4; ++index) {
        auto craft = request("P", "sheet-stage-craft-anvil-" + std::to_string(index),
            "craft_component");
        craft.emplace("target", V("pod-fabrication-hub"));
        craft.emplace("generation", V(I{1}));
        craft.emplace("component", V("anvil"));
        run.accept("P", craft);
    }
    std::string support;
    I support_generation{};
    for (int index = 0; index < 4; ++index) {
        const I x = 24 + (index % 2) * 4;
        const I z = (index / 2) * 4;
        run.p = {static_cast<double>(x) * 0.4125, 1,
            static_cast<double>(z) * 0.4125};
        auto place = request("P", "sheet-stage-anvil-" + std::to_string(index),
            "place_component");
        place.emplace("component", V("anvil"));
        place.emplace("center", V(point(x, 0, z)));
        const auto made = run.accept("P", place);
        if (index == 0) {
            support = std::get<std::string>(made.at("entity").storage());
            support_generation = std::get<I>(made.at("generation").storage());
        }
        if (index == 2) {
            auto three_supports = stage;
            three_supports.at("request") = V("sheet-stage-three-supports");
            run.refuses("Q", three_supports, "missing_support");
        }
    }
    for (int index = 0; index < 4; ++index) {
        const g::Point cell{24 + (index % 2) * 4, 0, (index / 2) * 4};
        check(std::any_of(run.world->snapshot().state.placed_components.begin(),
                run.world->snapshot().state.placed_components.end(),
                [&](const auto& entry) {
                    return entry.second.kind == factory::materials::Component::anvil &&
                        entry.second.center == cell;
                }), "Each separate support cell retains its placed anvil.");
    }
    auto wrong_sheet = stage;
    wrong_sheet.at("request") = V("sheet-stage-wrong-id");
    wrong_sheet.at("sheet_id") = V(sheet_id + 1);
    run.refuses("Q", wrong_sheet, "unavailable_input");
    run.q = {7.65, 1, 0};
    auto far_corner = stage;
    far_corner.at("request") = V("sheet-stage-far-corner");
    run.refuses("Q", far_corner, "out_of_reach");
    run.q = {10.7, 1, 0.8};
    run.accept("Q", stage);
    const auto staged = run.world->snapshot();
    check(staged.state.material.cargo.at("Q").sheets.empty() &&
          staged.state.material.dropped_material.at({24, 0, 0}).sheets ==
              recovered.state.material.cargo.at("Q").sheets &&
          codec_restore(source.profile, staged, "The staged sheet restores at its separate support."),
        "One identity-bearing sheet moves from Q to a second supported four-cell area.");
    auto forged_staging = staged;
    forged_staging.state.material.dropped_material.at({24, 0, 0}).sheets.front().rotation = 1;
    check(!w::World::restore("press-feed", source.profile, forged_staging),
        "Staged sheet orientation cannot be rewritten without an authoritative turn.");
    auto duplicate = stage;
    duplicate.at("request") = V("sheet-stage-duplicate");
    run.refuses("Q", duplicate, "occupied");
    auto reclaim_support = request("P", "sheet-stage-reclaim-support", "reclaim_component");
    reclaim_support.emplace("target", V(support));
    reclaim_support.emplace("generation", V(support_generation));
    run.p = {9.9, 1, 0};
    run.refuses("P", reclaim_support, "occupied");
    auto recover_staged = request("P", "sheet-stage-recover", "pickup_material");
    recover_staged.emplace("center", V(point(24, 0, 0)));
    recover_staged.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
        {"work_lots", V(V::Array{})}, {"offcuts", V(I{0})}, {"sheets", V(I{1})},
        {"sheet_items", V(V::Array{V(O{{"id", V(sheet_id)},
            {"rotation", V(I{0})}})})}}));
    run.p = {10.7, 1, 0.8};
    run.accept("P", recover_staged);
    const auto restaged = run.world->snapshot();
    check(restaged.state.material.cargo.at("P").sheets ==
              recovered.state.material.cargo.at("Q").sheets &&
          !restaged.state.material.dropped_material.contains({24, 0, 0}) &&
          codec_restore(source.profile, restaged, "P's recovered staged sheet restores."),
        "P can recover the same sheet from the second support without duplication.");
    auto stage_again = request("P", "sheet-shear-stage", "place_sheet");
    stage_again.emplace("center", V(point(24, 0, 0)));
    stage_again.emplace("sheet_id", V(sheet_id));
    run.accept("P", stage_again);
    auto shear = request("P", "sheet-shear-missing-blades", "stroke_broad_shear");
    shear.emplace("target", V(support));
    shear.emplace("generation", V(support_generation));
    shear.emplace("sheet_id", V(sheet_id));
    run.refuses("P", shear, "incomplete_shear");
    run.p = {0, 1, 1.65};
    for (int index = 0; index < 28; ++index) {
        auto harvest = request("P", "shear-ore-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("ore"));
        run.accept("P", harvest);
    }
    run.p = {4.95, 1, 4.95};
    for (int index = 0; index < 4; ++index) {
        auto harvest = request("P", "shear-tree-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("tree"));
        run.accept("P", harvest);
    }
    run.p = {1.65, 1, 6.6};
    for (const auto* kind : {"cutting_edge", "sliding_guide", "softmetal_shaft",
                             "softmetal_cog"})
        for (int index = 0; index < 4; ++index) {
            auto craft = request("P", std::string("shear-craft-") + kind + std::to_string(index),
                "craft_component");
            craft.emplace("target", V("pod-fabrication-hub"));
            craft.emplace("generation", V(I{1}));
            craft.emplace("component", V(kind));
            run.accept("P", craft);
        }
    auto wheel = request("P", "shear-wheel", "place");
    wheel.emplace("role", V("waterwheel"));
    wheel.emplace("center", V(point(24, 4, -4)));
    wheel.emplace("axis", V("z"));
    wheel.emplace("teeth", V(I{0}));
    wheel.emplace("half_span", V(I{0}));
    run.p = {9.9, 1, -0.8};
    run.accept("P", wheel);
    for (int index = 0; index < 4; ++index) {
        const I x = 24 + (index % 2) * 4;
        const I z = (index / 2) * 4;
        const I outward = index / 2 == 0 ? -1 : 1;
        const std::pair<const char*, g::Point> parts[] = {
            {"cutting_edge", {x, 1, z}}, {"sliding_guide", {x, 3, z}},
            {"softmetal_shaft", {x, 4, z + outward}},
            {"softmetal_cog", {x, 4, z + outward * 2}}};
        run.p = {static_cast<double>(x) * 0.4125, 1,
            static_cast<double>(z) * 0.4125};
        for (const auto& [kind, center] : parts) {
            auto place = request("P", std::string("shear-place-") + kind +
                std::to_string(index), "place_component");
            place.emplace("component", V(kind));
            place.emplace("center", V(point(center[0], center[1], center[2])));
            run.accept("P", place);
        }
    }
    const auto placed = run.world->snapshot();
    std::vector<factory::assembly::Part> shear_parts;
    for (const auto& [id, item] : placed.state.placed_components)
        shear_parts.push_back({id, item.kind, item.center, item.generation});
    const auto head = factory::assembly::inspect_broad_shear(shear_parts, {24, 0, 0});
    if (!head.shear) throw std::runtime_error("The separate cutting head status is " +
        std::to_string(static_cast<int>(head.status)) + ".");
    ++checks;
    const auto shear_drive = w::BroadPressDriveIndex(w::drive_power(source.profile,
        placed.state)).inspect(*head.shear);
    if (shear_drive.status != w::BroadPressDriveStatus::ready)
        throw std::runtime_error("The separate cutting drive status is " +
            std::to_string(static_cast<int>(shear_drive.status)) + ".");
    ++checks;
    run.p = {10.7, 1, 0.8};
    for (int stroke = 1; stroke <= 3; ++stroke) {
        shear.at("request") = V("sheet-shear-stroke-" + std::to_string(stroke));
        const auto result = run.accept("P", shear);
        check(std::get<I>(result.at("shear_strokes").storage()) == stroke &&
              run.world->snapshot().state.material.dropped_material.at(
                  {24, 0, 0}).sheets.front().id == sheet_id &&
              codec_restore(source.profile, run.world->snapshot(),
                  "A partial cutting stroke restores with the sheet."),
            "Each partial powered stroke keeps the one accessible sheet identity.");
        if (stroke == 2) {
            const auto components = run.world->snapshot().state.placed_components;
            const auto blade = std::find_if(components.begin(), components.end(),
                [](const auto& entry) {
                    return entry.second.kind == m::Component::cutting_edge &&
                        entry.second.center == g::Point{28, 1, 4};
                });
            check(blade != components.end(), "The fourth blade has a placed identity.");
            auto remove = request("P", "sheet-shear-remove-blade", "reclaim_component");
            remove.emplace("target", V(blade->first));
            remove.emplace("generation", V(blade->second.generation));
            run.p = {11.55, 1, 1.65};
            run.accept("P", remove);
            shear.at("request") = V("sheet-shear-three-blades");
            run.refuses("P", shear, "incomplete_shear");
            check(run.world->snapshot().state.shear_progress.at(sheet_id).strokes == 2 &&
                  codec_restore(source.profile, run.world->snapshot(),
                      "A removed blade preserves the saved partial cut."),
                "An interrupted three-blade width cannot finish the sheet.");
            auto replace = request("P", "sheet-shear-replace-blade", "place_component");
            replace.emplace("component", V("cutting_edge"));
            replace.emplace("center", V(point(28, 1, 4)));
            run.accept("P", replace);
            run.p = {10.7, 1, 0.8};
        }
    }
    auto stop_shear = request("P", "sheet-shear-stop", "set_drive");
    stop_shear.emplace("target", V("press-wheel"));
    stop_shear.emplace("generation", V(I{1}));
    stop_shear.emplace("enabled", V(false));
    run.p = {3.3, 1, 0};
    run.accept("P", stop_shear);
    run.p = {10.7, 1, 0.8};
    shear.at("request") = V("sheet-shear-unpowered");
    run.refuses("P", shear, "shear_unpowered");
    check(run.world->snapshot().state.shear_progress.at(sheet_id).strokes == 3,
        "Lost power leaves the three accepted cutting strokes intact.");
    stop_shear.at("request") = V("sheet-shear-restart");
    stop_shear.at("enabled") = V(true);
    run.p = {3.3, 1, 0};
    run.accept("P", stop_shear);
    run.p = {10.7, 1, 0.8};
    shear.at("request") = V("sheet-shear-finish");
    const auto finish = run.accept("P", shear);
    const auto four = factory::world::Snapshot(run.world->snapshot());
    check(std::get<I>(finish.at("formed_products").storage()) == 4 &&
          four.state.shear_progress.at(sheet_id).strokes == 4 &&
          !four.state.material.dropped_material.at({24, 0, 0}).sheets.size() &&
          std::all_of(head.shear->work_centers.begin(), head.shear->work_centers.end(),
              [&](const auto& point) {
                  return four.state.material.dropped_material.at(point).products == 1;
              }) &&
          codec_restore(source.profile, four, "Four separate plates restore after cutting."),
        "One twelve-mass sheet becomes exactly four ordinary three-mass plates.");
    const auto replay = run.send("P", shear);
    auto replay_expected = finish;
    replay_expected.at("duplicate") = V(true);
    check(replay.completed() && replay.result &&
          !factory::values::typed_difference(V(*replay.result), V(replay_expected)) &&
          run.world->snapshot().state == four.state &&
          run.world->snapshot().revision == four.revision,
        "The same authenticated request returns its cached result without another cut.");
    shear.at("request") = V("sheet-shear-duplicate");
    run.refuses("P", shear, "unavailable_input");
    auto forged_strokes = four;
    forged_strokes.state.shear_progress.at(sheet_id).strokes = 3;
    check(!w::World::restore("press-feed", source.profile, forged_strokes),
        "A saved cutting witness cannot erase the fourth accepted stroke.");
    auto plate = request("P", "sheet-shear-pickup", "pickup_material");
    plate.emplace("center", V(point(24, 0, 0)));
    plate.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{1})},
        {"work_lots", V(V::Array{})}, {"offcuts", V(I{0})}, {"sheets", V(I{0})}}));
    run.accept("P", plate);
    check(run.world->snapshot().state.material.cargo.at("P").products == 1 &&
          codec_restore(source.profile, run.world->snapshot(),
              "One ordinary shear plate pickup restores with its source history."),
        "A cut plate becomes ordinary actor cargo without moving the other three.");
}
} // namespace

int main() {
    try {
        frame_free_hand_press({8, 0, 0}, {1, 0, 0});
        frame_free_hand_press({8, 4, 8}, {0, 0, 1});
        actor_feed_is_physical_custody();
        two_placed_presses_advance_distinct_powered_work();
        belt_feeds_a_placed_press();
        belt_feeds_a_guided_press(false);
        belt_feeds_a_guided_press(true);
        powered_broad_sheet_custody();
        std::cout << "press_feed_world_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "press_feed_world_test: " << error.what() << '\n';
        return 1;
    }
}
