#pragma once

#include "factory/cycle.hpp"
#include "factory/indexing.hpp"

#include <iosfwd>

namespace factory::index_drive {
struct Profile {
    mechanisms::Slide carrier{2, 3, 2};
    indexing::Axis axis{indexing::Axis::y};
    int direction{1};
};
struct State {
    mechanisms::Phase phase;
    // Reference stop at the start of this carrier revolution. Actual wheel
    // pose is derived from reference AND phase; there is no mirrored live pose.
    indexing::Orientation reference;
    bool operator==(const State&) const = default;
};
struct AngularPose {
    indexing::Orientation from, to;
    mechanisms::Tooth numerator{}, denominator{1};
    bool turning{};  // Describes the next interval, as in the carrier component.
    bool operator==(const AngularPose&) const = default;
};
struct Pose {
    mechanisms::Pose carrier;
    AngularPose wheel;
    bool work_window{};  // Kinematic dwell only; not powered tool admission.
    bool operator==(const Pose&) const = default;
};
struct Observation {
    bool powered{true};
    bool carrier_obstructed{};
    bool wheel_obstructed{};
};
enum class Error { none, invalid_profile, invalid_state, obstructed };
[[nodiscard]] const char* error_name(Error) noexcept;

// Experimental fixed kinematics: the working stroke indexes one quarter turn
// linearly with carrier displacement; return overruns and holds that wheel stop.
// Cycle wrap only rebases the reference. This is not a force/contact simulation.
// Every output and State remain unchanged on refusal. Power loss pauses after
// validation. Carrier obstruction applies to either moving stroke; wheel-motion
// obstruction applies only while indexing, because return is isolated by overrun.
// The caller supplies truthful observations, global power/isolation/admission and
// its sole phase commit. There is no World, material owner, clock or persistence.
[[nodiscard]] Error sample(const Profile&, const State&, Pose&) noexcept;
[[nodiscard]] Error advance(const Profile&, State&, Observation) noexcept;

// Fixed y-axis four-face tag fixture; direction is +1/-1. One retained tag is
// stamped only at powered far dwell and released only after the carrier docks
// with all marks and the wheel home. No reset, World goods or body is created.
[[nodiscard]] int play(int direction, std::istream&, std::ostream&, std::ostream&);
}  // namespace factory::index_drive
