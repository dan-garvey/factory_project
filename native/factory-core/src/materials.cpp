#include "factory/materials.hpp"

#include <algorithm>
#include <initializer_list>
#include <limits>
#include <numeric>
#include <utility>

namespace factory::materials {

Quantity belt_speed_subticks(Quantity numerator, Quantity denominator, bool inclined) noexcept {
    if (numerator == 0 || denominator <= 0) return 0;
    __extension__ using Wide = __int128;
    Wide magnitude = numerator;
    if (magnitude < 0) magnitude = -magnitude;
    const Wide speed = magnitude * (inclined ? 2896 : work_subticks_per_tick) / denominator;
    return static_cast<Quantity>(std::min<Wide>(speed, std::numeric_limits<Quantity>::max()));
}

namespace {

bool add(Quantity& total, Quantity value) noexcept {
    if (value < 0 || total > std::numeric_limits<Quantity>::max() - value) return false;
    total += value;
    return true;
}

bool products(Quantity& total, Quantity count, Quantity weight) noexcept {
    return count >= 0 && count <= std::numeric_limits<Quantity>::max() / weight
        && add(total, count * weight);
}

bool valid_lot(const WorkLot& lot, const State& state, const Config& config) noexcept {
    return lot.id > 0 && lot.id < state.next_work_id
        && lot.recipe == RecipeSignature{config.input_units_per_product, config.cycle_ticks}
        && lot.remaining_ticks >= 0 && lot.remaining_ticks <= lot.recipe.cycle_ticks
        && lot.completed_subticks >= 0 && lot.completed_subticks < work_subticks_per_tick
        && lot.work_remainder_denominator > 0 && lot.work_remainder >= 0
        && lot.work_remainder < lot.work_remainder_denominator
        && (lot.remaining_ticks != 0 || (lot.completed_subticks == 0 && lot.work_remainder == 0));
}

void advance_work(WorkLot& lot, Quantity subticks, Quantity remainder, Quantity remainder_denominator) noexcept {
    if (lot.remaining_ticks == 0) return;
    __extension__ using Wide = __int128;
    const auto gcd = std::gcd(lot.work_remainder_denominator, remainder_denominator);
    const Wide common = static_cast<Wide>(lot.work_remainder_denominator / gcd) * remainder_denominator;
    const auto max = std::numeric_limits<Quantity>::max();
    const Quantity denominator = common <= max ? static_cast<Quantity>(common) : max;
    const auto scale = [denominator](Quantity numerator, Quantity from) {
        return (static_cast<Wide>(numerator) * denominator + from / 2) / from;
    };
    const Wide fractional = scale(lot.work_remainder, lot.work_remainder_denominator) +
        scale(remainder, remainder_denominator);
    const Wide progressed = static_cast<Wide>(lot.completed_subticks) + subticks + fractional / denominator;
    const auto whole = progressed / work_subticks_per_tick;
    if (whole >= lot.remaining_ticks) {
        lot.remaining_ticks = 0;
        lot.completed_subticks = 0;
        lot.work_remainder = 0;
        lot.work_remainder_denominator = 1;
    } else {
        lot.remaining_ticks -= static_cast<Quantity>(whole);
        lot.completed_subticks = static_cast<Quantity>(progressed % work_subticks_per_tick);
        lot.work_remainder = static_cast<Quantity>(fractional % denominator);
        lot.work_remainder_denominator = lot.work_remainder == 0 ? 1 : denominator;
    }
}

}  // namespace

const char* component_name(Component component) noexcept {
    switch (component) {
        case Component::wooden_frame: return "wooden_frame";
        case Component::wooden_shaft: return "wooden_shaft";
        case Component::wooden_cog: return "wooden_cog";
        case Component::receiver_tray: return "receiver_tray";
        case Component::tool_mount: return "tool_mount";
        case Component::sliding_guide: return "sliding_guide";
        case Component::cutting_edge: return "cutting_edge";
        case Component::anvil: return "anvil";
        case Component::ram_face: return "ram_face";
        case Component::softmetal_shaft: return "softmetal_shaft";
        case Component::softmetal_cog: return "softmetal_cog";
        case Component::wooden_workbench: return "wooden_workbench";
    }
    return "invalid_component";
}

std::optional<Component> component_from_name(const std::string& name) noexcept {
    for (const auto component : {Component::wooden_frame, Component::wooden_shaft,
             Component::wooden_cog, Component::receiver_tray, Component::tool_mount,
             Component::sliding_guide, Component::cutting_edge, Component::anvil,
             Component::ram_face, Component::softmetal_shaft, Component::softmetal_cog,
             Component::wooden_workbench})
        if (name == component_name(component)) return component;
    return std::nullopt;
}

std::optional<ComponentCost> component_cost(Component component) noexcept {
    switch (component) {
        case Component::wooden_frame: return ComponentCost{3, 0};
        case Component::wooden_shaft: return ComponentCost{1, 0};
        case Component::wooden_cog: return ComponentCost{2, 0};
        case Component::receiver_tray: return ComponentCost{2, 0};
        case Component::tool_mount: return ComponentCost{1, 0};
        case Component::sliding_guide: return ComponentCost{1, 0};
        case Component::cutting_edge: return ComponentCost{0, 1};
        case Component::anvil: return ComponentCost{0, 2};
        case Component::ram_face: return ComponentCost{0, 2};
        case Component::softmetal_shaft: return ComponentCost{0, 2};
        case Component::softmetal_cog: return ComponentCost{0, 2};
        case Component::wooden_workbench: return ComponentCost{4, 0};
    }
    return std::nullopt;
}

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::invalid_configuration: return "invalid_configuration";
        case Error::invalid_state: return "invalid_state";
        case Error::invalid_path: return "invalid_path";
        case Error::quantity_overflow: return "quantity_overflow";
        case Error::invalid_actor: return "invalid_actor";
        case Error::unavailable_output: return "unavailable_output";
        case Error::work_id_overflow: return "work_id_overflow";
        case Error::unavailable_drop: return "unavailable_drop";
        case Error::unavailable_source: return "unavailable_source";
        case Error::inventory_full: return "inventory_full";
        case Error::unavailable_recipe: return "unavailable_recipe";
        case Error::unavailable_input: return "unavailable_input";
    }
    return "unknown_error";
}

std::optional<BeltAdvance> advance_belt_lane(const BeltLane& lane, Quantity signed_subticks,
                                             Quantity receiver_capacity) {
    if (lane.slots.size() < 2 || lane.slots.size() > maximum_belt_slots ||
        lane.phase <= -work_subticks_per_tick || lane.phase >= work_subticks_per_tick ||
        lane.remainder_denominator <= 0 || lane.remainder <= -lane.remainder_denominator ||
        lane.remainder >= lane.remainder_denominator ||
        signed_subticks < -maximum_work_subticks_per_tick ||
        signed_subticks > maximum_work_subticks_per_tick || receiver_capacity < 0)
        return std::nullopt;
    for (std::size_t index = 0; index < lane.slots.size(); ++index) {
        if (!lane.slots[index]) continue;
        const auto& item = *lane.slots[index];
        const bool raw = item.components.empty() && item.timber == 0 && item.raw_units == 1 && item.products == 0 && item.work_lots.empty();
        const bool product = item.components.empty() && item.timber == 0 && item.raw_units == 0 && item.products == 1 && item.work_lots.empty();
        const bool work = item.components.empty() && item.timber == 0 && item.raw_units == 0 && item.products == 0 && item.work_lots.size() == 1;
        if (!raw && !product && !work) return std::nullopt;
        if (work) {
            const auto& lot = item.work_lots.front();
            if (lot.id <= 0 || lot.recipe.input_units_per_product < 1 || lot.recipe.cycle_ticks < 1 ||
                lot.remaining_ticks < 0 || lot.remaining_ticks > lot.recipe.cycle_ticks ||
                lot.completed_subticks < 0 || lot.completed_subticks >= work_subticks_per_tick ||
                lot.work_remainder_denominator <= 0 || lot.work_remainder < 0 ||
                lot.work_remainder >= lot.work_remainder_denominator ||
                (lot.remaining_ticks == 0 && (lot.completed_subticks != 0 || lot.work_remainder != 0))) return std::nullopt;
            for (std::size_t other = 0; other < index; ++other)
                if (lane.slots[other] && !lane.slots[other]->work_lots.empty() &&
                    lane.slots[other]->work_lots.front().id == lot.id) return std::nullopt;
        }
    }
    BeltAdvance result{lane, {}};
    const auto displacement = lane.phase + signed_subticks;
    const auto steps = displacement / work_subticks_per_tick;
    result.candidate.phase = displacement % work_subticks_per_tick;
    const auto direction = steps < 0 ? -1 : 1;
    for (Quantity step = 0; step < (steps < 0 ? -steps : steps); ++step) {
        auto& slots = result.candidate.slots;
        const std::size_t end = direction > 0 ? slots.size() - 1 : 0;
        if (slots[end] && static_cast<Quantity>(result.delivered.size()) < receiver_capacity) {
            result.delivered.push_back(std::move(*slots[end]));
            slots[end].reset();
        }
        for (std::size_t offset = 1; offset < slots.size(); ++offset) {
            const std::size_t from = direction > 0 ? end - offset : offset;
            const std::size_t to = direction > 0 ? from + 1 : from - 1;
            if (slots[from] && !slots[to]) {
                slots[to] = std::move(slots[from]);
                slots[from].reset();
            }
        }
    }
    return result;
}

std::optional<BeltAdvance> advance_belt_lane_rate(const BeltLane& lane, Quantity numerator,
                                                   Quantity denominator, int direction,
                                                   bool inclined, Quantity receiver_capacity) {
    if (denominator <= 0 || (direction != -1 && direction != 1) || lane.remainder_denominator <= 0 ||
        lane.remainder <= -lane.remainder_denominator || lane.remainder >= lane.remainder_denominator)
        return std::nullopt;
    __extension__ using Wide = __int128;
    Wide magnitude = numerator;
    if (magnitude < 0) magnitude = -magnitude;
    const Wide distance = magnitude * (inclined ? 2896 : work_subticks_per_tick);
    // Preserve both fractions exactly whenever their least common denominator
    // fits in the saved state. For exceptionally large combinations, round
    // each fraction to the largest representable denominator, bounding the
    // total error to one part in that denominator per rate change.
    const auto divisor = std::gcd(lane.remainder_denominator, denominator);
    const Wide common = static_cast<Wide>(lane.remainder_denominator / divisor) * denominator;
    const auto limit = std::numeric_limits<Quantity>::max();
    const Quantity saved_denominator = common <= limit ? static_cast<Quantity>(common) : limit;
    const auto scale = [saved_denominator](Wide value, Quantity from) {
        const Wide product = value * saved_denominator;
        const Wide half = from / 2;
        return product < 0 ? (product - half) / from : (product + half) / from;
    };
    Wide subticks = static_cast<Wide>(lane.phase) + direction * (distance / denominator);
    Wide fraction = scale(lane.remainder, lane.remainder_denominator) +
                    direction * scale(distance % denominator, denominator);
    subticks += fraction / saved_denominator;
    fraction %= saved_denominator;
    // Keep the whole and fractional parts on the same side of zero so that
    // tile boundary crossing uses truncation toward zero even on reversal.
    if (subticks > 0 && fraction < 0) { --subticks; fraction += saved_denominator; }
    if (subticks < 0 && fraction > 0) { ++subticks; fraction -= saved_denominator; }
    const Wide steps = subticks / work_subticks_per_tick;
    auto advanced = advance_belt_lane(lane, 0, receiver_capacity);
    if (!advanced) return std::nullopt;
    advanced->candidate.phase = 0;
    // At most one pass per slot can change a finite lane: after that every
    // item has either exited or reached a blocked downstream position.
    const Wide magnitude_steps = steps < 0 ? -steps : steps;
    Quantity remaining_steps = static_cast<Quantity>(std::min<Wide>(magnitude_steps, lane.slots.size()));
    while (remaining_steps > 0) {
        const auto chunk = std::min<Quantity>(remaining_steps, maximum_work_subticks_per_tick / work_subticks_per_tick);
        auto next = advance_belt_lane(advanced->candidate,
            (steps < 0 ? -chunk : chunk) * work_subticks_per_tick,
            receiver_capacity - static_cast<Quantity>(advanced->delivered.size()));
        if (!next) return std::nullopt;
        advanced->candidate = std::move(next->candidate);
        advanced->delivered.insert(advanced->delivered.end(), next->delivered.begin(), next->delivered.end());
        remaining_steps -= chunk;
    }
    advanced->candidate.phase = static_cast<Quantity>(subticks % work_subticks_per_tick);
    advanced->candidate.remainder = static_cast<Quantity>(fraction);
    advanced->candidate.remainder_denominator = saved_denominator;
    return advanced;
}

Error validate(const State& state, const Config& config, const Path& path) noexcept {
    if (config.input_units_per_product < 1 || config.collector_capacity < 1 ||
        config.cycle_ticks < 1 || config.hand_carry_capacity < 1 ||
        config.hand_carry_capacity > 1000000 || config.component_capacity < 1 ||
        config.component_capacity > 1000000 || config.timber_sites.size() > 16)
        return Error::invalid_configuration;
    if (config.manual_ore && (config.manual_ore->id.empty() ||
        config.timber_sites.contains(config.manual_ore->id))) return Error::invalid_configuration;
    if (!config.manual_ore && state.shipped_products != 0) return Error::invalid_state;
    const auto valid_center = [](const DropPoint& center) {
        for (const auto coordinate : center)
            if (coordinate < -maximum_drop_coordinate || coordinate > maximum_drop_coordinate) return false;
        return true;
    };
    if (config.manual_ore && !valid_center(config.manual_ore->center)) return Error::invalid_configuration;
    if (state.timber_remaining.size() != config.timber_sites.size()) return Error::invalid_state;
    Quantity timber_total = 0, timber_accounted = 0;
    for (const auto& [id, site] : config.timber_sites) {
        if (id.empty() || site.initial < 1 || site.initial > 1000000 || !valid_center(site.center) ||
            !add(timber_total, site.initial)) return Error::invalid_configuration;
        const auto found = state.timber_remaining.find(id);
        if (found == state.timber_remaining.end() || found->second < 0 || found->second > site.initial ||
            !add(timber_accounted, found->second)) return Error::invalid_state;
    }
    std::size_t current_work = state.processing ? 1 : 0;
    for (const auto& [actor, cargo] : state.cargo) {
        (void)actor;
        if (cargo.work_lots.size() > maximum_live_work_lots - current_work) return Error::invalid_state;
        current_work += cargo.work_lots.size();
    }
    if (state.belt_lanes.size() > maximum_belt_lanes) return Error::invalid_state;
    for (const auto& [id, lane] : state.belt_lanes) {
        (void)id;
        if (lane.slots.size() > maximum_belt_slots) return Error::invalid_state;
        for (const auto& item : lane.slots) if (item) {
            if (item->work_lots.size() > maximum_live_work_lots - current_work) return Error::invalid_state;
            current_work += item->work_lots.size();
        }
    }
    for (const auto& [point, cargo] : state.dropped_material) {
        (void)point;
        if (cargo.work_lots.size() > maximum_live_work_lots - current_work) return Error::invalid_state;
        current_work += cargo.work_lots.size();
    }
    const auto& stock = state.stock;
    if (state.initial_units < 0 || state.shipped_products < 0 || stock.source < 0 || stock.collector < 0 ||
        stock.belt < 0 || stock.input < 0 || stock.output < 0 ||
        stock.collector > config.collector_capacity || stock.belt > 1 ||
        stock.input > config.input_units_per_product || stock.output > 1 ||
        state.next_work_id < 1) return Error::invalid_state;
    if ((path.collector_to_belt && (!path.collector_present || !path.belt_present)) ||
        (path.belt_to_processor && (!path.belt_present || !path.processor_present)) ||
        (!path.collector_present && stock.collector != 0) ||
        (!path.belt_present && stock.belt != 0) ||
        (!path.processor_present && (stock.input != 0 || state.processing || stock.output != 0))) {
        return Error::invalid_path;
    }
    // Collect serials once and compare sorted IDs. Repeated scans of all
    // holders for every lot made checkpoint validation quadratic at scale.
    std::array<WorkId, maximum_live_work_lots> live_ids{};
    std::size_t live_count = 0;
    const auto record_lot = [&](const WorkLot& lot) {
        if (!valid_lot(lot, state, config)) return false;
        live_ids[live_count++] = lot.id;
        return true;
    };
    if (state.processing && !record_lot(*state.processing)) return Error::invalid_state;
    Quantity total = 0;
    for (const auto value : {stock.source, stock.collector, stock.belt, stock.input}) {
        if (!add(total, value)) return Error::quantity_overflow;
    }
    if (state.dropped_material.size() > maximum_drop_points) return Error::invalid_state;
    for (const auto& [point, cargo] : state.dropped_material) {
        for (const auto coordinate : point)
            if (coordinate < -maximum_drop_coordinate || coordinate > maximum_drop_coordinate)
                return Error::invalid_state;
        if (cargo.raw_units < 0 || cargo.products < 0 || cargo.timber != 0 || !cargo.components.empty() ||
            (cargo.raw_units == 0 && cargo.products == 0 && cargo.work_lots.empty())) return Error::invalid_state;
        if (!add(total, cargo.raw_units) || !products(total, cargo.products, config.input_units_per_product))
            return Error::quantity_overflow;
        for (const auto& lot : cargo.work_lots) {
            if (!record_lot(lot)) return Error::invalid_state;
            if (!add(total, lot.recipe.input_units_per_product)) return Error::quantity_overflow;
        }
    }
    if (state.processing && !add(total, state.processing->recipe.input_units_per_product)) {
        return Error::quantity_overflow;
    }
    if (!products(total, stock.output, config.input_units_per_product) ||
        !products(total, state.shipped_products, config.input_units_per_product)) return Error::quantity_overflow;
    for (const auto& [span_id, lane] : state.belt_lanes) {
        if (span_id.empty() || lane.slots.size() < 2 || lane.slots.size() > maximum_belt_slots ||
            lane.phase <= -work_subticks_per_tick || lane.phase >= work_subticks_per_tick ||
            lane.remainder_denominator <= 0 || lane.remainder <= -lane.remainder_denominator ||
            lane.remainder >= lane.remainder_denominator)
            return Error::invalid_state;
        for (const auto& item : lane.slots) {
            if (!item) continue;
            const bool raw = item->components.empty() && item->timber == 0 && item->raw_units == 1 && item->products == 0 && item->work_lots.empty();
            const bool product = item->components.empty() && item->timber == 0 && item->raw_units == 0 && item->products == 1 && item->work_lots.empty();
            const bool work = item->components.empty() && item->timber == 0 && item->raw_units == 0 && item->products == 0 && item->work_lots.size() == 1;
            if (!raw && !product && !work) return Error::invalid_state;
            if (raw && !add(total, 1)) return Error::quantity_overflow;
            if (product && !add(total, config.input_units_per_product)) return Error::quantity_overflow;
            if (work) {
                const auto& lot = item->work_lots.front();
                if (!record_lot(lot)) return Error::invalid_state;
                if (!add(total, lot.recipe.input_units_per_product)) return Error::quantity_overflow;
            }
        }
    }
    for (const auto& [actor, cargo] : state.cargo) {
        if (actor.empty() || cargo.raw_units < 0 || cargo.products < 0 || cargo.timber < 0 ||
            !add(timber_accounted, cargo.timber)) return Error::invalid_state;
        Quantity component_count = 0;
        for (const auto& [kind, count] : cargo.components) {
            const auto cost = component_cost(kind);
            if (!cost || count < 1 || !add(component_count, count) ||
                component_count > config.component_capacity ||
                (cost->timber > 0 && !products(timber_accounted, count, cost->timber)) ||
                (cost->ore > 0 && !products(total, count, cost->ore))) return Error::invalid_state;
        }
        if ((!config.manual_ore && config.timber_sites.empty()) && component_count != 0)
            return Error::invalid_state;
        if (!add(total, cargo.raw_units) || !products(total, cargo.products, config.input_units_per_product)) {
            return Error::quantity_overflow;
        }
        for (const auto& lot : cargo.work_lots) {
            if (!record_lot(lot)) return Error::invalid_state;
            if (!add(total, lot.recipe.input_units_per_product)) return Error::quantity_overflow;
        }
    }
    if (state.placed_components.size() > 12 || state.fabricated_timber < 0 ||
        state.fabricated_raw < 0 || !add(timber_accounted, state.fabricated_timber) ||
        !add(total, state.fabricated_raw)) return Error::invalid_state;
    for (const auto& [kind, count] : state.placed_components) {
        const auto cost = component_cost(kind);
        if (!cost || count < 1 || count > 4096 ||
            (cost->timber > 0 && !products(timber_accounted, count, cost->timber)) ||
            (cost->ore > 0 && !products(total, count, cost->ore))) return Error::invalid_state;
    }
    if (!state.placed_components.empty() && !config.manual_ore && config.timber_sites.empty())
        return Error::invalid_state;
    std::sort(live_ids.begin(), live_ids.begin() + live_count);
    if (std::adjacent_find(live_ids.begin(), live_ids.begin() + live_count) !=
        live_ids.begin() + live_count) return Error::invalid_state;
    return total == state.initial_units && timber_accounted == timber_total ?
        Error::none : Error::invalid_state;
}

Error step(State& state, const Config& config, const Path& path) {
    return step(state, config, path,
                MachinePower{path.collector_present, path.belt_present, path.processor_present});
}

Error step(State& state, const Config& config, const Path& path,
           const MachinePower& power) {
    const auto input_error = validate(state, config, path);
    if (input_error != Error::none) return input_error;
    if ((power.collector && !path.collector_present) ||
        (power.belt && !path.belt_present) ||
        (power.processor && !path.processor_present) ||
        (power.belt && !power.belt_forward && !power.reverse_drop) ||
        power.processor_work_per_tick < 0 || power.processor_work_remainder_denominator <= 0 ||
        power.processor_work_remainder < 0 || power.processor_work_remainder >= power.processor_work_remainder_denominator ||
        (power.processor && power.processor_work_per_tick == 0 && power.processor_work_remainder == 0)) return Error::invalid_path;
    if (!path.powered || (!power.collector && !power.belt && !power.processor))
        return Error::none;
    auto next = state;
    auto& stock = next.stock;
    // Preserve the existing order. Carried work is deliberately not visited.
    if (power.processor && next.processing) {
        auto& lot = *next.processing;
        advance_work(lot, power.processor_work_per_tick, power.processor_work_remainder,
                     power.processor_work_remainder_denominator);
        if (lot.remaining_ticks == 0 && stock.output < 1) {
            next.processing.reset();
            ++stock.output;
        }
    }
    if (power.processor && path.processor_present && !next.processing &&
        stock.input >= config.input_units_per_product) {
        if (next.next_work_id == std::numeric_limits<WorkId>::max()) return Error::work_id_overflow;
        stock.input -= config.input_units_per_product;
        next.processing = WorkLot{next.next_work_id,
            {config.input_units_per_product, config.cycle_ticks}, config.cycle_ticks};
        ++next.next_work_id;
    }
    if (power.belt && power.belt_forward && path.belt_to_processor && stock.belt > 0 &&
        stock.input < config.input_units_per_product) {
        --stock.belt;
        ++stock.input;
    }
    if (power.belt && !power.belt_forward && stock.belt > 0) {
        const auto point = *power.reverse_drop;
        for (const auto coordinate : point)
            if (coordinate < -maximum_drop_coordinate || coordinate > maximum_drop_coordinate)
                return Error::invalid_path;
        const auto existing = next.dropped_material.find(point);
        if (existing != next.dropped_material.end() || next.dropped_material.size() < maximum_drop_points) {
            if (!add(next.dropped_material[point].raw_units, 1)) return Error::quantity_overflow;
            --stock.belt;
        }
    }
    if (power.collector && path.collector_to_belt && stock.collector > 0 && stock.belt < 1) {
        --stock.collector;
        ++stock.belt;
    }
    if (power.collector && path.collector_present && stock.source > 0 &&
        stock.collector < config.collector_capacity) {
        --stock.source;
        ++stock.collector;
    }
    const auto output_error = validate(next, config, path);
    if (output_error != Error::none) return output_error;
    state = std::move(next);
    return Error::none;
}

Error turn_press(State& state, const Config& config, const Path& path,
                 const DropPoint& work, const DropPoint& exit) {
    const auto valid = validate(state, config, path);
    if (valid != Error::none) return valid;
    if (config.input_units_per_product != 1 || work == exit) return Error::unavailable_recipe;
    const auto found = state.dropped_material.find(work);
    if (found == state.dropped_material.end()) return Error::unavailable_input;
    const auto& item = found->second;
    if (item.products != 0 || item.raw_units + static_cast<Quantity>(item.work_lots.size()) != 1)
        return Error::invalid_state;
    if (item.work_lots.size() == 1 && item.work_lots.front().remaining_ticks == 0 &&
        state.dropped_material.contains(exit)) return Error::unavailable_output;
    auto next = state;
    auto& active = next.dropped_material.at(work);
    if (active.raw_units == 1) {
        if (next.next_work_id == std::numeric_limits<WorkId>::max()) return Error::work_id_overflow;
        active.raw_units = 0;
        active.work_lots.push_back(WorkLot{next.next_work_id++, {1, config.cycle_ticks}, config.cycle_ticks});
    } else {
        advance_work(active.work_lots.front(), work_subticks_per_tick, 0, 1);
    }
    // The work location is removed before its product takes the clear exit,
    // so the number of loose locations never grows during this transfer.
    if (active.work_lots.front().remaining_ticks == 0 &&
        !next.dropped_material.contains(exit)) {
        next.dropped_material.erase(work);
        next.dropped_material.emplace(exit, Cargo{0, 1, {}});
    }
    const auto result = validate(next, config, path);
    if (result != Error::none) return result;
    state = std::move(next);
    return Error::none;
}

Error pickup_material(State& state, const Config& config, const Path& path,
                 const std::string& actor, const DropPoint& point) {
    const auto input_error = validate(state, config, path);
    if (input_error != Error::none) return input_error;
    if (actor.empty() || !state.cargo.contains(actor)) return Error::invalid_actor;
    const auto found = state.dropped_material.find(point);
    if (found == state.dropped_material.end()) return Error::unavailable_drop;
    auto next = state;
    auto& destination = next.cargo.at(actor);
    if (!add(destination.raw_units, found->second.raw_units) || !add(destination.products, found->second.products))
        return Error::quantity_overflow;
    destination.work_lots.insert(destination.work_lots.end(), found->second.work_lots.begin(), found->second.work_lots.end());
    next.dropped_material.erase(point);
    const auto output_error = validate(next, config, path);
    if (output_error != Error::none) return output_error;
    state = std::move(next);
    return Error::none;
}

Error harvest_source(State& state, const Config& config, const Path& path,
                     const std::string& actor, const std::string& source_id) {
    const auto input_error = validate(state, config, path);
    if (input_error != Error::none) return input_error;
    if (actor.empty() || !state.cargo.contains(actor)) return Error::invalid_actor;
    const bool ore = config.manual_ore && config.manual_ore->id == source_id;
    const auto timber = config.timber_sites.find(source_id);
    if (!ore && timber == config.timber_sites.end()) return Error::unavailable_source;
    if ((ore && state.stock.source == 0) ||
        (!ore && state.timber_remaining.at(source_id) == 0)) return Error::unavailable_source;
    const auto& carried = state.cargo.at(actor);
    __extension__ using Wide = __int128;
    const Wide used = static_cast<Wide>(carried.raw_units) + carried.products +
        carried.timber + carried.work_lots.size();
    Wide component_count = 0;
    for (const auto& [kind, count] : carried.components) {
        (void)kind;
        component_count += count;
    }
    if (used + component_count >= config.hand_carry_capacity) return Error::inventory_full;
    auto next = state;
    if (ore) {
        --next.stock.source;
        ++next.cargo.at(actor).raw_units;
    } else {
        --next.timber_remaining.at(source_id);
        ++next.cargo.at(actor).timber;
    }
    const auto output_error = validate(next, config, path);
    if (output_error != Error::none) return output_error;
    state = std::move(next);
    return Error::none;
}

Error craft_component(State& state, const Config& config, const Path& path,
                      const std::string& actor, Component component) {
    const auto input_error = validate(state, config, path);
    if (input_error != Error::none) return input_error;
    if (actor.empty() || !state.cargo.contains(actor)) return Error::invalid_actor;
    const auto cost = component_cost(component);
    if (!cost || (!config.manual_ore && config.timber_sites.empty())) return Error::unavailable_recipe;
    const auto& carried = state.cargo.at(actor);
    if (carried.timber < cost->timber || carried.raw_units < cost->ore) return Error::unavailable_input;
    Quantity count = 0;
    for (const auto& [kind, amount] : carried.components) {
        (void)kind;
        if (!add(count, amount)) return Error::quantity_overflow;
    }
    if (count >= config.component_capacity) return Error::inventory_full;
    auto next = state;
    auto& output = next.cargo.at(actor);
    output.timber -= cost->timber;
    output.raw_units -= cost->ore;
    ++output.components[component];
    const auto output_error = validate(next, config, path);
    if (output_error != Error::none) return output_error;
    state = std::move(next);
    return Error::none;
}

Error retrieve(State& state, const Config& config, const Path& path,
               const std::string& actor, Quantity amount) {
    const auto input_error = validate(state, config, path);
    if (input_error != Error::none) return input_error;
    if (actor.empty() || !state.cargo.contains(actor)) return Error::invalid_actor;
    if (amount < 1 || amount > state.stock.output) return Error::unavailable_output;
    auto next = state;
    if (!add(next.cargo.at(actor).products, amount)) return Error::quantity_overflow;
    next.stock.output -= amount;
    const auto output_error = validate(next, config, path);
    if (output_error != Error::none) return output_error;
    state = std::move(next);
    return Error::none;
}

}  // namespace factory::materials
