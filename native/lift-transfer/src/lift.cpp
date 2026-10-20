#include "factory/lift_transfer.hpp"

namespace factory::lift {
namespace m = mechanisms;
namespace {
Error validate(const Profile& profile) noexcept {
    m::Tooth length{};
    if (m::cycle_length(profile.timing, length) != m::Error::none || profile.rise <= 0 ||
        profile.rise > 2 * mechanics::maximum_coordinate ||
        profile.timing.travel > static_cast<m::Tooth>(profile.rise) ||
        profile.rise % static_cast<clearance::Coordinate>(profile.timing.travel) != 0) return Error::invalid_profile;
    if (clearance::sweep(profile.lower_box, {0, profile.rise, 0}, {}).error != clearance::Error::none)
        return Error::invalid_profile;
    return Error::none;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_phase: return "invalid_phase";
        case Error::invalid_obstacles: return "invalid_obstacles";
    }
    return "unknown";
}
const char* stop_name(Stop reason) noexcept {
    switch (reason) {
        case Stop::unpowered: return "unpowered";
        case Stop::empty_source: return "empty_source";
        case Stop::receiver_closed: return "receiver_closed";
        case Stop::missing_load: return "missing_load";
        case Stop::load_on_return: return "load_on_return";
        case Stop::obstructed: return "obstructed";
    }
    return "unknown";
}

Error sample(const Profile& profile, m::Phase phase, Pose& output) noexcept {
    const auto error = validate(profile);
    if (error != Error::none) return error;
    Pose next;
    if (m::sample(profile.timing, phase, next.cycle) != m::Error::none) return Error::invalid_phase;
    // travel <= rise <= 2*grid_bound, numerator <= travel: no product overflow.
    const auto offset = (profile.rise / static_cast<clearance::Coordinate>(profile.timing.travel)) *
        static_cast<clearance::Coordinate>(next.cycle.numerator);
    next.platform = profile.lower_box;
    next.platform.minimum[1] += offset;
    next.platform.maximum[1] += offset;
    output = next;
    return Error::none;
}

Plan prepare(const Profile& profile, m::Phase phase, const Observation& observed) noexcept {
    Pose at;
    if (const auto error = sample(profile, phase, at); error != Error::none) return error;
    const auto current = clearance::sweep(at.platform, {}, observed.obstacles);
    if (current.error != clearance::Error::none) return Error::invalid_obstacles;
    const auto hold = [&](Stop stop, std::optional<clearance::Hit> hit = {}) -> Plan {
        return Hold{stop, phase, at, hit};
    };
    if (!observed.powered) return hold(Stop::unpowered);
    if (current.hit) return hold(Stop::obstructed, current.hit);
    if (at.cycle.numerator == 0 && !observed.loaded) {
        if (!observed.source_available) return hold(Stop::empty_source);
        return Handoff{Direction::load, phase, at};
    }
    if (at.cycle.numerator == at.cycle.denominator && observed.loaded) {
        if (!observed.receiver_accepts) return hold(Stop::receiver_closed);
        return Handoff{Direction::unload, phase, at};
    }
    if (at.cycle.stage == m::Stage::outward && !observed.loaded) return hold(Stop::missing_load);
    if (at.cycle.stage == m::Stage::homeward && observed.loaded) return hold(Stop::load_on_return);
    auto next = phase;
    if (m::advance(profile.timing, next, true) != m::Error::none) return Error::invalid_phase;
    Pose to;
    if (const auto error = sample(profile, next, to); error != Error::none) return error;
    const clearance::Point move{0, to.platform.minimum[1] - at.platform.minimum[1], 0};
    const auto proposed = clearance::sweep(at.platform, move, observed.obstacles);
    if (proposed.error != clearance::Error::none) return Error::invalid_obstacles;
    if (proposed.hit) return hold(Stop::obstructed, proposed.hit);
    return Step{next, to};
}
}  // namespace factory::lift
