#include "factory/screw_drive.hpp"

#include <algorithm>
#include <numeric>
#include <utility>

namespace factory::screw_drive {
namespace k = geared_cycle;
namespace g = mechanics;
namespace {
static_assert(maximum_turns + k::maximum_intervals < k::maximum_teeth);
static_assert(k::maximum_denominator <= 1000000 && k::maximum_intervals <= 256);
static_assert(g::maximum_dimension <= 4096 && g::maximum_coordinate <= 1000000000);
std::uint64_t magnitude(Integer value) noexcept {
    const auto bits = static_cast<std::uint64_t>(value);
    return value < 0 ? std::uint64_t{0} - bits : bits;
}
Fraction reduced(Fraction value) noexcept {
    const auto divisor = static_cast<Integer>(std::gcd(magnitude(value.numerator), static_cast<std::uint64_t>(value.denominator)));
    return {value.numerator / divisor, value.denominator / divisor};
}
using Nuts = std::variant<Refusal, std::vector<Nut>>;
Nuts validate(const Profile& profile) {
    if (profile.limit_turns < 1 || profile.limit_turns > maximum_turns || profile.nuts.empty() || profile.nuts.size() > maximum_nuts)
        return Refusal{Error::invalid_profile, {}, 0};
    auto nuts = profile.nuts;
    for (const auto& nut : nuts) {
        if (nut.id == 0 || static_cast<std::size_t>(nut.axis) >= 3 || nut.lead == 0 ||
            nut.lead < -g::maximum_dimension || nut.lead > g::maximum_dimension)
            return Refusal{Error::invalid_nut, {}, nut.id};
        for (const auto coordinate : nut.origin)
            if (coordinate < -g::maximum_coordinate || coordinate > g::maximum_coordinate)
                return Refusal{Error::invalid_nut, {}, nut.id};
        const Integer end = nut.origin[static_cast<std::size_t>(nut.axis)] + nut.lead * profile.limit_turns;
        if (end < -g::maximum_coordinate || end > g::maximum_coordinate)
            return Refusal{Error::invalid_nut, {}, nut.id};
    }
    std::sort(nuts.begin(), nuts.end(), [](const auto& a, const auto& b) { return a.id < b.id; });
    for (std::size_t i = 1; i < nuts.size(); ++i)
        if (nuts[i - 1].id == nuts[i].id) return Refusal{Error::duplicate_nut, {}, nuts[i].id};
    return nuts;
}
std::optional<Refusal> validate_turns(const Profile& profile, Turns turns) {
    const auto checked = k::prepare(k::maximum_teeth, turns, {0, 1});
    if (const auto* error = std::get_if<k::Error>(&checked)) return Refusal{Error::invalid_turns, *error, 0};
    if (turns.numerator > profile.limit_turns * turns.denominator) return Refusal{Error::invalid_turns, {}, 0};
    return std::nullopt;
}
std::vector<NutPose> poses(const std::vector<Nut>& nuts, Turns turns) {
    std::vector<NutPose> result;
    for (const auto& nut : nuts) {
        NutPose pose{nut.id, {}};
        for (std::size_t axis = 0; axis < 3; ++axis) pose.position[axis] = {nut.origin[axis], 1};
        const auto axis = static_cast<std::size_t>(nut.axis);
        pose.position[axis] = reduced({nut.origin[axis] * turns.denominator + nut.lead * turns.numerator, turns.denominator});
        result.push_back(pose);
    }
    return result;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_nut: return "invalid_nut";
        case Error::duplicate_nut: return "duplicate_nut";
        case Error::invalid_turns: return "invalid_turns";
        case Error::clock_refused: return "clock_refused";
        case Error::inconsistent_clock: return "inconsistent_clock";
    }
    return "unknown";
}
const char* stop_name(Stop stop) noexcept {
    switch (stop) {
        case Stop::unpowered: return "unpowered";
        case Stop::stopped: return "stopped";
        case Stop::lower_end: return "lower_end";
        case Stop::upper_end: return "upper_end";
    }
    return "unknown";
}
Sample sample(const Profile& profile, Turns turns) {
    const auto checked = validate(profile);
    if (const auto* error = std::get_if<Refusal>(&checked)) return *error;
    if (const auto error = validate_turns(profile, turns)) return *error;
    return poses(std::get<std::vector<Nut>>(checked), turns);
}

Plan prepare(const Profile& profile, Turns turns, const Observation& observation) {
    auto checked = validate(profile);
    if (const auto* error = std::get_if<Refusal>(&checked)) return *error;
    if (const auto error = validate_turns(profile, turns)) return *error;
    const auto checked_rate = k::prepare(k::maximum_teeth, {}, observation.rate, false);
    if (const auto* error = std::get_if<k::Error>(&checked_rate)) return Refusal{Error::clock_refused, *error, 0};
    const auto& nuts = std::get<std::vector<Nut>>(checked);
    const auto rate = reduced(observation.rate);
    if (!observation.powered || rate.numerator == 0)
        return Hold{turns, poses(nuts, turns), observation.powered ? Stop::stopped : Stop::unpowered};
    const int direction = rate.numerator > 0 ? 1 : -1;
    const Integer boundary = direction > 0 ? profile.limit_turns : 0;
    const Integer distance = direction > 0 ? boundary * turns.denominator - turns.numerator : turns.numerator;
    if (distance == 0) return Hold{turns, poses(nuts, turns), direction > 0 ? Stop::upper_end : Stop::lower_end};
    // Validated bounds keep stop-time products below 4.1e15 and all pose
    // products below 1.1e15. Normalize before ever negating a source numerator.
    const Integer speed = direction > 0 ? rate.numerator : -rate.numerator;
    const Integer time_numerator = distance * rate.denominator;
    const Integer time_denominator = speed * turns.denominator;
    const bool reaches = time_numerator <= time_denominator;
    const auto applied_rate = reaches ? reduced({direction * distance, turns.denominator}) : rate;
    auto clock = k::prepare(k::maximum_teeth, turns, applied_rate);
    if (const auto* error = std::get_if<k::Error>(&clock)) return Refusal{Error::clock_refused, *error, 0};
    auto motion = std::get<k::Prepared>(std::move(clock));
    if (motion.next.numerator > profile.limit_turns * motion.next.denominator)
        return Refusal{Error::inconsistent_clock, {}, 0};
    Advance result{motion.next, poses(nuts, motion.next), {}, {}};
    for (const auto& crossing : motion.crossings) {
        auto at = crossing.at;
        if (reaches) {
            const Integer travelled = direction > 0 ? crossing.tooth * turns.denominator - turns.numerator
                                                   : turns.numerator - crossing.tooth * turns.denominator;
            at = reduced({travelled * rate.denominator, time_denominator});
        }
        result.crossings.push_back({crossing.tooth, crossing.direction, at});
    }
    if (reaches) result.endstop = Endstop{direction > 0 ? End::upper : End::lower, reduced({time_numerator, time_denominator})};
    return result;
}
}  // namespace factory::screw_drive
