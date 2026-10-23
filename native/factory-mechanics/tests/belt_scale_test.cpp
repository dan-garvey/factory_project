#include "factory/mechanics.hpp"

#include <algorithm>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace g = factory::mechanics;

int main(int argc, char** argv) {
    constexpr int belts = 500;
    std::vector<g::Part> parts;
    std::vector<g::BeltSpan> spans;
    parts.reserve(belts * 2);
    spans.reserve(belts);
    for (int index = 0; index < belts; ++index) {
        const auto name = "belt-" + std::to_string(index);
        const g::Integer z = index * 16;
        parts.push_back({name + "-first", g::Kind::shaft, {0, 0, z}, g::Axis::z, 0, 2});
        parts.push_back({name + "-last", g::Kind::shaft, {76, 0, z}, g::Axis::z, 0, 2});
        spans.push_back({name, name + "-first", name + "-last"});
    }
    auto result = g::evaluate(parts, {}, spans);
    if (!result.accepted() || result.motion.size() != parts.size() ||
        result.engagements.size() != spans.size() || result.components.size() != spans.size())
        throw std::runtime_error("A disjoint bounded belt fixture was rejected.");
    std::reverse(parts.begin(), parts.end());
    std::reverse(spans.begin(), spans.end());
    for (auto& span : spans) std::swap(span.first_shaft, span.last_shaft);
    if (g::evaluate(parts, {}, spans) != result)
        throw std::runtime_error("Belt motion or engagement changed with part and endpoint order.");
    parts.push_back({"obstruction", g::Kind::hub, {4, 0, 0}, g::Axis::z, 0, 0});
    const auto blocked = g::evaluate(parts, {}, spans);
    if (blocked.error != g::Error::invalid_belt || !blocked.motion.empty() ||
        !blocked.engagements.empty() || !blocked.components.empty())
        throw std::runtime_error("An occupied tile escaped the indexed pulley refusal.");
    parts.pop_back();

    if (argc > 1 && std::string(argv[1]) == "--benchmark") {
        std::vector<double> milliseconds;
        for (int sample = 0; sample < 20; ++sample) {
            const auto start = std::chrono::steady_clock::now();
            result = g::evaluate(parts, {}, spans);
            if (!result.accepted() || result.motion.size() != parts.size())
                throw std::runtime_error("A measured bounded belt fixture was rejected.");
            milliseconds.push_back(std::chrono::duration<double, std::milli>(
                std::chrono::steady_clock::now() - start).count());
        }
        std::sort(milliseconds.begin(), milliseconds.end());
        std::cout << "BELT_SCALE belts=" << belts << " shafts=" << parts.size()
                  << " median_ms=" << milliseconds[10] << " p95_ms=" << milliseconds[19] << '\n';
    }
    std::cout << "BELT_SCALE_CHECK belts=" << belts << " shafts=" << parts.size() << " passed\n";
}
