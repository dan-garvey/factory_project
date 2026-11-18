#pragma once

#include "factory/mechanics.hpp"

#include <functional>
#include <optional>

namespace factory::piston {
using Integer = mechanics::Integer;
using Point = mechanics::Point;
// Native motion is finer than the construction grid. One foundation unit is
// four construction levels; each paid segment adds exactly one unit of reach.
inline constexpr Integer ticks_per_level = 1024;
inline constexpr Integer segment_ticks = 4 * ticks_per_level;
inline constexpr Integer maximum_segments = 64;
inline constexpr Integer feed_ticks_per_turn = 256;
inline constexpr Integer maximum_step = 64;
struct Config {
    Point center{};
    Integer orientation{}; // 24 proper cube rotations; zero is vertical down.
    Integer segments{};
    bool operator==(const Config&) const = default;
};
struct Progress {
    Integer position{}, remainder{}, denominator{1};
    bool blocked{};
    bool operator==(const Progress&) const = default;
};
using Basis = std::array<Point, 3>;
[[nodiscard]] std::optional<Basis> basis(Integer orientation) noexcept;
[[nodiscard]] Point rotate(const Basis&, Point) noexcept;
[[nodiscard]] bool valid(const Config&, const Progress& = {}) noexcept;
[[nodiscard]] Point displacement(const Config&, const Progress&); // Native ticks.
[[nodiscard]] Point moving_point(const Config&, const Progress&, Point reference);
[[nodiscard]] Point segment_center(const Config&, Integer index); // Retracted construction address; zero based.
struct Bounds {
    Point minimum{}, maximum{}; // Native ticks, world axes.
    bool operator==(const Bounds&) const = default;
};
[[nodiscard]] Bounds enclosure(Bounds, Bounds) noexcept;
[[nodiscard]] bool overlaps(const Bounds&, const Bounds&) noexcept;
struct Geometry {
    Bounds housing, arm;
    std::vector<Bounds> segments;
};
[[nodiscard]] Geometry geometry(const Config&, const Progress&);
enum class Channel { feed, tool, output };
struct Port {
    Channel channel;
    mechanics::RotaryPort reference; // Shared shaft-port contract in its rigid frame.
    Point position; // Actual world position in native ticks.
    bool moving{};
};
// Fixed feed and tool shafts are independent. Only tool connects to output;
// the authority derives that registered joint, never a client-supplied edge.
[[nodiscard]] std::vector<Port> ports(const Config&, const Progress&);
[[nodiscard]] std::array<mechanics::Part, 3> spindles(const Config&, const std::string& owner);
[[nodiscard]] mechanics::Engagement through_connection(const Config&, const std::string& owner);

enum class Clearance { clear, blocked, unavailable };
using ObserveSweep = std::function<Clearance(const Progress& from, const Progress& to,
    const Bounds& swept_arm)>;
enum class Error { none, invalid_state, invalid_rate, query_failed };
struct Motion {
    Error error{Error::none};
    Progress progress;
    Integer displacement{};
    bool at_limit{};
};
// The caller checks the entire arm/payload path against its authoritative site.
// Failure rolls back the proposal. Obstruction retains the last clear position,
// discards accumulated feed and remains retractable. Length changes travel only.
[[nodiscard]] Motion advance(const Config&, const Progress&, mechanics::Rate,
    const ObserveSweep&);
} // namespace factory::piston
