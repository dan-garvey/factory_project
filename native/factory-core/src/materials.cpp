#include "factory/materials.hpp"

#include <limits>
#include <utility>

namespace factory::materials {
namespace {

bool add(Quantity& total, Quantity value) noexcept {
    if (value < 0 || total > std::numeric_limits<Quantity>::max() - value) {
        return false;
    }
    total += value;
    return true;
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
    }
    return "unknown_error";
}

Error validate(const State& state, const Config& config, const Path& path) noexcept {
    if (config.input_units_per_product < 1 || config.collector_capacity < 1 ||
        config.cycle_ticks < 1) {
        return Error::invalid_configuration;
    }
    const auto& stock = state.stock;
    if (state.initial_units < 0 || stock.source < 0 || stock.collector < 0 ||
        stock.belt < 0 || stock.input < 0 || stock.held < 0 || stock.output < 0 ||
        stock.collector > config.collector_capacity || stock.belt > 1 ||
        stock.input > config.input_units_per_product || stock.output > 1 ||
        (stock.held != 0 && stock.held != config.input_units_per_product) ||
        state.remaining < 0 || state.remaining > config.cycle_ticks ||
        (stock.held == 0 && state.remaining != 0)) {
        return Error::invalid_state;
    }
    if ((path.collector_to_belt && (!path.collector_present || !path.belt_present)) ||
        (path.belt_to_processor && (!path.belt_present || !path.processor_present)) ||
        (!path.collector_present && stock.collector != 0) ||
        (!path.belt_present && stock.belt != 0) ||
        (!path.processor_present && (stock.input != 0 || stock.held != 0 || stock.output != 0))) {
        return Error::invalid_path;
    }
    Quantity raw = 0;
    for (const auto value : {stock.source, stock.collector, stock.belt, stock.input, stock.held}) {
        if (!add(raw, value)) return Error::quantity_overflow;
    }
    Quantity products = stock.output;
    for (const auto& [actor, amount] : state.inventories) {
        if (actor.empty() || amount < 0) return Error::invalid_state;
        if (!add(products, amount)) return Error::quantity_overflow;
    }
    if (products > std::numeric_limits<Quantity>::max() / config.input_units_per_product) {
        return Error::quantity_overflow;
    }
    if (!add(raw, products * config.input_units_per_product)) return Error::quantity_overflow;
    return raw == state.initial_units ? Error::none : Error::invalid_state;
}

Error step(State& state, const Config& config, const Path& path) {
    const auto input_error = validate(state, config, path);
    if (input_error != Error::none) return input_error;
    if (!path.powered) return Error::none;

    auto next = state;
    auto& stock = next.stock;
    // Preserve the current explicit order: finish held work, start the next
    // cycle, move belt input, move collector stock, then extract finite feed.
    if (stock.held > 0) {
        if (next.remaining > 0) --next.remaining;
        if (next.remaining == 0 && stock.output < 1) {
            stock.held = 0;
            ++stock.output;
        }
    }
    if (path.processor_present && stock.held == 0 && stock.input >= config.input_units_per_product) {
        stock.input -= config.input_units_per_product;
        stock.held = config.input_units_per_product;
        next.remaining = config.cycle_ticks;
    }
    if (path.belt_to_processor && stock.belt > 0 && stock.input < config.input_units_per_product) {
        --stock.belt;
        ++stock.input;
    }
    if (path.collector_to_belt && stock.collector > 0 && stock.belt < 1) {
        --stock.collector;
        ++stock.belt;
    }
    if (path.collector_present && stock.source > 0 && stock.collector < config.collector_capacity) {
        --stock.source;
        ++stock.collector;
    }
    const auto output_error = validate(next, config, path);
    if (output_error != Error::none) return output_error;
    state = std::move(next);
    return Error::none;
}

Error retrieve(State& state, const Config& config, const Path& path,
               const std::string& actor, Quantity amount) {
    const auto input_error = validate(state, config, path);
    if (input_error != Error::none) return input_error;
    if (actor.empty()) return Error::invalid_actor;
    if (amount < 1 || amount > state.stock.output) return Error::unavailable_output;

    auto next = state;
    auto& held = next.inventories[actor];
    if (!add(held, amount)) return Error::quantity_overflow;
    next.stock.output -= amount;
    const auto output_error = validate(next, config, path);
    if (output_error != Error::none) return output_error;
    state = std::move(next);
    return Error::none;
}

}  // namespace factory::materials
