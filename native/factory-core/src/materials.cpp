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

std::optional<BeltAdvance> advance_belt_lane(const BeltLane& lane, Quantity signed_subticks,
                                             Quantity receiver_capacity) {
    if (lane.slots.size() < 2 || lane.slots.size() > maximum_belt_slots ||
        lane.phase <= -work_subticks_per_tick || lane.phase >= work_subticks_per_tick ||
        signed_subticks < -maximum_work_subticks_per_tick ||
        signed_subticks > maximum_work_subticks_per_tick || receiver_capacity < 0)
        return std::nullopt;
    for (std::size_t index = 0; index < lane.slots.size(); ++index) {
        if (!lane.slots[index]) continue;
        const auto& item = *lane.slots[index];
        const bool raw = item.raw_units == 1 && item.products == 0 && item.work_lots.empty();
        const bool product = item.raw_units == 0 && item.products == 1 && item.work_lots.empty();
        const bool work = item.raw_units == 0 && item.products == 0 && item.work_lots.size() == 1;
        if (!raw && !product && !work) return std::nullopt;
        if (work) {
            const auto& lot = item.work_lots.front();
            if (lot.id <= 0 || lot.recipe.input_units_per_product < 1 || lot.recipe.cycle_ticks < 1 ||
                lot.remaining_ticks < 0 || lot.remaining_ticks > lot.recipe.cycle_ticks ||
                lot.completed_subticks < 0 || lot.completed_subticks >= work_subticks_per_tick ||
                (lot.remaining_ticks == 0 && lot.completed_subticks != 0)) return std::nullopt;
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
