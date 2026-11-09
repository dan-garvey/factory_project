#include "material_projection.hpp"
#include "factory/ore_column_target.hpp"
#include "factory/mineral_site.hpp"

#include <algorithm>
#include <cmath>
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
    Integer embodied_plates = state.fabricated_plates;
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
        (plates + embodied_plates) * plate_mass + offcuts + sheets * config.sheet_mass;
    return Value(Object{{"stock_chunks", Value(stock_chunks)},
        {"work_chunks", Value(work_chunks)}, {"plates", Value(plates)},
        {"offcut_units", Value(offcuts)}, {"sheets", Value(sheets)},
        {"embodied_chunks", Value(embodied_chunks)},
        {"embodied_plates", Value(embodied_plates)},
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

// Cosmetic surface exposures retain their authored layout. Their balances and
// cut mask are read from columns, never additional harvesting targets or stock.
static Value ore_surface(const world::Profile& profile,const world::State& state) {
    const auto& grid=profile.excavation->grid;
    std::array<Integer,mineral_site::field_region_count> initial{},remaining{};
    excavation::Cell low{},high{};
    bool first=true;
    for(const auto& [cell,column]:*state.excavation) {
        if(column.initial_units==0)continue;
        if(first){low=high=cell;first=false;}
        low.x=std::min(low.x,cell.x);low.z=std::min(low.z,cell.z);
        high.x=std::max(high.x,cell.x);high.z=std::max(high.z,cell.z);
        const auto pitch=mineral_site::field_pitch_meters;
        const mineral_site::Cell coarse{
            static_cast<Integer>(std::floor((grid.origin[0]+(cell.x+.5)*grid.pitch)/pitch+.5)),
            static_cast<Integer>(std::floor((grid.origin[2]+(cell.z+.5)*grid.pitch)/pitch+.5))};
        if(const auto region=mineral_site::field_region(coarse)) {
            initial[*region]+=column.initial_units;remaining[*region]+=column.remaining_units;
        }
    }
    Array cells,regions_by_cell,regions,cut_cells;
    const auto& id=profile.material.manual_ore->id;
    for(Integer x=mineral_site::field_min.x;x<=mineral_site::field_max.x;++x)
    for(Integer z=mineral_site::field_min.z;z<=mineral_site::field_max.z;++z) {
        cells.emplace_back(Array{Value(x),Value(z)});
        regions_by_cell.emplace_back(id+"-region-"+std::to_string(*mineral_site::field_region({x,z})));
    }
    for(Integer region=0;region<mineral_site::field_region_count;++region) {
        const auto cell=*mineral_site::field_exposure_cell(region);
        regions.emplace_back(Object{{"id",Value(id+"-region-"+std::to_string(region))},
            {"position",point_value({cell.x*mineral_site::field_pitch_meters,0,cell.z*mineral_site::field_pitch_meters})},
            {"initial",Value(initial[region])},{"remaining",Value(remaining[region])}});
    }
    for(const auto& [cell,column]:*state.excavation)
        if(column.remaining_units<column.initial_units)
            cut_cells.emplace_back(Array{Value(cell.x-low.x),Value(cell.z-low.z)});
    return Value(Object{{"id",Value(id)},{"cells",Value(std::move(cells))},
        {"cell_regions",Value(std::move(regions_by_cell))},{"regions",Value(std::move(regions))},
        {"cell_pitch",Value(mineral_site::field_pitch_meters)},
        {"cut_origin",Value(Array{Value(grid.origin[0]+low.x*grid.pitch),Value(grid.origin[2]+low.z*grid.pitch)})},
        {"cut_pitch",Value(grid.pitch)},
        {"cut_size",Value(Array{Value(high.x-low.x+1),Value(high.z-low.z+1)})},
        {"cut_cells",Value(std::move(cut_cells))}});
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
        if (contents.raw_units > 0 && profile.excavation && state.excavation) {
            const auto& grid = profile.excavation->grid;
            const double x = point[0] * profile.meters_per_grid_unit + profile.anchor_offset[0];
            const double z = point[2] * profile.meters_per_grid_unit + profile.anchor_offset[2];
            const excavation::Cell cell{Integer(std::floor((x-grid.origin[0])/grid.pitch)),
                Integer(std::floor((z-grid.origin[2])/grid.pitch))};
            const auto column = state.excavation->find(cell);
            if (column != state.excavation->end() && column->second.remaining_units < column->second.initial_units) {
                const auto face = excavation::surface(grid, cell, column->second);
                const double y = point[1] * profile.meters_per_grid_unit + profile.anchor_offset[1];
                if (face && std::abs(y - face->floor) <= profile.meters_per_grid_unit)
                    drop.emplace("ground_position", point_value({x, face->floor, z}));
            }
        }
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
    if(profile.excavation && state.excavation && profile.material.manual_ore)
        fields.emplace("ore_surface",ore_surface(profile,state));
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
        if (profile.excavation && state.excavation) {
            const bool valid=world::ore_columns::validate(*profile.excavation,
                *state.excavation,state.material)==world::ore_columns::Error::none;
            for (const auto& [cell,column]:*state.excavation) {
                if (!valid) break;
                const auto bounds=excavation::surface(profile.excavation->grid,cell,column);
                if (!bounds || column.initial_units==0) continue;
                const authority::Point center{(bounds->min_x+bounds->max_x)/2,
                    bounds->floor,(bounds->min_z+bounds->max_z)/2};
                const authority::Point low{bounds->min_x,bounds->base,bounds->min_z};
                const authority::Point high{bounds->max_x,bounds->floor,bounds->max_z};
                sources.emplace(world::ore_columns::target_id(cell),Value(Object{
                    {"kind",Value("ore_deposit")},{"position",point_value(center)},
                    {"cell",Value(Array{Value(cell.x),Value(cell.z)})},
                    {"initial",Value(column.initial_units)},{"remaining",Value(column.remaining_units)},
                    {"floor",Value(bounds->floor)},
                    {"contact_bounds",Value(Array{point_value(low),point_value(high)})}}));
            }
        } else {
        const auto& ore = *profile.material.manual_ore;
        Object projected_ore{{"kind", Value("ore_deposit")},
            {"position", site_position(ore.center)}, {"initial", Value(profile.initial_units)},
            {"remaining", Value(state.material.stock.source)}};
        if (profile.manual_ore_contact_bounds) {
            const auto& [low, high] = *profile.manual_ore_contact_bounds;
            projected_ore.emplace("contact_bounds", Value(Array{point_value(low), point_value(high)}));
        }
        sources.emplace(ore.id, Value(std::move(projected_ore)));
        if (profile.ore_field && state.ore_field) {
            const auto initial = mineral_site::allocate_field(profile.initial_units);
            for (mineral_site::Integer region = 0;
                    region < mineral_site::field_region_count; ++region) {
                const auto bounds = world::ore_region_contact_bounds(profile, region);
                if (!bounds) continue;
                const auto index = static_cast<std::size_t>(region);
                const authority::Point midpoint{
                    (bounds->first[0] + bounds->second[0]) / 2,
                    (bounds->first[1] + bounds->second[1]) / 2,
                    (bounds->first[2] + bounds->second[2]) / 2};
                Object projected_region{
                    {"kind", Value("ore_deposit")},
                    {"position", point_value(midpoint)},
                    {"initial", Value(initial->remaining[index])},
                    {"remaining", Value(state.ore_field->remaining[index])},
                    {"contact_bounds", Value(Array{point_value(bounds->first),
                        point_value(bounds->second)})}};
                sources.emplace(world::ore_region_id(profile, region),
                    Value(std::move(projected_region)));
            }
        }
        }
        fields.emplace("hand_sources", Value(std::move(sources)));
    }
    return fields;
}

}  // namespace factory::godot_world::material_projection
