#include "factory/gear_puzzles.hpp"

namespace factory::gear_puzzles {
namespace m = mechanics;
namespace {
m::Part gear(const char* id, m::Point center, m::Integer teeth) {
    return {id, m::Kind::gear, center, m::Axis::z, teeth, 0};
}

std::vector<m::Part> endpoints(m::Integer x, m::Integer teeth, m::Integer plane) {
    return {gear("input", {0, 0, 0}, 20), gear("output", {x, 0, plane}, teeth),
        {"input-shaft", m::Kind::shaft, {0, 0, 0}, m::Axis::z, 0, 1},
        {"output-shaft", m::Kind::shaft, {x, 0, plane}, m::Axis::z, 0, 1},
        {"drive", m::Kind::hub, {0, 0, -1}, m::Axis::z, 0, 0},
        {"sink", m::Kind::hub, {x, 0, plane + 1}, m::Axis::z, 0, 0}};
}

const std::array<Challenge, 3>& entries() {
    static const auto idler_fixed = endpoints(100, 40, 0);
    static const auto bend_fixed = endpoints(88, 20, 0);
    static const auto compound_fixed = [] {
        auto parts = endpoints(100, 20, 2);
        parts.push_back(gear("large", {60, 0, 0}, 40));
        parts.push_back(gear("small", {60, 0, 2}, 20));
        return parts;
    }();
    static const std::array<Challenge, 3> challenges{{
        {"idler", "One more mesh",
         "Drive the output in the input direction at half its speed using the one carried idler.",
         {1, 2}, idler_fixed, {Slot{m::Kind::gear, 20, 0}, std::nullopt}, {std::nullopt, std::nullopt}},
        {"bend", "Three turns around the bend",
         "Place both gears to reverse the output at equal speed. Route above or below the input line.",
         {-1, 1}, bend_fixed, {Slot{m::Kind::gear, 20, 0}, Slot{m::Kind::gear, 20, 0}},
         {m::Point{40, 0, 0}, m::Point{40, 40, 0}}},
        {"compound", "The missing axial bridge",
         "Join the large and small compound gears across their two planes. Target forward half-speed output.",
         {1, 2}, compound_fixed, {Slot{m::Kind::shaft, 0, 1}, std::nullopt},
         {m::Point{60, 0, 0}, std::nullopt}},
    }};
    return challenges;
}
}  // namespace

std::span<const Challenge> catalogue() { return entries(); }

const Challenge* find(std::string_view id) {
    for (const auto& challenge : entries()) if (challenge.id == id) return &challenge;
    return nullptr;
}

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::unknown_challenge: return "unknown_challenge";
        case Error::unavailable_part: return "unavailable_part";
        case Error::outside_site: return "outside_site";
        case Error::invalid_geometry: return "invalid_geometry";
    }
    return "unknown";
}

Report inspect(std::string_view id, const Placements& placements) {
    const auto* challenge = find(id);
    if (!challenge) return {Error::unknown_challenge};
    Report report;
    report.required = challenge->required;
    std::vector<m::Part> parts(challenge->fixed.begin(), challenge->fixed.end());
    for (std::size_t i = 0; i < placements.size(); ++i) {
        if (!placements[i]) continue;
        if (!challenge->kit[i]) { report.error = Error::unavailable_part; return report; }
        const auto point = *placements[i];
        for (std::size_t axis = 0; axis < point.size(); ++axis) {
            if (point[axis] < site_minimum[axis] || point[axis] > site_maximum[axis]) {
                report.error = Error::outside_site;
                return report;
            }
        }
        const auto slot = *challenge->kit[i];
        parts.push_back({"part-" + std::to_string(i + 1), slot.kind, point, m::Axis::z, slot.teeth, slot.half_span});
    }
    report.derivation = m::evaluate(parts, {{"drive", {1, 1}}});
    if (!report.derivation.accepted()) { report.error = Error::invalid_geometry; return report; }
    const auto actual = report.derivation.motion.find("sink");
    if (actual == report.derivation.motion.end()) { report.error = Error::invalid_geometry; return report; }
    report.actual = actual->second;
    return report;
}
}  // namespace factory::gear_puzzles
