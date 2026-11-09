#pragma once

#include <array>
#include <compare>
#include <cstddef>
#include <cstdint>
#include <map>
#include <optional>
#include <vector>

namespace factory::excavation {
using Integer = std::int64_t;
using Point = std::array<double, 3>;

struct Cell {
    Integer x{};
    Integer z{};
    auto operator<=>(const Cell&) const = default;
};

// Trusted, immutable world facts. No engine scale or ore grade is hard-coded.
// One removed stock unit lowers this column by height_step / units_per_step.
struct Grid {
    Point origin{};
    double pitch{1.0};
    double height_step{1.0};
    Integer units_per_step{1};
    Integer work_per_unit{1};
    bool operator==(const Grid&) const = default;
};

struct Column {
    Integer initial_units{};
    Integer remaining_units{};
    // Bound terrain height relative to Grid::origin[1], before excavation.
    // Natural terrain need not be rounded to the construction height grid.
    double initial_height{};
    // Incomplete cutting work belongs to this addressed ore, not a tool.
    Integer work{};
    bool operator==(const Column&) const = default;
};

inline constexpr std::size_t maximum_columns = 16384;
using Columns = std::map<Cell, Column>;

enum class Face { top, west, east, north, south };
struct Surface {
    double min_x{};
    double max_x{};
    double min_z{};
    double max_z{};
    double floor{};
    double base{};
    bool operator==(const Surface&) const = default;
};
struct FacePatch {
    Face face{};
    Point center{};
    // Top: X/Z half spans. Side: horizontal tangent/Y half spans.
    std::array<double, 2> half_span{};
    bool operator==(const FacePatch&) const = default;
};

[[nodiscard]] bool valid(const Grid&, const Columns&) noexcept;
[[nodiscard]] std::optional<Integer> remaining(const Columns&) noexcept;
[[nodiscard]] std::optional<Surface> surface(const Grid&, Cell, const Column&) noexcept;
// Includes the actual floor, even when exhausted. Sides are emitted only
// against a known lower neighbour. Bind zero-stock columns around deposit
// edges to describe surrounding ground; a missing neighbour is not free air.
[[nodiscard]] std::optional<std::vector<FacePatch>> exposed_faces(
    const Grid&, const Columns&, Cell);

struct Contact {
    Cell cell{};
    Face face{Face::top};
    Point center{};
    // World-aligned rectangle actually covered by the trusted working face,
    // not the circumscribed AABB of a rotated face. It must cover the complete
    // addressed bite, so a tiny tool cannot withdraw an arbitrarily broad cell.
    std::array<double, 2> half_span{};
    bool operator==(const Contact&) const = default;
};

enum class Status {
    working, produced, no_work, outside_deposit, exhausted, receiver_full,
    invalid_state, invalid_request, no_contact, face_not_exposed,
    face_too_small,
};

struct CutProposal {
    Status status{Status::invalid_state};
    Cell cell{};
    Column before{};
    Column after{};
    Integer produced_units{};
    Integer work_spent{};
    [[nodiscard]] bool changes_column() const noexcept {
        return status == Status::working || status == Status::produced;
    }
};

// Pure proposal for ONE top bite. Extra supplied work is not banked after
// producing a unit: deeper stock requires another actual contact at its new
// floor. Side cuts must cover the top bite from an already lower neighbour,
// never tunnel under retained material. A full receiver preserves ore and work.
// Hand and powered tools use this same function with their supplied work.
// World must commit before/after and output custody atomically; overlapping
// tools must plan again against the latest columns after each settlement.
[[nodiscard]] CutProposal cut(const Grid&, const Columns&, const Contact&,
                             Integer supplied_work, Integer receiver_capacity) noexcept;

[[nodiscard]] const char* status_name(Status) noexcept;
}  // namespace factory::excavation
