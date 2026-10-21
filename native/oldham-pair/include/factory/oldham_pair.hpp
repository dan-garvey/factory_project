#pragma once

#include "factory/cardan_pair.hpp"
#include "factory/clearance.hpp"

#include <array>
#include <optional>
#include <span>
#include <variant>

namespace factory::oldham_pair {
using Integer = mechanics::Integer;
using Id = std::uint32_t;
using Dial = cardan_pair::Dial;
using Fraction = mechanics::Rate;
using Point = std::array<Fraction, 3>;
struct Port {
    Id id{};
    mechanics::Point center{};
    mechanics::Axis axis{mechanics::Axis::z};
    bool operator==(const Port&) const = default;
};
struct Profile {
    Port input{7, {0, 0, 0}}, output{11, {8, 0, 4}};
    Integer input_travel{8}, output_travel{8};  // Effective centre travel, each sign.
    Integer disc_radius{3}, half_thickness{1};
    bool operator==(const Profile&) const = default;
};
struct Sample {
    Profile profile;
    Dial dial;
    Point centre;
    Point centre_per_radian;  // Geometric derivative, NOT displacement per tick.
    std::array<Fraction, 2> travel_squared;
    std::array<mechanics::Motion, 3> rotation;  // Input, disc spin and output: 1:1.
};
struct Turn {
    Profile profile;
    clearance::Rotor proxy;
    std::array<bool, 2> travel_fits;
    clearance::FullTurnResult clearance;
    [[nodiscard]] bool admitted() const noexcept { return travel_fits[0] && travel_fits[1] && clearance.clear(); }
};
enum class Error {
    invalid_port, duplicate_id, not_parallel, invalid_profile, axial_gap,
    invalid_dial, invalid_motion, invalid_rate, outside_input_slot,
    outside_output_slot, representation_limit, query_refused,
};
struct Refusal {
    Error reason;
    Id subject{};
    std::optional<geared_cycle::Error> rate_error{};
    std::optional<clearance::Error> geometry_error{};
};
using Reading = std::variant<Refusal, Sample>;
using TurnPlan = std::variant<Refusal, Turn>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Ideal line-key geometry between parallel positive coordinate axes. The disc
// centre is the intersection of two orthogonal rotating slot lines. One caller
// owns the primitive input dial; the centre and both slide distances are derived.
// The output/disc spin follow the input, while the disc CENTRE orbits twice per
// input revolution. Per-radian derivatives need an explicit angular-unit/time
// conversion before any authority could use them as physical velocity.
// Raw validation, exact finite current travel and native source states apply
// even while unpowered. This is an owned observation, not an adopted move.
[[nodiscard]] Reading sample(const Profile&, Dial, mechanics::Motion);

// Pure COMPLETE-turn setup proposal. Each slide's maximum squared travel is
// exactly the transverse shaft-offset squared. The continuous box query encloses
// a circular disc throughout its correct double-frequency centre orbit. The
// proxy box rotates with that orbit; rotational invariance of the enclosed disc
// makes it conservative even though the disc itself spins at input speed.
// Integer midpoint/proxy limits refuse rather than round. Validate the entire
// obstacle set before returning any blocked/admitted result. A hit is an
// existence witness, not first impact time or a partial-turn proposal.
//
// Keys, grooves, flanges and housings are not complete solid geometry here. The
// authority owns truthful shapes, actual construction/contact/force admission,
// load, phase/time, graph adoption and World. Neither API stores live state.
[[nodiscard]] TurnPlan prepare_turn(const Profile&, std::span<const clearance::Obstacle>);
}  // namespace factory::oldham_pair
