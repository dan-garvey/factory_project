#include "factory/world.hpp"

#include <algorithm>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace world = factory::world;
namespace mechanical = factory::mechanics;
namespace stationary = factory::stationary;

int main(int argc, char** argv) {
    constexpr std::size_t machine_count = 1000;
    world::Profile profile;
    profile.material = {1, 32, 2};
    profile.actors = {"P"};
    profile.finite_parts = {{{stationary::Role::waterwheel, 0, 0}, machine_count}};
    world::State seed;
    seed.material.cargo.emplace("P", factory::materials::Cargo{});
    seed.kits.emplace("P", stationary::Kit{});
    seed.topology.drive_enabled = true;
    for (std::size_t index = 0; index < machine_count; ++index) {
        const auto id = "scale-wheel-" + std::to_string(index);
        const auto x = static_cast<mechanical::Integer>(index % 40) * 16;
        const auto z = static_cast<mechanical::Integer>(index / 40) * 16;
        const factory::waterwheel::Sample sample{0, -1000, 200, 0};
        profile.water.emplace(std::array<mechanical::Integer, 2>{x, z}, sample);
        seed.topology.parts.push_back({{id, mechanical::Kind::hub, {x, 0, z},
            mechanical::Axis::z, 0, 0}, 1, stationary::Role::waterwheel});
        const auto rate = factory::waterwheel::rate(121, 600, mechanical::Axis::z, sample);
        if (!rate || rate->numerator == 0)
            throw std::runtime_error("The trusted flow does not rotate the fixture wheel.");
        seed.topology.sources.push_back({id, *rate});
        seed.issued_entities.emplace(id, 1);
    }
    auto authority = world::World::create("thousand-water-site", profile, seed);
    if (!authority) throw std::runtime_error("The World rejected a conserved thousand-wheel site.");
    const auto original = authority->snapshot();
    if (original.state.topology.parts.size() != machine_count ||
        original.state.issued_entities.size() != machine_count ||
        original.state.kits.at("P") != stationary::Kit{})
        throw std::runtime_error("Machine placement was not conserved in the one World.");
    const auto drive = world::drive_power(original.state.topology);
    const auto& motion = drive.mechanical;
    if (!motion.accepted() || motion.motion.size() != machine_count ||
        drive.load.size() != machine_count)
        throw std::runtime_error("The placed wheels did not have one native motion result each.");
    for (const auto& [id, value] : motion.motion)
        if (value.state != mechanical::MotionState::rotating ||
            drive.load.at(id).overloaded || drive.load.at(id).capacity <= 0 ||
            drive.load.at(id).impact != 0)
            throw std::runtime_error("A placed native wheel lost confirmed rotation: " + id);

    const auto advanced = authority->tick();
    if (advanced.error != world::TransactionError::none ||
        authority->snapshot().state.topology != original.state.topology ||
        authority->snapshot().state.material != original.state.material)
        throw std::runtime_error("A native step changed placed machines or material custody.");

    if (argc > 1 && std::string(argv[1]) == "--benchmark") {
        const auto snapshot = authority->snapshot();
        const auto measure = [&](const char* stage, auto&& operation) {
            std::vector<double> samples;
            samples.reserve(20);
            for (int sample = 0; sample < 20; ++sample) {
                const auto start = std::chrono::steady_clock::now();
                operation();
                const auto end = std::chrono::steady_clock::now();
                samples.push_back(std::chrono::duration<double, std::milli>(end - start).count());
            }
            std::sort(samples.begin(), samples.end());
            std::cout << "WORLD_THOUSAND_STAGE name=" << stage
                      << " median_ms=" << samples[samples.size() / 2]
                      << " p95_ms=" << samples[static_cast<std::size_t>(samples.size() * 0.95)] << '\n';
        };
        measure("validate", [&] {
            if (!world::validate(profile, snapshot)) throw std::runtime_error("Measured validation failed.");
        });
        measure("drive_power", [&] {
            if (!world::drive_power(snapshot.state.topology).mechanical.accepted())
                throw std::runtime_error("Measured drive derivation failed.");
        });
        measure("machine_power", [&] {
            const auto power = world::machine_power(snapshot.state.topology);
            if (power.processor) throw std::runtime_error("Wheel-only fixture fabricated a press.");
        });
        measure("material_path", [&] {
            const auto path = world::material_path(snapshot.state.topology);
            if (path.collector_present || path.processor_present || path.belt_present)
                throw std::runtime_error("Wheel-only fixture fabricated a material machine.");
        });
        std::vector<double> milliseconds;
        milliseconds.reserve(20);
        for (int sample = 0; sample < 20; ++sample) {
            const auto start = std::chrono::steady_clock::now();
            const auto step = authority->tick();
            const auto end = std::chrono::steady_clock::now();
            if (step.error != world::TransactionError::none)
                throw std::runtime_error("A measured native step failed.");
            milliseconds.push_back(std::chrono::duration<double, std::milli>(end - start).count());
        }
        std::sort(milliseconds.begin(), milliseconds.end());
        std::cout << "WORLD_THOUSAND active=" << machine_count
                  << " sampled_ticks=" << milliseconds.size()
                  << " median_ms=" << milliseconds[milliseconds.size() / 2]
                  << " p95_ms=" << milliseconds[static_cast<std::size_t>(milliseconds.size() * 0.95)] << '\n';
    }
    std::cout << "WORLD_SCALE_CHECK active=" << machine_count << " passed\n";
}
