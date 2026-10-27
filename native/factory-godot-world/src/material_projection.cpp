#include "material_projection.hpp"

#include <limits>
#include <stdexcept>
#include <utility>

namespace factory::godot_world::material_projection {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
}  // namespace

Value point_value(const authority::Point& point) {
    return Value(Array{Value(point[0]), Value(point[1]), Value(point[2])});
}

Value cargo_value(const materials::Cargo& cargo, bool resources, bool copper) {
    Array lots;
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
    if (resources) {
        output.emplace("timber", Value(cargo.timber));
        Object components;
        for (const auto& [kind, count] : cargo.components)
            components.emplace(materials::component_name(kind), Value(count));
        output.emplace("components", Value(std::move(components)));
    }
    if (copper) {
        output.emplace("offcuts", Value(cargo.offcuts));
        output.emplace("sheets", Value(static_cast<Integer>(cargo.sheets.size())));
        if (!cargo.sheets.empty()) {
            Array sheet_items;
            for (const auto& sheet : cargo.sheets)
                sheet_items.emplace_back(Object{{"id", Value(sheet.id)},
                    {"rotation", Value(sheet.rotation)}});
            output.emplace("sheet_items", Value(std::move(sheet_items)));
        }
    }
    return Value(std::move(output));
}

bool copper_forms(const materials::Config& config) {
    return config.raw_mass != 1 || config.plate_mass != 0 || config.sheet_mass != 0;
}

static Value material_mass_value(const materials::State& state, const materials::Config& config) {
    Integer stock_chunks = state.stock.source + state.stock.collector +
        state.stock.belt + state.stock.input;
    Integer work_chunks = state.processing ? state.processing->recipe.input_units_per_product : 0;
    Integer plates = state.stock.output;
    Integer offcuts = state.stock.offcuts;
    Integer sheets = 0;
    Integer embodied_chunks = state.fabricated_raw;
    const auto count_cargo = [&](const materials::Cargo& cargo) {
        stock_chunks += cargo.raw_units;
        plates += cargo.products;
        offcuts += cargo.offcuts;
        sheets += static_cast<Integer>(cargo.sheets.size());
        for (const auto& lot : cargo.work_lots)
            work_chunks += lot.recipe.input_units_per_product;
        for (const auto& [kind, count] : cargo.components)
            embodied_chunks += materials::component_cost(kind)->ore * count;
    };
    for (const auto& [actor, cargo] : state.cargo) { (void)actor; count_cargo(cargo); }
    for (const auto& [point, cargo] : state.dropped_material) { (void)point; count_cargo(cargo); }
    for (const auto& [id, lane] : state.belt_lanes) {
        (void)id;
        for (const auto& slot : lane.slots) if (slot) count_cargo(*slot);
    }
    for (const auto& [kind, count] : state.placed_components)
        embodied_chunks += materials::component_cost(kind)->ore * count;
    const Integer plate_mass = config.plate_mass == 0 ?
        config.input_units_per_product * config.raw_mass : config.plate_mass;
    const Integer accounted = (stock_chunks + work_chunks + embodied_chunks) * config.raw_mass +
        plates * plate_mass + offcuts + sheets * config.sheet_mass;
    return Value(Object{{"stock_chunks", Value(stock_chunks)},
        {"work_chunks", Value(work_chunks)}, {"plates", Value(plates)},
        {"offcut_units", Value(offcuts)}, {"sheets", Value(sheets)},
        {"embodied_chunks", Value(embodied_chunks)},
        {"accounted_mass", Value(accounted)},
        {"initial_mass", Value(state.initial_units * config.raw_mass)}});
}

Object slide_phase_projection(const world::State& state) {
    Object phases;
    for (const auto& [id, phase] : state.slide_phases)
        phases.emplace(id, Value(Object{{"subticks", Value(phase.subticks)},
            {"remainder", Value(phase.remainder)},
            {"denominator", Value(phase.denominator)},
            {"cycle_subticks", Value(world::slide_cycle_subticks)}}));
    return phases;
}
Object tick_fields(const world::Profile& profile, const world::Snapshot& snapshot) {
    const auto& state = snapshot.state;
    const bool copper = copper_forms(profile.material);
    Object manual_cuts, cargo;
    for (const auto& [actor, cut] : state.manual_cuts)
        manual_cuts.emplace(actor, Value(Object{{"target", Value(cut.target)},
            {"remaining_ticks", Value(cut.remaining_ticks)},
            {"duration_ticks", Value(world::manual_cut_ticks)},
            {"interrupted", Value(cut.interrupted_revision != 0)}}));
    for (const auto& [actor, contents] : state.material.cargo)
        cargo.emplace(actor, cargo_value(contents,
            profile.material.manual_ore.has_value() || !profile.material.timber_sites.empty(), copper));
    Array dropped_material;
    for (const auto& [point, contents] : state.material.dropped_material) {
        auto drop = std::get<Object>(cargo_value(contents, false, copper).storage());
        drop.emplace("center", Value(Array{Value(point[0]), Value(point[1]), Value(point[2])}));
        dropped_material.emplace_back(std::move(drop));
    }
    Object belt_spans;
    Integer span_order = 0;
    // The validated ledger bounds this raw-equivalent total by initial stock.
    // Finished products are not unprocessed blanks.
    Integer belt_raw_units = 0;
    for (const auto& span : state.topology.belt_spans) {
        const auto& lane = state.material.belt_lanes.at(span.geometry.id);
        Array slots;
        for (const auto& item : lane.slots) {
            slots.push_back(item ? cargo_value(*item, false, copper) : Value(nullptr));
            if (!item) continue;
            belt_raw_units += item->raw_units;
            for (const auto& lot : item->work_lots) belt_raw_units += lot.recipe.input_units_per_product;
        }
        belt_spans.emplace(span.geometry.id, Value(Object{{"generation", Value(span.generation)},
            {"order", Value(span_order++)}, {"from", Value(span.geometry.first_shaft)}, {"to", Value(span.geometry.last_shaft)},
            {"phase", Value(lane.phase)}, {"slots", Value(std::move(slots))}}));
    }
    Integer player = 0;
    for (const auto& [actor, contents] : state.material.cargo) {
        (void)actor;
        player += contents.products;
    }
    const auto& stock = state.material.stock;
    Object stock_fields{{"source", Value(stock.source)}, {"collector", Value(stock.collector)},
        {"belt", Value(stock.belt)}, {"input", Value(stock.input)},
        {"held", Value(state.material.processing ? state.material.processing->recipe.input_units_per_product : 0)},
        {"output", Value(stock.output)}, {"player", Value(player)}};
    if (copper) stock_fields.emplace("offcuts", Value(stock.offcuts));
    Object fields{{"revision", Value(snapshot.revision)},
        {"order", Value(snapshot.history.order)},
        {"manual_cuts", Value(std::move(manual_cuts))},
        {"cargo", Value(std::move(cargo))},
        {"belt_spans", Value(std::move(belt_spans))}, {"line_belt_raw", Value(belt_raw_units)},
        {"dropped_material", Value(std::move(dropped_material))},
        {"stock", Value(std::move(stock_fields))},
        {"remaining", Value(state.material.processing ? state.material.processing->remaining_ticks : 0)}};
    if (state.landing_pod) fields.emplace("slide_phases", Value(slide_phase_projection(state)));
    if (copper) fields.emplace("material_mass", material_mass_value(state.material, profile.material));
    if (profile.material.manual_ore) {
        const auto site_position = [&profile](const materials::DropPoint& center) {
            return Value(Array{
                Value(center[0] * profile.meters_per_grid_unit + profile.anchor_offset[0]),
                Value(center[1] * profile.meters_per_grid_unit + profile.anchor_offset[1]),
                Value(center[2] * profile.meters_per_grid_unit + profile.anchor_offset[2])});
        };
        Object sources;
        for (const auto& [id, site] : profile.material.timber_sites)
            sources.emplace(id, Value(Object{{"kind", Value("tree")},
                {"position", site_position(site.center)}, {"initial", Value(site.initial)},
                {"remaining", Value(state.material.timber_remaining.at(id))}}));
        const auto& ore = *profile.material.manual_ore;
        Object projected_ore{{"kind", Value("ore_deposit")},
            {"position", site_position(ore.center)}, {"initial", Value(profile.initial_units)},
            {"remaining", Value(state.material.stock.source)}};
        if (profile.manual_ore_contact_bounds) {
            const auto& [low, high] = *profile.manual_ore_contact_bounds;
            projected_ore.emplace("contact_bounds", Value(Array{point_value(low), point_value(high)}));
        }
        sources.emplace(ore.id, Value(std::move(projected_ore)));
        fields.emplace("hand_sources", Value(std::move(sources)));
    }
    return fields;
}

}  // namespace factory::godot_world::material_projection
