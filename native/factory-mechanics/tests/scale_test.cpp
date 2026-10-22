#include "factory/mechanics.hpp"

#include <algorithm>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace mechanical = factory::mechanics;

int main(int argc, char** argv) {
    const std::vector<mechanical::Part> long_drive{
        {"long-shaft", mechanical::Kind::shaft, {0, 0, 0}, mechanical::Axis::z, 0, 4096},
        {"far-drive", mechanical::Kind::hub, {0, 0, 4096}, mechanical::Axis::z, 0, 0}};
    const auto reach = mechanical::evaluate(long_drive, {{"far-drive", {1, 1}}});
    if (!reach.accepted() || reach.engagements.size() != 1 ||
        reach.motion.at("long-shaft").state != mechanical::MotionState::rotating)
        throw std::runtime_error("A maximum-span shaft lost its physical contact.");
    const std::vector<mechanical::Part> large_gears{
        {"gear-a", mechanical::Kind::gear, {0, 0, 0}, mechanical::Axis::z, 4000, 0},
        {"gear-b", mechanical::Kind::gear, {7999, 0, 0}, mechanical::Axis::z, 4000, 0}};
    if (mechanical::evaluate(large_gears, {}).error != mechanical::Error::overlapping_gears)
        throw std::runtime_error("A maximum-radius cog overlap escaped the spatial contact scan.");

    constexpr std::size_t machine_count = 1000;
    std::vector<mechanical::Part> parts;
    std::vector<mechanical::Drive> sources;
    parts.reserve(machine_count);
    sources.reserve(machine_count);
    for (std::size_t index = 0; index < machine_count; ++index) {
        // One physical powered hub per separate machine tile. Each source is
        // a registered drive observation, so every hub must actually rotate.
        const auto id = "machine-" + std::to_string(index);
        const auto x = static_cast<mechanical::Integer>(index % 40) * 8;
        const auto z = static_cast<mechanical::Integer>(index / 40) * 8;
        parts.push_back({id, mechanical::Kind::hub, {x, 0, z}, mechanical::Axis::z, 0, 0});
        sources.push_back({id, {1, 1}});
    }
    const auto result = mechanical::evaluate(parts, sources);
    if (!result.accepted() || result.motion.size() != machine_count ||
        result.components.size() != machine_count || !result.engagements.empty())
        throw std::runtime_error("The thousand powered machines did not retain distinct physical identities.");
    for (const auto& [id, motion] : result.motion)
        if (motion.state != mechanical::MotionState::rotating || motion.rate != mechanical::Rate{1, 1})
            throw std::runtime_error("An authority-sourced machine lost its actual rotation: " + id);

    std::reverse(parts.begin(), parts.end());
    if (mechanical::evaluate(parts, sources) != result)
        throw std::runtime_error("The thousand-machine result depends on input order.");

    parts.resize(mechanical::maximum_parts + 1);
    for (std::size_t index = machine_count; index < parts.size(); ++index)
        parts[index] = {"extra-" + std::to_string(index), mechanical::Kind::hub,
                        {static_cast<mechanical::Integer>(index) * 8, 0, 0}, mechanical::Axis::z, 0, 0};
    const auto rejected = mechanical::evaluate(parts, {});
    if (rejected.error != mechanical::Error::too_many_parts || !rejected.motion.empty() ||
        !rejected.engagements.empty() || !rejected.components.empty())
        throw std::runtime_error("The bounded evaluator accepted or partially published an excessive graph.");

    if (argc > 1 && std::string(argv[1]) == "--benchmark") {
        parts.resize(machine_count);
        std::vector<double> milliseconds;
        milliseconds.reserve(60);
        for (int sample = 0; sample < 60; ++sample) {
            const auto start = std::chrono::steady_clock::now();
            const auto measured = mechanical::evaluate(parts, sources);
            const auto end = std::chrono::steady_clock::now();
            if (!measured.accepted() || measured.motion.size() != machine_count)
                throw std::runtime_error("The measured solve failed.");
            milliseconds.push_back(std::chrono::duration<double, std::milli>(end - start).count());
        }
        std::sort(milliseconds.begin(), milliseconds.end());
        std::cout << "MECHANICS_THOUSAND powered=" << machine_count
                  << " samples=" << milliseconds.size()
                  << " median_ms=" << milliseconds[milliseconds.size() / 2]
                  << " p95_ms=" << milliseconds[static_cast<std::size_t>(milliseconds.size() * 0.95)] << '\n';
    }
    std::cout << "MECHANICS_SCALE_CHECK powered=" << machine_count << " passed\n";
}
