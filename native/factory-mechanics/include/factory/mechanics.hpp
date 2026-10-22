#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace factory::mechanics {

using Integer = std::int64_t;
using Point = std::array<Integer, 3>;

// These are bounds of this first exact-grid adapter, not game-scale targets.
inline constexpr std::size_t maximum_parts = 256;
inline constexpr Integer maximum_coordinate = 1000000;
inline constexpr Integer maximum_dimension = 4096;

enum class Axis { x, y, z };
enum class Kind { hub, gear, shaft };

struct Part {
    std::string id;
    Kind kind{Kind::hub};
    Point center{};
    Axis axis{Axis::z};
    // In integer pitch units, a gear's pitch radius equals its tooth count.
    // Only gears use teeth; only shafts use half_span.
    Integer teeth{};
    Integer half_span{};
    bool operator==(const Part&) const = default;
};

struct Rate {
    Integer numerator{};
    Integer denominator{1};
    bool operator==(const Rate&) const = default;
};

// Only the authority can supply a registered source hub and its drive rate.
// This is not a client command, clock or mutable mechanical world.
struct Drive {
    std::string hub;
    Rate rate;
    bool operator==(const Drive&) const = default;
};

// A placed belt is an explicit span, not an arbitrary power edge. Its ends
// identify shaft tiles; intermediate aligned shaft tiles also participate.
struct BeltSpan {
    std::string id;
    std::string first_shaft;
    std::string last_shaft;
    bool operator==(const BeltSpan&) const = default;
};

enum class BeltPathKind { horizontal, vertical, inclined, sideways };
struct BeltPath {
    BeltPathKind kind;
    // Tile centers in endpoint order, including both endpoints.
    std::vector<Point> tiles;
    bool operator==(const BeltPath&) const = default;
};

// Geometry only: does not grant placement or check occupants, custody or power.
// Axles must be perpendicular to a straight or 45-degree path in their plane.
[[nodiscard]] std::optional<BeltPath> belt_path(const Part& first, const Part& last);

// Signed cargo movement relative to endpoint order: +1 toward last, -1 toward
// first, 0 when stopped. Vertical and sideways belts cannot transport objects.
// Invalid paths and invalid rates also return no direction.
[[nodiscard]] std::optional<int> belt_cargo_direction(const Part& first, const Part& last, Rate rate);

enum class EngagementKind { external_mesh, coaxial_shaft, belt };
struct Engagement {
    std::string a;
    std::string b;
    EngagementKind kind;
    Rate b_from_a;
    bool operator==(const Engagement&) const = default;
};

enum class MotionState { unpowered, stopped, rotating, stalled };
// Prescribed rates are observations that must all hold; sources are physical
// drivers that may back-drive a slower source in the same direction.
enum class SourcePolicy { prescribed, overpower };
struct Motion {
    MotionState state{MotionState::unpowered};
    Rate rate{};
    bool operator==(const Motion&) const = default;
};

struct Component {
    std::vector<std::string> parts;
    MotionState state{MotionState::unpowered};
    bool operator==(const Component&) const = default;
};

enum class Error {
    none,
    too_many_parts,
    invalid_part,
    duplicate_identity,
    invalid_drive,
    invalid_belt,
    overlapping_gears,
    rate_overflow,
};

struct Result {
    Error error{Error::none};
    std::string subject;
    std::vector<Engagement> engagements;
    std::map<std::string, Motion> motion;
    std::vector<Component> components;
    [[nodiscard]] bool accepted() const noexcept { return error == Error::none; }
    bool operator==(const Result&) const = default;
};

[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] const char* motion_state_name(MotionState) noexcept;

// Pure, bounded derivation. Belt spans are validated geometry, not input edges.
// Validation or arithmetic failure publishes no partial engagement/motion map.
// Ratio conflicts stall only their connected component. Contact/load/phase,
// quantities, construction admission and persistence belong to the authority.
[[nodiscard]] Result evaluate(const std::vector<Part>&, const std::vector<Drive>&,
                              const std::vector<BeltSpan>& belts = {},
                              SourcePolicy sources = SourcePolicy::prescribed);

}  // namespace factory::mechanics
