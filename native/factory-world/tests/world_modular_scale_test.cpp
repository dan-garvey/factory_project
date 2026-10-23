#include "factory/world.hpp"

#include <algorithm>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace w = factory::world;
namespace a = factory::assembly;
namespace g = factory::mechanics;
namespace m = factory::materials;

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
    std::cout << "WORLD_MODULAR_CHECK collectors=" << collectors
              << " presses=" << presses << " placed=" << state.placed_components.size()
              << " passed\n";
}
