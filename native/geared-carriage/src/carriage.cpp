#include "factory/geared_carriage.hpp"

#include <algorithm>
#include <utility>

namespace factory::geared_carriage {
namespace c = clearance;
namespace k = geared_cycle;
namespace m = mechanisms;
using I = mechanics::Integer;
namespace {
// Native contact fractions have numerator/denominator at most twice the grid
// bound; phase fractions have denominator at most one million. All comparisons
// therefore fit signed 64-bit, including two native contact fractions.
static_assert(mechanics::maximum_coordinate <= 1000000000);
static_assert(k::maximum_denominator <= 1000000);
int compare(c::Fraction a, c::Fraction b) noexcept {
    const auto left = a.numerator * b.denominator;
    const auto right = b.numerator * a.denominator;
    return left < right ? -1 : left > right ? 1 : 0;
}
I wrap(I tooth, I teeth) noexcept {
    const auto result = tooth % teeth;
    return result < 0 ? result + teeth : result;
}
std::optional<Refusal> validate(const Profile& profile, I& teeth) {
    m::Tooth count{};
    if (m::cycle_length(profile.timing, count) != m::Error::none || count > static_cast<m::Tooth>(k::maximum_teeth) ||
        static_cast<std::size_t>(profile.axis) >= 3 || profile.stroke <= 0 ||
        profile.stroke % static_cast<I>(profile.timing.travel) != 0)
        return Refusal{Error::invalid_profile, {}, c::Error::none};
    c::Point displacement{};
    displacement[static_cast<std::size_t>(profile.axis)] = profile.stroke;
    const auto range = c::sweep(profile.dock, displacement, {});
    if (range.error != c::Error::none) return Refusal{Error::invalid_profile, {}, range.error};
    teeth = static_cast<I>(count);
    return std::nullopt;
}
std::optional<Pose> cell(const Profile& profile, I base, I teeth) {
    const auto tooth = wrap(base, teeth);
    m::Pose a, b;
    if (m::sample(profile.timing, {static_cast<m::Tooth>(tooth)}, a) != m::Error::none ||
        m::sample(profile.timing, {static_cast<m::Tooth>((tooth + 1) % teeth)}, b) != m::Error::none)
        return std::nullopt;
    Pose result{profile.dock, profile.dock, {0, 1}};
    const I step = profile.stroke / static_cast<I>(profile.timing.travel);
    const auto axis = static_cast<std::size_t>(profile.axis);
    result.from.minimum[axis] += step * static_cast<I>(a.numerator);
    result.from.maximum[axis] += step * static_cast<I>(a.numerator);
    result.to.minimum[axis] += step * static_cast<I>(b.numerator);
    result.to.maximum[axis] += step * static_cast<I>(b.numerator);
    return result;
}

using Probe = std::variant<Refusal, std::optional<Contact>>;
Probe probe(const Pose& pose, I tooth, std::size_t ordinal, c::Fraction from, c::Fraction to,
            std::span<const c::Obstacle> obstacles) {
    c::Point displacement{}, reverse{};
    for (std::size_t axis = 0; axis < 3; ++axis) {
        displacement[axis] = pose.to.minimum[axis] - pose.from.minimum[axis];
        reverse[axis] = -displacement[axis];
    }
    const int direction = compare(to, from);
    const auto minimum = direction < 0 ? to : from;
    const auto maximum = direction < 0 ? from : to;
    std::optional<Contact> first;
    for (const auto& obstacle : obstacles) {
        const auto forward = c::sweep(pose.from, displacement, {&obstacle, 1});
        const auto backward = c::sweep(pose.to, reverse, {&obstacle, 1});
        if (forward.error != c::Error::none || backward.error != c::Error::none)
            return Refusal{Error::query_failure, {}, forward.error != c::Error::none ? forward.error : backward.error};
        if (!forward.hit && !backward.hit) continue;
        if (!forward.hit || !backward.hit) return Refusal{Error::inconsistent_query, {}, c::Error::none};
        const auto lower = forward.hit->time;
        const c::Fraction upper{backward.hit->time.denominator - backward.hit->time.numerator,
                                backward.hit->time.denominator};
        if (compare(lower, upper) >= 0) return Refusal{Error::inconsistent_query, {}, c::Error::none};
        const bool inside = (compare(from, lower) > 0 || (compare(from, lower) == 0 && forward.hit->initially_overlapping)) &&
                            (compare(from, upper) < 0 || (compare(from, upper) == 0 && backward.hit->initially_overlapping));
        const auto clipped_lower = compare(minimum, lower) > 0 ? minimum : lower;
        const auto clipped_upper = compare(maximum, upper) < 0 ? maximum : upper;
        if (direction == 0 ? !inside : compare(clipped_lower, clipped_upper) >= 0) continue;
        const auto contact = direction == 0 ? from : direction > 0 ? clipped_lower : clipped_upper;
        const Contact candidate{obstacle.id, ordinal, tooth, contact, inside};
        if (!first || (direction >= 0 ? compare(contact, first->fraction) < 0 : compare(contact, first->fraction) > 0) ||
            (compare(contact, first->fraction) == 0 && obstacle.id < first->obstacle)) first = candidate;
    }
    return first;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_clock: return "invalid_clock";
        case Error::invalid_obstacles: return "invalid_obstacles";
        case Error::query_failure: return "query_failure";
        case Error::inconsistent_query: return "inconsistent_query";
    }
    return "unknown";
}
const char* stop_name(Stop stop) noexcept {
    switch (stop) {
        case Stop::unpowered: return "unpowered";
        case Stop::stopped: return "stopped";
        case Stop::obstructed: return "obstructed";
    }
    return "unknown";
}

Sample sample(const Profile& profile, k::Phase phase) {
    I teeth{};
    if (const auto refusal = validate(profile, teeth)) return *refusal;
    const auto checked = k::prepare(teeth, phase, {0, 1});
    if (const auto* error = std::get_if<k::Error>(&checked)) return Refusal{Error::invalid_clock, *error, c::Error::none};
    auto result = cell(profile, phase.numerator / phase.denominator, teeth);
    if (!result) return Refusal{Error::invalid_profile, {}, c::Error::none};
    result->fraction = {phase.numerator % phase.denominator, phase.denominator};
    return *result;
}

Plan prepare(const Profile& profile, k::Phase phase, const Observation& observation) {
    I teeth{};
    if (const auto refusal = validate(profile, teeth)) return *refusal;
    auto clock = k::prepare(teeth, phase, observation.rate, observation.powered);
    if (const auto* error = std::get_if<k::Error>(&clock)) return Refusal{Error::invalid_clock, *error, c::Error::none};
    const auto validated = c::sweep(profile.dock, {}, observation.obstacles);
    if (validated.error != c::Error::none) return Refusal{Error::invalid_obstacles, {}, validated.error};
    auto proposed = std::get<k::Prepared>(std::move(clock));
    const bool moving = observation.powered && observation.rate.numerator != 0;
    const int direction = !moving || observation.rate.numerator > 0 ? 1 : -1;
    I base = phase.numerator / phase.denominator;
    c::Fraction from{phase.numerator % phase.denominator, phase.denominator};
    if (direction < 0 && from.numerator == 0) { --base; from = {1, 1}; }
    std::size_t ordinal{};
    auto query = [&](c::Fraction to) -> std::optional<Plan> {
        const auto piece = cell(profile, base, teeth);
        if (!piece) return Plan{Refusal{Error::invalid_profile, {}, c::Error::none}};
        auto result = probe(*piece, wrap(base, teeth), ordinal, from, to, observation.obstacles);
        if (const auto* refusal = std::get_if<Refusal>(&result)) return Plan{*refusal};
        if (const auto hit = std::get<std::optional<Contact>>(std::move(result))) return Plan{Hold{phase, Stop::obstructed, hit}};
        return std::nullopt;
    };
    if (!moving) {
        if (auto blocked = query(from)) return std::move(*blocked);
        return Hold{phase, observation.powered ? Stop::stopped : Stop::unpowered, {}};
    }
    for (const auto& crossing : proposed.crossings) {
        static_cast<void>(crossing);  // Every ordered boundary is one whole piece.
        if (auto blocked = query(direction > 0 ? c::Fraction{1, 1} : c::Fraction{0, 1})) return std::move(*blocked);
        base += direction;
        from = direction > 0 ? c::Fraction{0, 1} : c::Fraction{1, 1};
        ++ordinal;
    }
    const c::Fraction tail{proposed.next.numerator % proposed.next.denominator, proposed.next.denominator};
    if (tail.numerator != 0)
        if (auto blocked = query(tail)) return std::move(*blocked);
    return Step{std::move(proposed)};
}
}  // namespace factory::geared_carriage
