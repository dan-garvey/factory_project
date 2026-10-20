#pragma once

#include "factory/clearance.hpp"
#include "factory/indexing.hpp"

#include <iosfwd>
#include <optional>
#include <variant>
#include <vector>

namespace factory::indexed_clearance {
enum class Route { short_path, detour, short_return };
enum class Phase { load, outbound, stamp, release, returning, complete };
struct Profile {
    clearance::Coordinate height{};  // Fixed for a run: zero, one or two grid units.
};

// One caller-owned finite metadata fixture. These three invented work tags are
// not World goods or quantities. Loaded pose lives only in Job; empty pose lives
// only in Orientation. There is no mirrored pose, material State or live clock.
struct State {
    Route route{Route::detour};
    Phase phase{Phase::load};
    unsigned quarter{};
    std::variant<indexing::Orientation, indexing::Job> holder;
    std::vector<indexing::Job> pending, completed;
    bool operator==(const State&) const = default;
};
enum class Error { invalid_state, blocked, indexing_refusal, clearance_refusal, unsafe_route_change, complete };
struct Refusal {
    Error error{Error::invalid_state};
    std::uint64_t obstacle{};
    indexing::Error indexing_error{indexing::Error::none};
    clearance::Error clearance_error{clearance::Error::none};
};
using Transition = std::variant<Refusal, State>;

[[nodiscard]] const char* route_name(Route) noexcept;
[[nodiscard]] const char* phase_name(Phase) noexcept;
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] State start(Route = Route::detour);
[[nodiscard]] bool valid(const Profile&, const State&) noexcept;
[[nodiscard]] bool finished(const Profile&, const State&) noexcept;
[[nodiscard]] std::optional<clearance::Box> envelope(const Profile&, const indexing::Orientation&) noexcept;

// Pure proposals. The caller commits one accepted State. Refusal publishes no
// partial cursor, marks or tag movement. A route can change only at an intake
// or work-station junction before the next leg has begun. Profile is immutable
// trusted layout supplied by that same caller; it is not a client pose command.
// Native face/turn and continuous-clearance components retain their own rules.
[[nodiscard]] Transition plan_step(const Profile&, const State&);
[[nodiscard]] Transition plan_route(const Profile&, const State&, Route);

// One retained fixture across bounded input lines: step, run 1..64, route
// short|detour|short_return, inspect, help and quit. No reset or replacement exists.
// Exit 0 requires the whole batch and empty holder home; 1 is unfinished;
// 2 is invalid startup, bounded-input refusal or stream failure.
[[nodiscard]] int play(const Profile&, Route, std::istream&, std::ostream&, std::ostream&);
}  // namespace factory::indexed_clearance
