#include "factory/indexed_clearance.hpp"

#include <array>

namespace factory::indexed_clearance {
namespace {
namespace i = indexing;
namespace c = clearance;
constexpr i::FaceMask required = 1;  // Original X+ face.
constexpr std::size_t batch = 3;
constexpr i::Orientation work{{i::Face::positive_z, i::Face::positive_y, i::Face::negative_x}};
struct Legs { int outbound{}, returning{}; unsigned out_count{}, return_count{}; };
std::optional<Legs> legs(Route route) noexcept {
    switch (route) {
        case Route::short_path: return Legs{-1, 1, 1, 1};
        case Route::detour: return Legs{1, -1, 3, 3};
        case Route::short_return: return Legs{1, 1, 3, 1};
    }
    return std::nullopt;
}
std::optional<i::Orientation> turned(i::Orientation pose, int direction, unsigned count) noexcept {
    for (unsigned n = 0; n < count; ++n) {
        i::Orientation next;
        if (i::rotate(pose, i::Axis::y, direction, next) != i::Error::none) return std::nullopt;
        pose = next;
    }
    return pose;
}
const i::Orientation& pose(const State& state) noexcept {
    if (const auto* job = std::get_if<i::Job>(&state.holder)) return job->orientation;
    return std::get<i::Orientation>(state.holder);
}
c::Box work_box(const Profile& profile) noexcept {
    return {{-1, profile.height - 1, 2}, {1, profile.height + 1, 3}};
}
bool metadata(const i::Job& job, std::size_t position, i::FaceMask marked, const i::Orientation& expected) noexcept {
    return i::validate(job) == i::Error::none && job.id == static_cast<materials::WorkId>(7 + position) &&
           job.required == required && job.marked == marked && job.orientation == expected;
}
}  // namespace

const char* route_name(Route route) noexcept {
    switch (route) {
        case Route::short_path: return "short";
        case Route::detour: return "detour";
        case Route::short_return: return "short_return";
    }
    return "unknown";
}
const char* phase_name(Phase phase) noexcept {
    switch (phase) {
        case Phase::load: return "load";
        case Phase::outbound: return "outbound";
        case Phase::stamp: return "stamp";
        case Phase::release: return "release";
        case Phase::returning: return "returning";
        case Phase::complete: return "complete";
    }
    return "unknown";
}
const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_state: return "invalid_state";
        case Error::blocked: return "blocked";
        case Error::indexing_refusal: return "indexing_refusal";
        case Error::clearance_refusal: return "clearance_refusal";
        case Error::unsafe_route_change: return "unsafe_route_change";
        case Error::complete: return "complete";
    }
    return "unknown";
}

State start(Route route) {
    State state;
    state.route = route;
    for (std::size_t n = 0; n < batch; ++n) state.pending.push_back({static_cast<materials::WorkId>(7 + n), {}, required, 0});
    return state;
}

std::optional<c::Box> envelope(const Profile& profile, const i::Orientation& orientation) noexcept {
    if (profile.height < 0 || profile.height > 2 || i::validate(orientation) != i::Error::none) return std::nullopt;
    const c::Box local{{2, -1, -1}, {3, 1, 1}};
    const c::Point pivot{0, profile.height, 0};
    c::Box result;
    for (std::size_t local_axis = 0; local_axis < 3; ++local_axis) {
        const auto face = static_cast<unsigned>(orientation.positive_axes[local_axis]);
        const auto world_axis = face / 2;
        const bool positive = face % 2 == 0;
        result.minimum[world_axis] = pivot[world_axis] + (positive ? local.minimum[local_axis] : -local.maximum[local_axis]);
        result.maximum[world_axis] = pivot[world_axis] + (positive ? local.maximum[local_axis] : -local.minimum[local_axis]);
    }
    return result;
}

bool valid(const Profile& profile, const State& state) noexcept {
    if (profile.height < 0 || profile.height > 2 || state.pending.size() > batch || state.completed.size() > batch) return false;
    const auto route = legs(state.route);
    if (!route || state.holder.valueless_by_exception()) return false;
    bool loaded{};
    i::FaceMask marked{};
    std::optional<i::Orientation> expected{i::Orientation{}};
    switch (state.phase) {
        case Phase::load:
            if (state.pending.empty() || state.quarter) return false;
            break;
        case Phase::outbound:
            if (state.quarter >= route->out_count) return false;
            loaded = true; expected = turned({}, route->outbound, state.quarter);
            break;
        case Phase::stamp:
        case Phase::release:
            if (state.quarter) return false;
            loaded = true; expected = work;
            marked = state.phase == Phase::release ? required : 0;
            break;
        case Phase::returning:
            if (state.quarter >= route->return_count || state.completed.empty()) return false;
            expected = turned(work, route->returning, state.quarter);
            break;
        case Phase::complete:
            if (state.quarter || !state.pending.empty() || state.completed.size() != batch) return false;
            break;
        default: return false;
    }
    const auto* held = std::get_if<i::Job>(&state.holder);
    if (!expected || (held != nullptr) != loaded || state.pending.size() + state.completed.size() + (loaded ? 1 : 0) != batch) return false;
    if (i::validate(pose(state)) != i::Error::none || pose(state) != *expected) return false;
    if (held && !metadata(*held, state.completed.size(), marked, *expected)) return false;
    for (std::size_t n = 0; n < state.completed.size(); ++n) if (!metadata(state.completed[n], n, required, work)) return false;
    for (std::size_t n = 0; n < state.pending.size(); ++n) {
        if (!metadata(state.pending[n], state.completed.size() + (loaded ? 1 : 0) + n, 0, {})) return false;
    }
    return true;
}
bool finished(const Profile& profile, const State& state) noexcept { return valid(profile, state) && state.phase == Phase::complete; }

Transition plan_route(const Profile& profile, const State& state, Route route) {
    if (!valid(profile, state) || !legs(route)) return Refusal{Error::invalid_state};
    if (state.phase != Phase::load && !((state.phase == Phase::outbound || state.phase == Phase::returning) && state.quarter == 0)) {
        return Refusal{Error::unsafe_route_change};
    }
    auto next = state;
    next.route = route;
    if (!valid(profile, next)) return Refusal{Error::invalid_state};
    return next;
}

Transition plan_step(const Profile& profile, const State& state) {
    if (!valid(profile, state)) return Refusal{Error::invalid_state};
    if (state.phase == Phase::complete) return Refusal{Error::complete};
    auto next = state;
    const auto route = *legs(state.route);
    switch (state.phase) {
        case Phase::load:
            next.holder = next.pending.front(); next.pending.erase(next.pending.begin());
            next.phase = Phase::outbound;
            break;
        case Phase::outbound:
        case Phase::returning: {
            const auto direction = state.phase == Phase::outbound ? route.outbound : route.returning;
            const c::Rotor rotor{*envelope(profile, pose(state)), {0, profile.height, 0}, mechanics::Axis::y};
            const std::array<c::Obstacle, 1> obstacles{{{7, {{1, -1, 1}, {2, 1, 2}}}}};
            const auto clearance = c::quarter_turn(rotor, direction > 0 ? c::TurnDirection::positive : c::TurnDirection::negative, obstacles);
            if (clearance.error != c::Error::none) return Refusal{Error::clearance_refusal, 0, i::Error::none, clearance.error};
            if (clearance.obstacle) return Refusal{Error::blocked, *clearance.obstacle};
            if (const auto* job = std::get_if<i::Job>(&state.holder)) {
                auto candidate = *job;
                const auto error = i::plan_turn(*job, i::Axis::y, direction, candidate);
                if (error != i::Error::none) return Refusal{Error::indexing_refusal, 0, error};
                next.holder = candidate;
            } else {
                i::Orientation candidate;
                const auto error = i::rotate(pose(state), i::Axis::y, direction, candidate);
                if (error != i::Error::none) return Refusal{Error::indexing_refusal, 0, error};
                next.holder = candidate;
            }
            ++next.quarter;
            const auto limit = state.phase == Phase::outbound ? route.out_count : route.return_count;
            if (next.quarter == limit) {
                next.quarter = 0;
                next.phase = state.phase == Phase::outbound ? Phase::stamp : next.pending.empty() ? Phase::complete : Phase::load;
            }
            break;
        }
        case Phase::stamp: {
            if (*envelope(profile, pose(state)) != work_box(profile)) return Refusal{Error::invalid_state};
            auto candidate = std::get<i::Job>(state.holder);
            const auto error = i::plan_stamp(candidate, i::Face::positive_z, candidate);
            if (error != i::Error::none) return Refusal{Error::indexing_refusal, 0, error};
            next.holder = candidate; next.phase = Phase::release;
            break;
        }
        case Phase::release: {
            const auto& job = std::get<i::Job>(state.holder);
            const auto error = i::release_ready(job, work);
            if (error != i::Error::none) return Refusal{Error::indexing_refusal, 0, error};
            next.completed.push_back(job); next.holder = job.orientation;
            next.phase = Phase::returning;
            break;
        }
        case Phase::complete: return Refusal{Error::complete};
    }
    if (!valid(profile, next)) return Refusal{Error::invalid_state};
    return next;
}
}  // namespace factory::indexed_clearance
