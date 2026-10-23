#include "factory/checkpoint.hpp"
#include "factory/world.hpp"

#include <algorithm>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

namespace w = factory::world;
namespace a = factory::assembly;
namespace g = factory::mechanics;
namespace m = factory::materials;
namespace s = factory::stationary;
using V = factory::values::Value;

struct ProductiveSite {
    w::Profile profile;
    w::Snapshot snapshot;
};

ProductiveSite productive_site() {
    w::Profile profile;
    profile.material = {1, 2, 2};
    profile.material.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    profile.material.timber_sites = {{"tree", {{12, 0, 12}, 40}}};
    profile.material.hand_carry_capacity = 100;
    profile.initial_units = 100;
    profile.actors = {"P"};
    profile.foundation_parts = 9;
    profile.starting_foundation_kits = {{"P", 0}};
    profile.landing_pod_center = g::Point{0, 0, 1000};
    profile.build_reach = 10000;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 4}};
    w::State seed;
    seed.material.initial_units = profile.initial_units;
    seed.material.stock.source = profile.initial_units;
    seed.material.timber_remaining = {{"tree", 40}};
    seed.material.cargo.emplace("P", m::Cargo{});
    seed.kits.emplace("P", s::Kit{});
    seed.foundation_kits.emplace("P", 0);
    seed.topology.drive_enabled = true;
    seed.landing_pod = w::LandingPod{"landing-pod", *profile.landing_pod_center, 1};
    seed.fabrication_hub = w::FabricationHub{"pod-fabrication-hub",
        w::landing_hub_center(*profile.landing_pod_center), 1};
    seed.hand_crank = w::HandCrank{"pod-hand-crank", 1, std::nullopt};
    seed.freight_beacon = w::FreightBeacon{"first-freight-beacon",
        w::landing_freight_center(*profile.landing_pod_center), 1};
    seed.issued_entities = {{"landing-pod", 1}, {"pod-fabrication-hub", 1},
        {"pod-hand-crank", 1}, {"first-freight-beacon", 1}};
    const auto deck = w::landing_deck_centers(*profile.landing_pod_center);
    for (std::size_t index = 0; index < deck.size(); ++index) {
        const auto id = "pod-floor-" + std::to_string(index);
        seed.foundations.emplace(id, w::Foundation{deck[index], 1});
        seed.issued_entities.emplace(id, 1);
    }
    for (const auto base : {g::Integer{800}, g::Integer{840}}) {
        profile.collector_faces.push_back({{base, 0, 0}, {-1, 0, 0}});
        for (const auto& [suffix, height, z] : {
                std::tuple{"collector-wheel", g::Integer{0}, g::Integer{0}},
                std::tuple{"press-wheel", g::Integer{4}, g::Integer{16}}}) {
            const auto id = std::to_string(base) + suffix;
            const factory::waterwheel::Sample sample{0, -1000, 0, -600};
            profile.water.emplace(std::array<g::Integer, 2>{base + 4, z}, sample);
            const auto rate = factory::waterwheel::rate(height * 100 + 121, 600,
                g::Axis::x, sample);
            if (!rate || rate->numerator == 0)
                throw std::runtime_error("A modular source wheel did not turn.");
            seed.topology.parts.push_back({{id, g::Kind::hub, {base + 4, height, z},
                g::Axis::x, 0, 0}, 1, s::Role::waterwheel});
            seed.topology.sources.push_back({id, *rate});
            seed.issued_entities.emplace(id, 1);
        }
    }
    auto world = w::World::create("mixed-scale", profile, seed);
    if (!world) throw std::runtime_error("The four-source modular startup was rejected.");
    const w::ObserveActor nearby = [](const std::string& actor) -> std::optional<factory::authority::ActorCut> {
        return factory::authority::ActorCut{actor, {0, 0, 0}, 1, true, 10000};
    };
    int request = 0;
    const auto issue = [&](const char* action, V::Object fields) -> V::Object {
        fields.emplace("context", V("mixed-scale"));
        fields.emplace("client", V("P-client"));
        fields.emplace("request", V("scale-setup-" + std::to_string(++request)));
        fields.emplace("actor", V("P"));
        fields.emplace("action", V(action));
        const auto result = world->command({"P", "P-client"}, fields, nearby);
        if (!result.completed() || !result.result ||
            !std::get<bool>(result.result->at("accepted").storage()))
            throw std::runtime_error(std::string("Mixed site setup refused ") + action + ": " +
                (result.result ? std::get<std::string>(result.result->at("reason").storage()) : "no result"));
        return *result.result;
    };
    for (int index = 0; index < 30; ++index) issue("harvest_source", {{"target", V("tree")}});
    for (int index = 0; index < 10; ++index) issue("harvest_source", {{"target", V("ore")}});
    const auto place = [&](const char* component, g::Point center) -> V::Object {
        issue("craft_component", {{"target", V("pod-fabrication-hub")},
            {"generation", V(g::Integer{1})}, {"component", V(component)}});
        return issue("place_component", {{"component", V(component)},
            {"center", V(V::Array{V(center[0]), V(center[1]), V(center[2])})}});
    };
    std::vector<std::pair<std::string, g::Integer>> presses;
    std::vector<std::string> driven_shafts;
    for (const auto base : {g::Integer{800}, g::Integer{840}}) {
        place("wooden_frame", {base, 0, 0});
        place("tool_mount", {base - 1, 0, 0});
        place("cutting_edge", {base - 2, 0, 0});
        place("receiver_tray", {base, 0, 1});
        driven_shafts.push_back(std::get<std::string>(
            place("wooden_shaft", {base + 1, 0, 0}).at("entity").storage()));
        const auto frame = place("wooden_frame", {base, 0, 16});
        presses.emplace_back(std::get<std::string>(frame.at("entity").storage()),
            std::get<g::Integer>(frame.at("generation").storage()));
        place("anvil", {base, 1, 16});
        place("ram_face", {base, 2, 16});
        place("sliding_guide", {base, 3, 16});
        place("tool_mount", {base, 4, 16});
        driven_shafts.push_back(std::get<std::string>(
            place("wooden_shaft", {base + 1, 4, 16}).at("entity").storage()));
        place("wooden_cog", {base + 2, 4, 16});
    }
    const auto power = w::drive_power(profile, world->snapshot().state);
    if (!power.mechanical.accepted()) throw std::runtime_error("The modular startup graph was rejected.");
    for (const auto& id : driven_shafts)
        if (!power.mechanical.motion.contains(id) ||
            power.mechanical.motion.at(id).state != g::MotionState::rotating)
            throw std::runtime_error("A modular machine shaft stopped: " + id);
    const auto before = world->snapshot();
    if (world->tick().error != w::TransactionError::none ||
        world->snapshot().state.material.stock.source != before.state.material.stock.source - 2)
        throw std::runtime_error("Both modular collectors did not produce independently.");
    for (std::size_t index = 0; index < presses.size(); ++index) {
        const auto base = index == 0 ? g::Integer{800} : g::Integer{840};
        issue("pickup_material", {{"center", V(V::Array{V(base), V(g::Integer{0}), V(g::Integer{1})})},
            {"expected", V(V::Object{{"raw", V(g::Integer{1})}, {"products", V(g::Integer{0})},
                {"work_lots", V(V::Array{})}})}});
        issue("feed_press", {{"target", V(presses[index].first)},
            {"generation", V(presses[index].second)},
            {"entry", V(V::Array{V(base + 1), V(g::Integer{1}), V(g::Integer{16})})}});
    }
    return {std::move(profile), world->snapshot()};
}

void powered_cog_world(bool benchmark) {
    constexpr int cog_count = 400;
    auto site = productive_site();
    auto& profile = site.profile;
    auto& seed = site.snapshot.state;
    for (int index = 0; index < cog_count; ++index) {
        ++profile.finite_parts[{s::Role::waterwheel, 0, 0}];
        ++profile.finite_parts[{s::Role::shaft, 0, 2}];
        ++profile.finite_parts[{s::Role::gear, 2, 0}];
        const g::Integer x = (index % 20) * 32;
        const g::Integer z = (index / 20) * 32;
        const auto prefix = "scale-cog-" + std::to_string(index);
        const auto wheel = prefix + "-wheel";
        const auto shaft = prefix + "-shaft";
        const auto cog = prefix + "-gear";
        const factory::waterwheel::Sample sample{0, -1000, 200, 0};
        const auto rate = factory::waterwheel::rate(121, 600, g::Axis::z, sample);
        if (!rate || rate->numerator == 0)
            throw std::runtime_error("The trusted water sample did not rotate a cog source.");
        profile.water.emplace(std::array<g::Integer, 2>{x, z}, sample);
        seed.topology.parts.push_back({{wheel, g::Kind::hub, {x, 0, z},
            g::Axis::z, 0, 0}, 1, s::Role::waterwheel});
        seed.topology.parts.push_back({{shaft, g::Kind::shaft, {x, 0, z + 4},
            g::Axis::z, 0, 2}, 1, s::Role::shaft});
        seed.topology.parts.push_back({{cog, g::Kind::gear, {x, 0, z + 8},
            g::Axis::z, 2, 0}, 1, s::Role::gear});
        seed.topology.sources.push_back({wheel, *rate});
        for (const auto& id : {wheel, shaft, cog}) seed.issued_entities.emplace(id, 1);
    }
    auto world = w::World::restore("mixed-scale", profile, site.snapshot);
    if (!world) throw std::runtime_error("The World rejected the mixed modular and cog site.");
    const auto initial = world->snapshot();
    const auto power = w::drive_power(profile, initial.state);
    if (!power.mechanical.accepted() || power.mechanical.motion.size() < cog_count * 3)
        throw std::runtime_error("The World lost a cog, axle, or source identity.");
    for (int index = 0; index < cog_count; ++index) {
        const auto id = "scale-cog-" + std::to_string(index) + "-gear";
        const auto found = power.mechanical.motion.find(id);
        if (found == power.mechanical.motion.end() || found->second.state != g::MotionState::rotating)
            throw std::runtime_error("A native scale cog did not rotate: " + id);
    }
    const auto encoded = w::encode_checkpoint(profile, initial);
    if (!std::holds_alternative<factory::values::Value>(encoded))
        throw std::runtime_error("The powered cog checkpoint could not encode.");
    const auto decoded = w::decode_checkpoint(profile, "mixed-scale",
        std::get<factory::values::Value>(encoded));
    if (!std::holds_alternative<w::Snapshot>(decoded) ||
        std::get<w::Snapshot>(decoded).state != initial.state)
        throw std::runtime_error("The powered cog checkpoint lost an identity.");
    if (!w::World::restore("mixed-scale", profile, std::get<w::Snapshot>(decoded)))
        throw std::runtime_error("The restored mixed World rejected its checkpoint.");
    if (world->tick().error != w::TransactionError::none ||
        !w::validate(profile, world->snapshot()))
        throw std::runtime_error("A mixed World tick lost finite custody.");
    const auto advanced = world->snapshot();
    for (const auto base : {g::Integer{800}, g::Integer{840}}) {
        const auto work = advanced.state.material.dropped_material.find({base, 1, 16});
        if (work == advanced.state.material.dropped_material.end() ||
            work->second.work_lots.size() != 1)
            throw std::runtime_error("A modular press did not start its own real work lot.");
    }
    if (benchmark) {
        const auto measure = [&](const char* stage, auto&& operation) {
            std::vector<double> samples;
            samples.reserve(100);
            for (int sample = 0; sample < 100; ++sample) {
                const auto start = std::chrono::steady_clock::now();
                operation();
                samples.push_back(std::chrono::duration<double, std::milli>(
                    std::chrono::steady_clock::now() - start).count());
            }
            std::sort(samples.begin(), samples.end());
            std::cout << "WORLD_COG_STAGE name=" << stage << " cogs=" << cog_count
                      << " samples=" << samples.size() << " median_ms=" << samples[50]
                      << " p95_ms=" << samples[94] << '\n';
        };
        measure("drive_power", [&] {
            if (!w::drive_power(profile, initial.state).mechanical.accepted())
                throw std::runtime_error("The measured cog drive was rejected.");
        });
        measure("validate", [&] {
            if (!w::validate(profile, initial))
                throw std::runtime_error("The measured cog World was rejected.");
        });
        std::vector<double> ticks;
        ticks.reserve(100);
        for (int sample = 0; sample < 100; ++sample) {
            auto fresh = w::World::restore("mixed-scale", profile, initial);
            if (!fresh) throw std::runtime_error("A measured mixed World did not restore.");
            const auto start = std::chrono::steady_clock::now();
            if (fresh->tick().error != w::TransactionError::none)
                throw std::runtime_error("The measured cog tick failed.");
            ticks.push_back(std::chrono::duration<double, std::milli>(
                std::chrono::steady_clock::now() - start).count());
        }
        std::sort(ticks.begin(), ticks.end());
        std::cout << "WORLD_COG_STAGE name=tick cogs=" << cog_count
                  << " samples=" << ticks.size() << " median_ms=" << ticks[50]
                  << " p95_ms=" << ticks[94] << '\n';
    }
    std::cout << "WORLD_COG_SCALE_CHECK rotating=" << cog_count
              << " collectors=2 presses=2 passed\n";
}

int main(int argc, char** argv) {
    w::Profile profile;
    w::State state;
    constexpr int collectors = 200;
    constexpr int presses = 100;
    int serial = 1;
    const auto add = [&](const std::string& name, m::Component kind, g::Point center) {
        state.placed_components.emplace(name, w::PlacedComponent{kind, center, serial++});
    };
    for (int index = 0; index < collectors; ++index) {
        const g::Integer x = index * 8;
        const auto name = "collector-" + std::to_string(index);
        profile.collector_faces.push_back({{x, 0, 0}, {-1, 0, 0}});
        add(name + "-frame", m::Component::wooden_frame, {x, 0, 0});
        add(name + "-mount", m::Component::tool_mount, {x - 1, 0, 0});
        add(name + "-edge", m::Component::cutting_edge, {x - 2, 0, 0});
        add(name + "-tray", m::Component::receiver_tray, {x, 0, 1});
        add(name + "-shaft", m::Component::wooden_shaft, {x + 1, 0, 0});
    }
    for (int index = 0; index < presses; ++index) {
        const g::Integer x = index * 8;
        const auto name = "press-" + std::to_string(index);
        add(name + "-frame", m::Component::wooden_frame, {x, 8, 16});
        add(name + "-anvil", m::Component::anvil, {x, 9, 16});
        add(name + "-ram", m::Component::ram_face, {x, 10, 16});
        add(name + "-guide", m::Component::sliding_guide, {x, 11, 16});
        add(name + "-mount", m::Component::tool_mount, {x, 12, 16});
        add(name + "-shaft", m::Component::wooden_shaft, {x + 1, 12, 16});
        add(name + "-cog", m::Component::wooden_cog, {x + 2, 12, 16});
    }
    profile.material = {1, 2, 2};
    profile.material.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    profile.actors = {"P"};
    profile.foundation_parts = 9;
    profile.starting_foundation_kits = {{"P", 0}};
    profile.landing_pod_center = g::Point{0, 0, 2000};
    w::State empty_site;
    empty_site.material.cargo.emplace("P", m::Cargo{});
    empty_site.kits.emplace("P", factory::stationary::Kit{});
    empty_site.foundation_kits.emplace("P", 0);
    empty_site.landing_pod = w::LandingPod{"landing-pod", *profile.landing_pod_center, 1};
    empty_site.fabrication_hub = w::FabricationHub{"pod-fabrication-hub",
        w::landing_hub_center(*profile.landing_pod_center), 1};
    empty_site.hand_crank = w::HandCrank{"pod-hand-crank", 1, std::nullopt};
    empty_site.freight_beacon = w::FreightBeacon{"first-freight-beacon",
        w::landing_freight_center(*profile.landing_pod_center), 1};
    empty_site.issued_entities = {{"landing-pod", 1}, {"pod-fabrication-hub", 1},
        {"pod-hand-crank", 1}, {"first-freight-beacon", 1}};
    const auto deck = w::landing_deck_centers(*profile.landing_pod_center);
    for (std::size_t index = 0; index < deck.size(); ++index) {
        const auto id = "pod-floor-" + std::to_string(index);
        empty_site.foundations.emplace(id, w::Foundation{deck[index], 1});
        empty_site.issued_entities.emplace(id, 1);
    }
    if (!w::World::create("modular-scale-profile", profile, empty_site))
        throw std::runtime_error("The World refused a trusted site with 200 independent collector faces.");
    const auto derived = w::drive_power(profile, state);
    if (!derived.mechanical.accepted() ||
        derived.mechanical.motion.size() != collectors * 2 + presses * 3)
        throw std::runtime_error("The mixed modular graph did not preserve each distinct drive part.");

    if (argc > 1 && std::string(argv[1]) == "--benchmark") {
        std::vector<double> samples;
        samples.reserve(20);
        for (int sample = 0; sample < 20; ++sample) {
            const auto start = std::chrono::steady_clock::now();
            if (!w::drive_power(profile, state).mechanical.accepted())
                throw std::runtime_error("The measured modular graph was rejected.");
            samples.push_back(std::chrono::duration<double, std::milli>(
                std::chrono::steady_clock::now() - start).count());
        }
        std::sort(samples.begin(), samples.end());
        std::cout << "WORLD_MODULAR_STAGE collectors=" << collectors
                  << " presses=" << presses << " parts=" << state.placed_components.size()
                  << " samples=" << samples.size() << " median_ms=" << samples[10]
                  << " p95_ms=" << samples[19] << '\n';
    }
    powered_cog_world(argc > 1 && std::string(argv[1]) == "--benchmark");
    std::cout << "WORLD_MODULAR_CHECK collectors=" << collectors
              << " presses=" << presses << " placed=" << state.placed_components.size()
              << " passed\n";
}
