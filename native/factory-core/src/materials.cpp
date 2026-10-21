#include "factory/materials.hpp"

#include <initializer_list>
#include <limits>
#include <utility>

namespace factory::materials {
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
        && (lot.remaining_ticks != 0 || lot.completed_subticks == 0);
}

// Validation is allocation-free to preserve its noexcept contract. The first
// finite fixture has few simultaneous lots; no factory-scale cost is claimed.
bool unique_lot(const State& state, WorkId id) noexcept {
    bool seen = state.processing && state.processing->id == id;
    for (const auto& [actor, cargo] : state.cargo) {
        (void)actor;
        for (const auto& lot : cargo.work_lots) {
            if (lot.id != id) continue;
            if (seen) return false;
            seen = true;
        }
    }
    return seen;
}

}  // namespace

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
    }
    return "unknown_error";
}

Error validate(const State& state, const Config& config, const Path& path) noexcept {
    if (config.input_units_per_product < 1 || config.collector_capacity < 1 ||
        config.cycle_ticks < 1) return Error::invalid_configuration;
    const auto& stock = state.stock;
    if (state.initial_units < 0 || stock.source < 0 || stock.collector < 0 ||
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
    if (state.processing && (!valid_lot(*state.processing, state, config) ||
                             !unique_lot(state, state.processing->id))) return Error::invalid_state;
    Quantity total = 0;
    for (const auto value : {stock.source, stock.collector, stock.belt, stock.input}) {
        if (!add(total, value)) return Error::quantity_overflow;
    }
    if (state.dropped_raw.size() > maximum_drop_points) return Error::invalid_state;
    for (const auto& [point, count] : state.dropped_raw) {
        for (const auto coordinate : point)
            if (coordinate < -maximum_drop_coordinate || coordinate > maximum_drop_coordinate)
                return Error::invalid_state;
        if (count <= 0) return Error::invalid_state;
        if (!add(total, count)) return Error::quantity_overflow;
    }
    if (state.processing && !add(total, state.processing->recipe.input_units_per_product)) {
        return Error::quantity_overflow;
    }
    if (!products(total, stock.output, config.input_units_per_product)) return Error::quantity_overflow;
    for (const auto& [actor, cargo] : state.cargo) {
        if (actor.empty() || cargo.raw_units < 0 || cargo.products < 0) return Error::invalid_state;
        if (!add(total, cargo.raw_units) || !products(total, cargo.products, config.input_units_per_product)) {
            return Error::quantity_overflow;
        }
        for (const auto& lot : cargo.work_lots) {
            if (!valid_lot(lot, state, config) || !unique_lot(state, lot.id)) return Error::invalid_state;
            if (!add(total, lot.recipe.input_units_per_product)) return Error::quantity_overflow;
        }
    }
    return total == state.initial_units ? Error::none : Error::invalid_state;
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
        power.processor_work_per_tick < 1 ||
        power.processor_work_per_tick > maximum_work_subticks_per_tick) return Error::invalid_path;
    if (!path.powered || (!power.collector && !power.belt && !power.processor))
        return Error::none;
    auto next = state;
    auto& stock = next.stock;
    // Preserve the existing order. Carried work is deliberately not visited.
    if (power.processor && next.processing) {
        auto& lot = *next.processing;
        if (lot.remaining_ticks > 0) {
            const auto progressed = lot.completed_subticks + power.processor_work_per_tick;
            const auto whole = progressed / work_subticks_per_tick;
            if (whole >= lot.remaining_ticks) {
                lot.remaining_ticks = 0;
                lot.completed_subticks = 0;
            } else {
                lot.remaining_ticks -= whole;
                lot.completed_subticks = progressed % work_subticks_per_tick;
            }
        }
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
        const auto existing = next.dropped_raw.find(point);
        if (existing != next.dropped_raw.end() || next.dropped_raw.size() < maximum_drop_points) {
            if (!add(next.dropped_raw[point], 1)) return Error::quantity_overflow;
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

Error pickup_raw(State& state, const Config& config, const Path& path,
                 const std::string& actor, const DropPoint& point) {
    const auto input_error = validate(state, config, path);
    if (input_error != Error::none) return input_error;
    if (actor.empty() || !state.cargo.contains(actor)) return Error::invalid_actor;
    const auto found = state.dropped_raw.find(point);
    if (found == state.dropped_raw.end()) return Error::unavailable_drop;
    auto next = state;
    if (!add(next.cargo.at(actor).raw_units, found->second)) return Error::quantity_overflow;
    next.dropped_raw.erase(point);
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
