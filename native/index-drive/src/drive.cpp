#include "factory/index_drive.hpp"

namespace factory::index_drive {
const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_state: return "invalid_state";
        case Error::obstructed: return "obstructed";
    }
    return "unknown";
}

Error sample(const Profile& profile, const State& state, Pose& result) noexcept {
    mechanisms::Tooth length{};
    if (mechanisms::cycle_length(profile.carrier, length) != mechanisms::Error::none ||
        static_cast<unsigned>(profile.axis) > 2 || (profile.direction != 1 && profile.direction != -1)) return Error::invalid_profile;
    if (indexing::validate(state.reference) != indexing::Error::none) return Error::invalid_state;
    Pose next;
    if (mechanisms::sample(profile.carrier, state.phase, next.carrier) != mechanisms::Error::none) return Error::invalid_state;
    indexing::Orientation target;
    if (indexing::rotate(state.reference, profile.axis, profile.direction, target) != indexing::Error::none) return Error::invalid_state;
    switch (next.carrier.stage) {
        case mechanisms::Stage::dock:
            next.wheel = {state.reference, state.reference, 0, 1, false};
            break;
        case mechanisms::Stage::outward:
            next.wheel = {state.reference, target, next.carrier.numerator, next.carrier.denominator, true};
            break;
        case mechanisms::Stage::work:
        case mechanisms::Stage::homeward:
            next.wheel = {target, target, 0, 1, false};
            break;
    }
    next.work_window = next.carrier.stage == mechanisms::Stage::work;
    result = next;
    return Error::none;
}

Error advance(const Profile& profile, State& state, Observation observation) noexcept {
    Pose current;
    const auto error = sample(profile, state, current);
    if (error != Error::none) return error;
    if (!observation.powered) return Error::none;
    auto next = state;
    const bool obstruction = observation.carrier_obstructed ||
        (current.carrier.stage == mechanisms::Stage::outward && observation.wheel_obstructed);
    const auto moved = mechanisms::advance(profile.carrier, next.phase, true, obstruction);
    if (moved == mechanisms::Error::obstructed) return Error::obstructed;
    if (moved != mechanisms::Error::none) return Error::invalid_state;
    // The last carrier-return interval holds the already indexed wheel.
    // Changing this reference does not add another physical quarter turn.
    if (next.phase.tooth == 0) next.reference = current.wheel.from;
    state = next;
    return Error::none;
}
}  // namespace factory::index_drive
