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
namespace s = factory::stationary;
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
    auto forged_product = formed;
    const auto produced = forged_product.state.material.dropped_material.at({7, 1, 0});
    forged_product.state.material.dropped_material.erase({7, 1, 0});
    forged_product.state.material.dropped_material.emplace(g::Point{7, 1, 1}, produced);
    check(!w::World::restore("press-feed", source.profile, forged_product),
          "A checkpoint cannot relocate the formed product without an accepted pickup.");
    auto pickup_product = request("P", "pickup-formed-product", "pickup_material");
    pickup_product.emplace("center", V(point(7, 1, 0)));
    pickup_product.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{1})},
        {"work_lots", V(V::Array{})}}));
    run.accept("P", pickup_product);
    check(run.world->snapshot().state.material.cargo.at("P").products == 1,
          "A physical actor retrieves the single formed product.");
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
    for (int index = 0; index < 20; ++index) {
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
    run.accept("P", turn);
    check(run.world->snapshot().state.material.dropped_material.at({0, 1, 0})
              .work_lots.front().remaining_ticks == 1 &&
          run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state.material.dropped_material.at({-1, 1, 0}) == m::Cargo{0, 1, {}} &&
          w::World::restore("press-feed", source.profile, run.world->snapshot()) != nullptr,
          "A manual crank and a powered tick share the same retained lot and valid checkpoint.");
}
} // namespace

int main() {
    try {
        actor_feed_is_physical_custody();
        two_placed_presses_advance_distinct_powered_work();
        std::cout << "press_feed_world_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "press_feed_world_test: " << error.what() << '\n';
        return 1;
    }
}
