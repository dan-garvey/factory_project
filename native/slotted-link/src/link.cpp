#include "factory/slotted_link.hpp"

#include <algorithm>
#include <numeric>

namespace factory::slotted_link {
namespace g = mechanics;
namespace {
Fraction time(Coordinate distance, Coordinate total) noexcept {
    const auto divisor = std::gcd(distance, total);
    return {distance / divisor, total / divisor};
}
bool valid(const Profile& profile) noexcept {
    if (profile.lower < -g::maximum_coordinate || profile.upper > g::maximum_coordinate || profile.lower >= profile.upper ||
        profile.back < 0 || profile.back > g::maximum_dimension || profile.front < 0 || profile.front > g::maximum_dimension)
        return false;
    return profile.back + profile.front <= g::maximum_dimension &&
           profile.lower - profile.back >= -g::maximum_coordinate && profile.upper + profile.front <= g::maximum_coordinate;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_state: return "invalid_state";
        case Error::invalid_destination: return "invalid_destination";
    }
    return "unknown";
}
const char* stop_name(Stop stop) noexcept {
    switch (stop) {
        case Stop::unpowered: return "unpowered";
        case Stop::rest: return "rest";
        case Stop::lower_end: return "lower_end";
        case Stop::upper_end: return "upper_end";
    }
    return "unknown";
}
Plan prepare(const Profile& profile, const State& state, const Observation& observation) {
    if (!valid(profile)) return Error::invalid_profile;
    if (state.follower < profile.lower || state.follower > profile.upper ||
        state.pin < state.follower - profile.back || state.pin > state.follower + profile.front)
        return Error::invalid_state;
    if (observation.destination < -g::maximum_coordinate || observation.destination > g::maximum_coordinate)
        return Error::invalid_destination;
    if (!observation.powered) return Hold{state, Stop::unpowered};
    // All coordinates, gaps, differences and time numerators are bounded native
    // grid values before subtraction. No raw signed input is ever negated.
    const auto displacement = observation.destination - state.pin;
    if (displacement == 0) return Hold{state, Stop::rest};
    const int direction = displacement > 0 ? 1 : -1;
    const auto total = direction * displacement;
    const auto side = direction > 0 ? Side::positive : Side::negative;
    const auto stop = direction > 0 ? profile.upper + profile.front : profile.lower - profile.back;
    if (state.pin == stop) return Hold{state, direction > 0 ? Stop::upper_end : Stop::lower_end};
    const auto pin = direction > 0 ? std::min(observation.destination, stop) : std::max(observation.destination, stop);
    Advance result{{pin, state.follower}, {}, {}, {}};
    if (pin > state.follower + profile.front) result.next.follower = pin - profile.front;
    if (pin < state.follower - profile.back) result.next.follower = pin + profile.back;
    const auto face = direction > 0 ? state.follower + profile.front : state.follower - profile.back;
    if (direction * (pin - face) >= 0) result.contact = Contact{side, time(direction * (face - state.pin), total)};
    if (pin == stop) result.endstop = Endstop{side, time(direction * (pin - state.pin), total)};
    if (result.next.follower != state.follower)
        result.follower_motion = Span{result.contact->at, result.endstop ? result.endstop->at : Fraction{1, 1}};
    return result;
}
}  // namespace factory::slotted_link
