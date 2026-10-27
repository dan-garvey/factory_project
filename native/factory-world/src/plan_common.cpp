#include "plan_common.hpp"
#include "factory/foundation_command_contract.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <set>
#include <utility>

namespace factory::world {

values::Value grid_value(const mechanics::Point& point) {
    using Value = values::Value;
    return Value(Value::Array{Value(point[0]), Value(point[1]), Value(point[2])});
}

std::array<mechanics::Point, 4> broad_cells(const mechanics::Point& origin) {
    return {origin, mechanics::Point{origin[0] + 4, origin[1], origin[2]},
        mechanics::Point{origin[0], origin[1], origin[2] + 4},
        mechanics::Point{origin[0] + 4, origin[1], origin[2] + 4}};
}

bool broad_item(const materials::Cargo& cargo) {
    return !cargo.sheets.empty() || std::any_of(cargo.work_lots.begin(),
        cargo.work_lots.end(), [](const auto& lot) {
            return lot.recipe.output == materials::WorkOutput::sheet;
        });
}

std::vector<authority::Point> broad_reach_targets(const Profile& profile,
                                                   const mechanics::Point& origin) {
    std::vector<authority::Point> targets;
    targets.reserve(4);
    for (const auto& cell : broad_cells(origin)) targets.push_back(anchor(profile, cell));
    return targets;
}

std::optional<std::vector<materials::DropPoint>> channel_swept_cells(
        const mechanics::Point& from, const mechanics::Point& to,
        materials::Footprint footprint, authority::Integer rotation, bool small_move) {
    if (from[1] != to[1]) return std::nullopt;
    const auto distance = std::abs(to[0] - from[0]) +
        std::abs(to[2] - from[2]);
    if (distance == 4) {
        if (auto cells = materials::swept_workcells(from, to, footprint, rotation))
            return cells;
    }
    if (!small_move || footprint.x_cells != 1 || footprint.z_cells != 1 ||
        rotation != 0 || to[0] % 4 || to[2] % 4)
        return std::nullopt;
    const bool offset_x = from[0] % 4 != 0;
    const bool offset_z = from[2] % 4 != 0;
    if (offset_x == offset_z) return std::nullopt;
    const auto axis = offset_x ? 0U : 2U;
    const auto other = offset_x ? 2U : 0U;
    if (std::abs(from[axis] % 4) % 2 != 1 || from[other] != to[other] ||
        std::abs(to[axis] - from[axis]) < 1 ||
        std::abs(to[axis] - from[axis]) > 3) return std::nullopt;
    return std::vector<materials::DropPoint>{from, to};
}

bool channel_cells_fit(const std::vector<materials::DropPoint>& cells,
        const std::vector<materials::DropPoint>& supports,
        const std::vector<materials::DropPoint>& blocked) {
    const std::set<materials::DropPoint> supported(supports.begin(), supports.end());
    const std::set<materials::DropPoint> obstructed(blocked.begin(), blocked.end());
    return std::all_of(cells.begin(), cells.end(), [&](const auto& cell) {
        return supported.contains(cell) && !obstructed.contains(cell);
    });
}

std::optional<mechanics::Point> grid_point(const authority::Object& intent,
        authority::Integer limit) {
    const auto* array = field<values::Value::Array>(intent, "center");
    if (!array || array->size() != 3) return std::nullopt;
    mechanics::Point point;
    for (std::size_t index = 0; index < point.size(); ++index) {
        const auto* value = std::get_if<authority::Integer>(&array->at(index).storage());
        if (!value || *value < -limit || *value > limit)
            return std::nullopt;
        point[index] = *value;
    }
    return point;
}

// A rectangle uses the same absolute quarter-pitch coordinates as every part.
// Bound the complete request before enumerating it or changing any custody.
std::vector<mechanics::Point> foundation_area(const authority::Object& intent) {
    const auto start = grid_point(intent);
    const auto* end = field<values::Value::Array>(intent, "end");
    if (!start || !end) return {};
    const auto finish = grid_point(authority::Object{{"center", values::Value(*end)}});
    if (!finish || (*start)[1] != (*finish)[1] || (*start)[0] % 4 || (*start)[2] % 4 ||
        (*finish)[0] % 4 || (*finish)[2] % 4) return {};
    const auto width = std::abs((*start)[0] - (*finish)[0]) / 4 + 1;
    const auto depth = std::abs((*start)[2] - (*finish)[2]) / 4 + 1;
    if (width > foundation_commands::maximum_area_side ||
        depth > foundation_commands::maximum_area_side ||
        width * depth > foundation_commands::maximum_area_side) return {};
    std::vector<mechanics::Point> points;
    for (auto x = std::min((*start)[0], (*finish)[0]); x <= std::max((*start)[0], (*finish)[0]); x += 4)
        for (auto z = std::min((*start)[2], (*finish)[2]); z <= std::max((*start)[2], (*finish)[2]); z += 4)
            points.push_back({x, (*start)[1], z});
    return points;
}

bool add(authority::Integer& total, authority::Integer count) {
    if (count < 0 || total > std::numeric_limits<authority::Integer>::max() - count)
        return false;
    total += count;
    return true;
}

std::optional<stationary::Role> role(const std::string& value) {
    using Role = stationary::Role;
    if (value == "collector") return Role::collector;
    if (value == "belt") return Role::belt;
    if (value == "processor") return Role::processor;
    if (value == "waterwheel") return Role::waterwheel;
    if (value == "gear") return Role::gear;
    if (value == "shaft") return Role::shaft;
    if (value == "gearbox") return Role::gearbox;
    if (value == "vertical_gearbox") return Role::vertical_gearbox;
    if (value == "chain_drive") return Role::chain_drive;
    return std::nullopt;
}

const stationary::PlacedPart* part(const stationary::Topology& topology, const std::string& id) {
    const auto found = std::find_if(topology.parts.begin(), topology.parts.end(),
        [&](const auto& item) { return item.geometry.id == id; });
    return found == topology.parts.end() ? nullptr : &*found;
}

values::Value removed_span_value(const stationary::PlacedBeltSpan& span) {
    using Value = values::Value;
    using Object = authority::Object;
    return Value(Object{{"first_shaft", Value(span.geometry.first_shaft)},
        {"last_shaft", Value(span.geometry.last_shaft)}});
}

values::Value lots_value(const std::vector<materials::WorkLot>& lots) {
    using Value = values::Value;
    using Object = authority::Object;
    Value::Array output;
    for (const auto& lot : lots) {
        Object item{
        {"id", Value(lot.id)}, {"input_units_per_product", Value(lot.recipe.input_units_per_product)},
        {"cycle_ticks", Value(lot.recipe.cycle_ticks)}, {"remaining_ticks", Value(lot.remaining_ticks)},
        {"completed_subticks", Value(lot.completed_subticks)}, {"work_remainder", Value(lot.work_remainder)},
        {"work_remainder_denominator", Value(lot.work_remainder_denominator)}};
        if (lot.recipe.output == materials::WorkOutput::sheet)
            item.emplace("output_form", Value("sheet"));
        output.emplace_back(std::move(item));
    }
    return Value(std::move(output));
}

bool copper_profile(const materials::Config& config) {
    return config.raw_mass != 1 || config.plate_mass != 0 || config.sheet_mass != 0;
}

values::Value belt_cargo_value(const materials::Cargo& cargo, bool copper) {
    using Value = values::Value;
    using Object = authority::Object;
    using Integer = authority::Integer;
    Value::Array lots;
    for (const auto& lot : cargo.work_lots) {
        Object item{
        {"id", Value(lot.id)}, {"recipe_input", Value(lot.recipe.input_units_per_product)},
        {"cycle_ticks", Value(lot.recipe.cycle_ticks)}, {"remaining", Value(lot.remaining_ticks)},
        {"completed_subticks", Value(lot.completed_subticks)}, {"work_remainder", Value(lot.work_remainder)},
        {"work_remainder_denominator", Value(lot.work_remainder_denominator)}};
        if (lot.recipe.output == materials::WorkOutput::sheet)
            item.emplace("output_form", Value("sheet"));
        lots.emplace_back(std::move(item));
    }
    Object output{{"raw", Value(cargo.raw_units)}, {"products", Value(cargo.products)},
                  {"work_lots", Value(std::move(lots))}};
    if (copper) {
        output.emplace("offcuts", Value(cargo.offcuts));
        output.emplace("sheets", Value(static_cast<Integer>(cargo.sheets.size())));
        if (!cargo.sheets.empty()) {
            Value::Array sheet_items;
            for (const auto& sheet : cargo.sheets)
                sheet_items.emplace_back(Object{{"id", Value(sheet.id)},
                    {"rotation", Value(sheet.rotation)}});
            output.emplace("sheet_items", Value(std::move(sheet_items)));
        }
    }
    return Value(std::move(output));
}

authority::Point anchor(const Profile& profile, const mechanics::Point& point) {
    return {static_cast<double>(point[0]) * profile.meters_per_grid_unit + profile.anchor_offset[0],
            static_cast<double>(point[1]) * profile.meters_per_grid_unit + profile.anchor_offset[1],
            static_cast<double>(point[2]) * profile.meters_per_grid_unit + profile.anchor_offset[2]};
}

values::Value point_value(const authority::Point& point) {
    using Value = values::Value;
    return Value(Value::Array{Value(point[0]), Value(point[1]), Value(point[2])});
}

authority::Object reach_facts(const Binding& binding, const authority::ReachReceipt& reach) {
    using Value = values::Value;
    Value::Array targets, distances;
    for (const auto& target : reach.targets) targets.push_back(point_value(target));
    for (const auto distance : reach.distances_squared) distances.emplace_back(distance);
    return {{"actor", Value(binding.actor)}, {"native_epoch", Value(reach.cut.native_epoch)},
        {"actor_position", point_value(reach.cut.position)}, {"targets", Value(std::move(targets))},
        {"distances_squared", Value(std::move(distances))}, {"build_reach", Value(reach.cut.build_reach)}};
}

Owner::Decision refused(std::string reason, std::string entity, authority::Object facts) {
    return {std::nullopt, {false, std::move(reason), std::move(entity), std::move(facts)}};
}

Owner::Decision accepted(State state, std::string entity, authority::Object facts) {
    return {std::move(state), {true, "ok", std::move(entity), std::move(facts)}};
}

} // namespace factory::world
