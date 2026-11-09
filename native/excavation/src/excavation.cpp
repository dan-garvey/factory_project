#include "factory/excavation.hpp"

#include <algorithm>
#include <cmath>
#include <limits>

namespace factory::excavation {
namespace {
bool valid_grid(const Grid& grid) noexcept {
    return std::all_of(grid.origin.begin(), grid.origin.end(),
               [](double value) { return std::isfinite(value); }) &&
        std::isfinite(grid.pitch) && grid.pitch > 0 &&
        std::isfinite(grid.height_step) && grid.height_step > 0 &&
        grid.units_per_step > 0 && grid.work_per_unit > 0;
}

bool valid_column(const Grid& grid, const Column& column) noexcept {
    return std::isfinite(column.initial_height) &&
        column.initial_units >= 0 && column.remaining_units >= 0 &&
        column.remaining_units <= column.initial_units && column.work >= 0 &&
        column.work < grid.work_per_unit &&
        (column.remaining_units > 0 || column.work == 0);
}

double magnitude(const Surface& face) noexcept {
    return std::max({1.0, std::abs(face.min_x), std::abs(face.max_x),
        std::abs(face.min_z), std::abs(face.max_z), std::abs(face.floor),
        std::abs(face.base)});
}

double tolerance(const Grid& grid, const Surface& face) noexcept {
    return std::max(std::min(grid.pitch, grid.height_step / grid.units_per_step) * 1e-9,
        magnitude(face) * 64.0 * std::numeric_limits<double>::epsilon());
}

bool covers(double center, double half_span, double low, double high,
            double epsilon) noexcept {
    return center - half_span <= low + epsilon &&
        center + half_span >= high - epsilon;
}

std::optional<Cell> neighbour(Cell cell, Face face) noexcept {
    switch (face) {
        case Face::west:
            if (cell.x == std::numeric_limits<Integer>::min()) return std::nullopt;
            --cell.x;
            return cell;
        case Face::east:
            if (cell.x == std::numeric_limits<Integer>::max()) return std::nullopt;
            ++cell.x;
            return cell;
        case Face::north:
            if (cell.z == std::numeric_limits<Integer>::min()) return std::nullopt;
            --cell.z;
            return cell;
        case Face::south:
            if (cell.z == std::numeric_limits<Integer>::max()) return std::nullopt;
            ++cell.z;
            return cell;
        case Face::top: return std::nullopt;
    }
    return std::nullopt;
}

bool side_x(Face face) noexcept {
    return face == Face::west || face == Face::east;
}

double plane(const Surface& bounds, Face face) noexcept {
    switch (face) {
        case Face::top: return bounds.floor;
        case Face::west: return bounds.min_x;
        case Face::east: return bounds.max_x;
        case Face::north: return bounds.min_z;
        case Face::south: return bounds.max_z;
    }
    return 0;
}

std::optional<double> neighbour_floor(const Grid& grid, const Columns& columns,
                                    Cell cell, Face face) noexcept {
    const auto adjacent = neighbour(cell, face);
    if (!adjacent) return std::nullopt;
    const auto found = columns.find(*adjacent);
    if (found == columns.end()) return std::nullopt;
    const auto bounds = surface(grid, *adjacent, found->second);
    return bounds ? std::optional<double>{bounds->floor} : std::nullopt;
}

bool valid_contact(const Contact& contact) noexcept {
    switch (contact.face) {
        case Face::top: case Face::west: case Face::east:
        case Face::north: case Face::south: break;
        default: return false;
    }
    const bool finite = std::all_of(contact.center.begin(), contact.center.end(),
        [](double value) { return std::isfinite(value); }) &&
        std::all_of(contact.half_span.begin(), contact.half_span.end(),
        [](double value) { return std::isfinite(value) && value > 0; });
    const auto first = contact.face == Face::top ? 0 : (side_x(contact.face) ? 2 : 0);
    const auto second = contact.face == Face::top ? 2 : 1;
    return finite &&
        std::isfinite(contact.center[first] - contact.half_span[0]) &&
        std::isfinite(contact.center[first] + contact.half_span[0]) &&
        std::isfinite(contact.center[second] - contact.half_span[1]) &&
        std::isfinite(contact.center[second] + contact.half_span[1]);
}
} // namespace

std::optional<Integer> remaining(const Columns& columns) noexcept {
    if (columns.size() > maximum_columns) return std::nullopt;
    Integer total{};
    for (const auto& [cell, column] : columns) {
        (void)cell;
        if (column.initial_units < 0 || column.remaining_units < 0 ||
            column.remaining_units > column.initial_units ||
            column.remaining_units > std::numeric_limits<Integer>::max() - total)
            return std::nullopt;
        total += column.remaining_units;
    }
    return total;
}

std::optional<Surface> surface(const Grid& grid, Cell cell,
                               const Column& column) noexcept {
    if (!valid_grid(grid) || !valid_column(grid, column)) return std::nullopt;
    const long double pitch = grid.pitch;
    const long double unit_depth = static_cast<long double>(grid.height_step) /
        static_cast<long double>(grid.units_per_step);
    const long double x = grid.origin[0] + static_cast<long double>(cell.x) * pitch;
    const long double z = grid.origin[2] + static_cast<long double>(cell.z) * pitch;
    const long double top = static_cast<long double>(grid.origin[1]) + column.initial_height;
    const Integer removed = column.initial_units - column.remaining_units;
    const Surface result{static_cast<double>(x), static_cast<double>(x + pitch),
        static_cast<double>(z), static_cast<double>(z + pitch),
        static_cast<double>(top - static_cast<long double>(removed) * unit_depth),
        static_cast<double>(top - static_cast<long double>(column.initial_units) * unit_depth)};
    if (!std::isfinite(result.min_x) || !std::isfinite(result.max_x) ||
        !std::isfinite(result.min_z) || !std::isfinite(result.max_z) ||
        !std::isfinite(result.floor) || !std::isfinite(result.base) ||
        result.min_x >= result.max_x || result.min_z >= result.max_z ||
        result.floor < result.base)
        return std::nullopt;
    // Reject geometry whose individual bite cannot be represented distinctly.
    // This also keeps floating-point contact tolerance far below a whole bite.
    const long double resolution = magnitude(result) * 1024.0L *
        std::numeric_limits<double>::epsilon();
    if (pitch <= resolution || unit_depth <= resolution) return std::nullopt;
    return result;
}

bool valid(const Grid& grid, const Columns& columns) noexcept {
    if (!valid_grid(grid) || !remaining(columns)) return false;
    for (const auto& [cell, column] : columns)
        if (!surface(grid, cell, column)) return false;
    return true;
}

std::optional<std::vector<FacePatch>> exposed_faces(
        const Grid& grid, const Columns& columns, Cell cell) {
    if (!valid(grid, columns)) return std::nullopt;
    const auto found = columns.find(cell);
    if (found == columns.end()) return std::nullopt;
    const auto bounds = *surface(grid, cell, found->second);
    const double mid_x = static_cast<double>((static_cast<long double>(bounds.min_x) + bounds.max_x) * 0.5L);
    const double mid_z = static_cast<double>((static_cast<long double>(bounds.min_z) + bounds.max_z) * 0.5L);
    std::vector<FacePatch> result{{Face::top, {mid_x, bounds.floor, mid_z},
        {grid.pitch * 0.5, grid.pitch * 0.5}}};
    for (const Face face : {Face::west, Face::east, Face::north, Face::south}) {
        const auto lower = neighbour_floor(grid, columns, cell, face);
        if (!lower || *lower >= bounds.floor) continue;
        const double half_height = static_cast<double>((static_cast<long double>(bounds.floor) - *lower) * 0.5L);
        const double mid_height = static_cast<double>((static_cast<long double>(bounds.floor) + *lower) * 0.5L);
        if (side_x(face))
            result.push_back({face, {plane(bounds, face), mid_height, mid_z},
                {grid.pitch * 0.5, half_height}});
        else
            result.push_back({face, {mid_x, mid_height, plane(bounds, face)},
                {grid.pitch * 0.5, half_height}});
    }
    return result;
}

CutProposal cut(const Grid& grid, const Columns& columns, const Contact& contact,
                Integer supplied_work, Integer receiver_capacity) noexcept {
    CutProposal proposal;
    proposal.cell = contact.cell;
    if (!valid(grid, columns)) return proposal;
    if (!valid_contact(contact) || supplied_work < 0 || receiver_capacity < 0) {
        proposal.status = Status::invalid_request;
        return proposal;
    }
    const auto found = columns.find(contact.cell);
    if (found == columns.end()) {
        proposal.status = Status::outside_deposit;
        return proposal;
    }
    proposal.before = proposal.after = found->second;
    if (found->second.remaining_units == 0) {
        proposal.status = Status::exhausted;
        return proposal;
    }
    const auto bounds = *surface(grid, contact.cell, found->second);
    const auto epsilon = tolerance(grid, bounds);
    const auto axis = contact.face == Face::top ? 1 : (side_x(contact.face) ? 0 : 2);
    if (std::abs(contact.center[axis] - plane(bounds, contact.face)) > epsilon) {
        proposal.status = Status::no_contact;
        return proposal;
    }
    if (contact.face == Face::top) {
        if (!covers(contact.center[0], contact.half_span[0], bounds.min_x, bounds.max_x, epsilon) ||
            !covers(contact.center[2], contact.half_span[1], bounds.min_z, bounds.max_z, epsilon)) {
            proposal.status = Status::face_too_small;
            return proposal;
        }
    } else {
        auto next = found->second;
        --next.remaining_units;
        next.work = 0;
        const auto next_floor = surface(grid, contact.cell, next)->floor;
        const auto adjacent = neighbour_floor(grid, columns, contact.cell, contact.face);
        if (!adjacent || *adjacent > next_floor + epsilon) {
            proposal.status = Status::face_not_exposed;
            return proposal;
        }
        const bool x_side = side_x(contact.face);
        const double low = x_side ? bounds.min_z : bounds.min_x;
        const double high = x_side ? bounds.max_z : bounds.max_x;
        const auto tangent = x_side ? 2 : 0;
        if (!covers(contact.center[tangent], contact.half_span[0], low, high, epsilon) ||
            !covers(contact.center[1], contact.half_span[1], next_floor, bounds.floor, epsilon)) {
            proposal.status = Status::face_too_small;
            return proposal;
        }
    }
    if (receiver_capacity == 0) {
        proposal.status = Status::receiver_full;
        return proposal;
    }
    if (supplied_work == 0) {
        proposal.status = Status::no_work;
        return proposal;
    }
    proposal.work_spent = std::min(supplied_work, grid.work_per_unit - proposal.before.work);
    proposal.after.work += proposal.work_spent;
    proposal.status = Status::working;
    if (proposal.after.work == grid.work_per_unit) {
        --proposal.after.remaining_units;
        proposal.after.work = 0;
        proposal.produced_units = 1;
        proposal.status = Status::produced;
    }
    return proposal;
}

const char* status_name(Status status) noexcept {
    switch (status) {
        case Status::working: return "cutting";
        case Status::produced: return "produced";
        case Status::no_work: return "unpowered";
        case Status::outside_deposit: return "outside_deposit";
        case Status::exhausted: return "exhausted";
        case Status::receiver_full: return "receiver_full";
        case Status::invalid_state: return "invalid_excavation_state";
        case Status::invalid_request: return "invalid_cut_request";
        case Status::no_contact: return "no_ore_contact";
        case Status::face_not_exposed: return "ore_face_not_exposed";
        case Status::face_too_small: return "cutting_face_too_small";
    }
    return "invalid_cut_status";
}
} // namespace factory::excavation
