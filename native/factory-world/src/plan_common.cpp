#include "plan_common.hpp"

#include <algorithm>
#include <limits>
#include <utility>

namespace factory::world {

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
