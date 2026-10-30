#include "factory/checkpoint.hpp"
#include "native/factory-world/tests/harvest_fixture.hpp"

#include <iostream>
#include <memory>
#include <optional>
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
    profile.material.manual_ore = m::OreSite{"ore", {-6, 0, 0}};
    profile.material.timber_sites = {{"tree", {{24, 0, 24}, 8}},
                                     {"tree-branch", {{24, 0, 48}, 4}},
                                     {"crank-tree", {{32, 0, 24}, 16}}};
    profile.material.hand_carry_capacity = 24;
    profile.initial_units = 10;
    profile.actors = {"P", "Q"};
    profile.foundation_parts = 24;
    profile.starting_foundation_kits = {{"P", 15}, {"Q", 0}};
    profile.landing_pod_center = g::Point{8, 0, 32};
    profile.meters_per_grid_unit = 0.20625;
    profile.anchor_offset = {0, 0.4125, 0};
    profile.build_reach = 4;
    profile.waterwheel_rate = {2, 1};
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}};
    state.material.initial_units = 10;
    state.material.stock.source = 10;
    state.material.cargo = {{"P", {}}, {"Q", {}}};
    state.material.timber_remaining = {{"tree", 8}, {"tree-branch", 4},
                                       {"crank-tree", 16}};
    state.kits = {{"P", {}}, {"Q", {}}};
    state.foundation_kits = {{"P", 15}, {"Q", 0}};
    state.topology.drive_enabled = true;
    state.topology.parts = {
        {{"press-wheel", g::Kind::hub, {4, 4, 0}, g::Axis::x, 0, 0}, 1, s::Role::waterwheel}};
    state.topology.sources = {{"press-wheel", profile.waterwheel_rate}};
    state.landing_pod = w::LandingPod{"landing-pod", *profile.landing_pod_center, 1};
    state.fabrication_hub = w::FabricationHub{"pod-fabrication-hub",
        w::landing_hub_center(*profile.landing_pod_center), 1};
    state.issued_entities = {{"landing-pod", 1}, {"pod-fabrication-hub", 1},
        {"press-wheel", 1}};
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

struct CrankToken { std::string id; I generation; };

CrankToken craft_crank(Runner& run, const std::string& label) {
    const auto previous = run.p;
    run.p = {6.6, 1, 4.95};
    for (int index = 0; index < 2; ++index) {
        auto harvest = request("P", label + "-timber-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("crank-tree"));
        run.accept("P", harvest);
    }
    auto craft = request("P", label + "-craft", "field_craft");
    craft.emplace("component", V("hand_crank"));
    const auto result = run.accept("P", craft);
    run.p = previous;
    return {std::get<std::string>(result.at("crank_id").storage()),
        std::get<I>(result.at("crank_generation").storage())};
}

void one_slide_broad_sheet_custody() {
    auto source = site();
    // The shared site wheel occupies the upper-right tile of this full
    // housing. Keep this fixture's independent wheel outside the press.
    source.state.topology.parts.front().geometry.center = {-8, 4, 0};
    source.profile.initial_units = 31;
    source.state.material.initial_units = 31;
    source.state.material.stock.source = 31;
    source.profile.material.hand_carry_capacity = 40;
    source.profile.material.raw_mass = 4;
    source.profile.material.plate_mass = 3;
    source.profile.material.sheet_mass = 12;
    Runner run(source);
    run.p = {0, 1, 1.65};
    for (int index = 0; index < 31; ++index) {
        auto harvest = request("P", "sized-ore-" + std::to_string(index), "harvest_source");
        harvest.emplace("target", V("ore"));
        run.accept("P", harvest);
    }
    const auto crank = craft_crank(run, "sized-crank");
    run.p = {1.65, 1, 6.6};
    for (const auto& [kind, amount] : {std::pair{"anvil", 4},
             std::pair{"flat_head", 4}, std::pair{"copper_slide", 4}})
        for (int index = 0; index < amount; ++index) {
            auto craft = request("P", std::string("sized-craft-") + kind +
                std::to_string(index), "craft_component");
            craft.emplace("target", V("pod-fabrication-hub"));
            craft.emplace("generation", V(I{1}));
            craft.emplace("component", V(kind));
            run.accept("P", craft);
        }
    run.p = {1.65, 1, 0.8};
    std::string bed_id;
    I bed_generation{};
    std::string slide_id;
    I slide_generation{};
    for (const auto& [kind, center] : {
             std::pair{"broad_anvil", g::Point{0, 0, 0}},
             std::pair{"broad_flat_head", g::Point{0, 1, 0}},
             std::pair{"broad_copper_slide", g::Point{0, 4, 0}}}) {
        auto place = request("P", std::string("sized-place-") + kind, "place_component");
        place.emplace("component", V(kind));
        place.emplace("center", V(point(center[0], center[1], center[2])));
        const auto made = run.accept("P", place);
        if (std::string(kind) == "broad_anvil") {
            bed_id = std::get<std::string>(made.at("entity").storage());
            bed_generation = std::get<I>(made.at("generation").storage());
        } else if (std::string(kind) == "broad_copper_slide") {
            slide_id = std::get<std::string>(made.at("entity").storage());
            slide_generation = std::get<I>(made.at("generation").storage());
        }
    }
    const auto assembled = run.world->snapshot();
    check(assembled.state.placed_components.size() == 3 &&
          assembled.state.material.cargo.at("P").raw_units == 3 &&
          codec_restore(source.profile, assembled,
              "One sized workbed, head and slide restore with finite part custody."),
        "Twelve crafted pieces produce three 2x2 assemblies and leave three feed units.");
    auto feed = request("P", "sized-sheet-feed", "feed_broad_press");
    feed.emplace("target", V(bed_id));
    feed.emplace("generation", V(bed_generation));
    run.accept("P", feed);
    const auto fed = run.world->snapshot();
    const auto work_id = fed.state.material.dropped_material.at({0, 0, 0}).work_lots.front().id;
    check(codec_restore(source.profile, fed,
              "The sized broad lot survives a fresh checkpoint.") != nullptr,
        "The 2x2 bed holds one located three-stock sheet lot.");
    auto fit = request("P", "sized-crank-fit", "attach_hand_crank");
    fit.emplace("target", V(slide_id));
    fit.emplace("generation", V(slide_generation));
    fit.emplace("crank", V(crank.id));
    fit.emplace("crank_generation", V(crank.generation));
    fit.emplace("port", V(point(6, 4, 0)));
    fit.emplace("face", V(point(1, 0, 0)));
    run.accept("P", fit);
    const w::ObserveActor held_actor = [&run](const std::string& actor)
            -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, run.p, 1, true, 4};
    };
    for (int index = 0; index < 6; ++index) {
        auto pulse = request("P", "sized-crank-pulse-" + std::to_string(index),
            "operate_hand_crank");
        pulse.emplace("target", V(slide_id));
        pulse.emplace("generation", V(slide_generation));
        pulse.emplace("crank", V(crank.id));
        pulse.emplace("crank_generation", V(crank.generation));
        pulse.emplace("port", V(point(6, 4, 0)));
        pulse.emplace("face", V(point(1, 0, 0)));
        run.accept("P", pulse);
        check(run.world->tick(held_actor).error == w::TransactionError::none,
            "The fitted crank advances the slide's native phase and contact.");
    }
    const auto formed = run.world->snapshot();
    check(formed.state.material.dropped_material.at({0, 0, 0}).sheets.size() == 1,
        "Two crank contacts form one broad sheet at the sized workbed.");
    check(formed.state.material.dropped_material.at({0, 0, 0}).sheets.front().id == work_id,
        "The sized slide's sheet retains its original work identity.");
    check(codec_restore(source.profile, formed,
              "The sized slide's completed sheet survives replay and checkpoint decoding.") != nullptr,
        "A single powered slide forms the same twelve-mass broad sheet.");
    auto forged = formed;
    forged.state.press_progress.at(work_id).automatic_remaining_ticks = 1;
    check(!w::World::restore("press-feed", source.profile, forged),
        "The sized slide's recorded work cannot be removed from restored history.");
}
} // namespace

int main() {
    try {
        one_slide_broad_sheet_custody();
        std::cout << "press_feed_world_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "press_feed_world_test: " << error.what() << '\n';
        return 1;
    }
}
