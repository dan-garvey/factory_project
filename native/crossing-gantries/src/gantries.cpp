#include "factory/gantries.hpp"

#include <array>
#include <numeric>

namespace factory::gantries {
namespace {
namespace m = mechanisms;
namespace c = clearance;
constexpr std::array<Definition, 3> definitions{{
    {Puzzle::bridge, "bridge", "A crossing too fast to see at its endpoints",
     "The two rails meet, but their carriages need not occupy the same height.",
     {{1, 1, 1}, {-4, 0, 0}, {4, 0, 0}}, {{1, 1, 1}, {0, 0, -4}, {0, 0, 4}}, false, 2},
    {Puzzle::crossing, "crossing", "Two fixed cycles share one aisle",
     "Use a bridge, or key one fixed cycle so each carriage has the crossing to itself.",
     {{2, 4, 2}, {-4, 0, 0}, {4, 0, 0}}, {{2, 4, 2}, {0, 0, -4}, {0, 0, 4}}, true, 2},
    {Puzzle::freight, "freight", "The longer rail returns later",
     "The second cycle lasts 18 teeth and the first lasts 12. Check their full common repeat.",
     {{2, 4, 2}, {-4, 0, 0}, {4, 0, 0}}, {{4, 6, 2}, {0, 0, -6}, {0, 0, 6}}, true, 2},
}};

bool position(const Track& track, m::Tooth tooth, c::Coordinate height, c::Point& point) noexcept {
    m::Pose pose;
    if (m::sample(track.slide, {tooth}, pose) != m::Error::none) return false;
    for (std::size_t axis = 0; axis < 3; ++axis) {
        const auto distance = track.work[axis] - track.dock[axis];
        const auto denominator = static_cast<c::Coordinate>(pose.denominator);
        if (denominator <= 0 || distance % denominator != 0) return false;
        point[axis] = track.dock[axis] + (distance / denominator) * static_cast<c::Coordinate>(pose.numerator);
    }
    point[1] += height;
    return true;
}

c::Box body(const c::Point& point) noexcept {
    return {{point[0] - 1, point[1], point[2] - 1}, {point[0] + 1, point[1] + 2, point[2] + 1}};
}
}  // namespace

std::span<const Definition> catalogue() noexcept { return definitions; }

const Definition* find(std::string_view id) noexcept {
    for (const auto& definition : definitions) if (definition.id == id) return &definition;
    return nullptr;
}

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::invalid_puzzle: return "invalid_puzzle";
        case Error::invalid_settings: return "invalid_settings";
        case Error::invalid_geometry: return "invalid_geometry";
    }
    return "unknown";
}

Report evaluate(Puzzle puzzle, Settings settings) noexcept {
    const Definition* definition = nullptr;
    for (const auto& candidate : definitions) if (candidate.puzzle == puzzle) definition = &candidate;
    if (!definition) return {Error::invalid_puzzle, 0, std::nullopt};
    m::Tooth first_length{}, second_length{};
    if (m::cycle_length(definition->first.slide, first_length) != m::Error::none ||
        m::cycle_length(definition->second.slide, second_length) != m::Error::none)
        return {Error::invalid_geometry, 0, std::nullopt};
    if (settings.height < 0 || settings.height > definition->maximum_height || settings.offset >= second_length ||
        (!definition->phase_adjustable && settings.offset != 0)) return {Error::invalid_settings, 0, std::nullopt};

    // Only the three immutable profiles enter this calculation: lengths <=18,
    // period <=36, coordinates <=8 and per-interval displacements <=8. No
    // externally supplied duration or geometry can overflow this arithmetic.
    const auto period = std::lcm(first_length, second_length);
    for (m::Tooth tick = 0; tick < period; ++tick) {
        c::Point a0, a1, b0, b1;
        if (!position(definition->first, tick % first_length, 0, a0) ||
            !position(definition->first, (tick + 1) % first_length, 0, a1) ||
            !position(definition->second, (tick + settings.offset) % second_length, settings.height, b0) ||
            !position(definition->second, (tick + settings.offset + 1) % second_length, settings.height, b1))
            return {Error::invalid_geometry, 0, std::nullopt};
        c::Point relative;
        for (std::size_t axis = 0; axis < 3; ++axis) relative[axis] = (a1[axis] - a0[axis]) - (b1[axis] - b0[axis]);
        const std::array<c::Obstacle, 1> obstacles{{{2, body(b0)}}};
        const auto swept = c::sweep(body(a0), relative, obstacles);
        if (swept.error != c::Error::none) return {Error::invalid_geometry, 0, std::nullopt};
        if (swept.hit) return {Error::none, period, Conflict{tick, swept.hit->time, swept.hit->initially_overlapping}};
    }
    return {Error::none, period, std::nullopt};
}
}  // namespace factory::gantries
