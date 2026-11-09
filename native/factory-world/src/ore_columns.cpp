#include "factory/ore_columns.hpp"

#include <utility>
#include <algorithm>
#include <cmath>
#include <limits>

namespace factory::world::ore_columns {
namespace {
bool valid_seed(const Seed& seed, const materials::State& material) noexcept {
    if (seed.columns.empty() || !excavation::valid(seed.grid, seed.columns)) return false;
    const auto initial = excavation::remaining(seed.columns);
    if (!initial || *initial <= 0 || *initial != material.initial_units) return false;
    for (const auto& [cell, column] : seed.columns) {
        (void)cell;
        if (column.initial_units != column.remaining_units || column.work != 0) return false;
    }
    for (const auto& [cell, point] : seed.contact_points) {
        const auto column = seed.columns.find(cell);
        if (column == seed.columns.end() || !std::all_of(point.begin(), point.end(),
                [](double value) { return std::isfinite(value); })) return false;
        const auto bounds = excavation::surface(seed.grid, cell, column->second);
        if (!bounds || point[0] < bounds->min_x || point[0] > bounds->max_x ||
            point[2] < bounds->min_z || point[2] > bounds->max_z ||
            point[1] != bounds->floor) return false;
    }
    return true;
}

Result check_state(const Seed& seed, const Field& field, const materials::State& material,
                   const materials::Config& config, const materials::Path& path) {
    Result result;
    result.error = validate(seed, field, material);
    if (result.error != Error::none) return result;
    result.material_error = materials::validate(material, config, path);
    if (result.material_error != materials::Error::none) result.error = Error::invalid_material;
    return result;
}

Result settle(const Seed& seed, Field& field, materials::State& material,
        const materials::Config& config, const materials::Path& path,
        const excavation::Contact& contact, materials::Quantity work,
        const std::string& receiver, materials::Quantity capacity,
        const std::optional<materials::DropPoint>& ground) {
    auto result = check_state(seed, field, material, config, path);
    if (result.error != Error::none) return result;
    materials::Cargo empty;
    const materials::Cargo* cargo = &empty;
    if (ground) {
        const auto found = material.dropped_material.find(*ground);
        if (found != material.dropped_material.end()) cargo = &found->second;
        else if (material.dropped_material.size() >= materials::maximum_drop_points) {
            result.error = Error::invalid_capacity;
            return result;
        }
    } else {
        const auto owner = material.cargo.find(receiver);
        if (owner == material.cargo.end()) {
            result.error = Error::invalid_receiver;
            return result;
        }
        cargo = &owner->second;
    }
    __extension__ using Wide = __int128;
    Wide count = static_cast<Wide>(cargo->raw_units) + cargo->products + cargo->timber +
        cargo->offcuts + cargo->sheets.size() + cargo->work_lots.size();
    for (const auto& [kind, amount] : cargo->components) { (void)kind; count += amount; }
    const std::optional<materials::Quantity> occupied = count >= 0 &&
        count <= std::numeric_limits<materials::Quantity>::max() ?
        std::optional{static_cast<materials::Quantity>(count)} : std::nullopt;
    if (!occupied || capacity < 0 || *occupied > capacity) {
        result.error = Error::invalid_capacity;
        return result;
    }
    const auto proposal = excavation::cut(seed.grid, field, contact, work, capacity - *occupied);
    result.cutting = proposal.status;
    if (!proposal.changes_column()) return result;

    // All allocation and validation happen on candidates before either owner
    // changes. No loose output, shared contraption pool or spare source exists.
    auto next_field = field;
    auto next_material = material;
    next_field.at(contact.cell) = proposal.after;
    if (proposal.produced_units != 0) {
        auto& cargo = ground ? next_material.dropped_material[*ground] : next_material.cargo.at(receiver);
        next_material.stock.source -= proposal.produced_units;
        cargo.raw_units += proposal.produced_units;
    }
    const auto final = check_state(seed, next_field, next_material, config, path);
    if (final.error != Error::none) return final;
    field = std::move(next_field);
    material = std::move(next_material);
    result.produced_units = proposal.produced_units;
    result.work_spent = proposal.work_spent;
    return result;
}
} // namespace

Error validate(const Seed& seed, const Field& field, const materials::State& material) noexcept {
    if (!valid_seed(seed, material)) return Error::invalid_seed;
    if (field.size() != seed.columns.size() || !excavation::valid(seed.grid, field))
        return Error::invalid_field;
    const auto source = excavation::remaining(field);
    if (!source || *source != material.stock.source) return Error::invalid_field;
    for (const auto& [cell, column] : field) {
        const auto initial = seed.columns.find(cell);
        if (initial == seed.columns.end() ||
            column.initial_units != initial->second.initial_units ||
            column.initial_height != initial->second.initial_height)
            return Error::invalid_field;
    }
    return Error::none;
}

std::optional<Field> initialize(const Seed& seed, const materials::State& material) {
    if (validate(seed, seed.columns, material) != Error::none) return std::nullopt;
    return seed.columns;
}

Result cut_to_ground(const Seed& seed, Field& field, materials::State& material,
        const materials::Config& config, const materials::Path& path,
        const excavation::Contact& contact, materials::Quantity work,
        const materials::DropPoint& ground) {
    return settle(seed, field, material, config, path, contact, work, {},
        std::numeric_limits<materials::Quantity>::max(), ground);
}

Result cut_to_actor(const Seed& seed, Field& field, materials::State& material,
        const materials::Config& config, const materials::Path& path,
        const excavation::Contact& contact, materials::Quantity work, const std::string& actor) {
    return settle(seed, field, material, config, path, contact, work,
                  actor, config.hand_carry_capacity == 0 ?
                    std::numeric_limits<materials::Quantity>::max() : config.hand_carry_capacity, std::nullopt);
}

std::optional<excavation::Surface> surface(const Seed& seed, const Field& field,
        const materials::State& material, excavation::Cell cell) {
    if (validate(seed, field, material) != Error::none) return std::nullopt;
    const auto column = field.find(cell);
    if (column == field.end()) return std::nullopt;
    return excavation::surface(seed.grid, cell, column->second);
}

std::optional<std::vector<excavation::FacePatch>> exposed_faces(const Seed& seed,
        const Field& field, const materials::State& material, excavation::Cell cell) {
    if (validate(seed, field, material) != Error::none) return std::nullopt;
    return excavation::exposed_faces(seed.grid, field, cell);
}

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::invalid_seed: return "invalid_ore_seed";
        case Error::invalid_field: return "invalid_ore_columns";
        case Error::invalid_material: return "invalid_ore_material";
        case Error::invalid_receiver: return "invalid_ore_receiver";
        case Error::invalid_capacity: return "invalid_ore_receiver_capacity";
    }
    return "invalid_ore_error";
}
} // namespace factory::world::ore_columns
