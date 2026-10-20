#include "factory/recovery.hpp"

#include <algorithm>
#include <limits>
#include <utility>

namespace factory::materials {
namespace {

TransferPlan refused(TransferError reason, Error material_error = Error::none) {
    return TransferRefusal{reason, material_error};
}

TransferPlan invalid_state(Error error) {
    return refused(error == Error::quantity_overflow ? TransferError::quantity_overflow
                                                    : TransferError::invalid_material_state, error);
}

bool add(Quantity& value, Quantity amount) noexcept {
    if (amount < 0 || value > std::numeric_limits<Quantity>::max() - amount) return false;
    value += amount;
    return true;
}

bool present(const Path& path, Holder holder) noexcept {
    switch (holder) {
        case Holder::collector: return path.collector_present;
        case Holder::belt: return path.belt_present;
        case Holder::processor: return path.processor_present;
        case Holder::source: return true;
    }
    return false;
}

std::optional<TransferError> target_error(const ResolvedTarget& target) {
    // Membership, current generation and reach have already been resolved by
    // World. These are only shape/presence checks on that internal reference.
    if (target.entity.id.empty() || target.entity.id.find('\0') != std::string::npos ||
        target.entity.generation < 1) return TransferError::invalid_target;
    if (target.holder == Holder::source) return TransferError::unsupported_source;
    if (!present(target.path, target.holder)) return TransferError::invalid_target;
    return {};
}

Quantity& raw_slot(State& state, Holder holder) {
    switch (holder) {
        case Holder::collector: return state.stock.collector;
        case Holder::belt: return state.stock.belt;
        default: return state.stock.input; // Only validated processor remains.
    }
}

Quantity capacity(const Config& config, Holder holder) noexcept {
    switch (holder) {
        case Holder::collector: return config.collector_capacity;
        case Holder::belt: return 1;
        default: return config.input_units_per_product;
    }
}

TransferPlan prepared(State&& candidate, Cargo&& moved, const std::string& actor,
                      const ResolvedTarget& target, TransferDirection direction) {
    return PreparedTransfer{std::move(candidate),
        {direction, actor, target.entity, target.holder, std::move(moved)}};
}

}  // namespace

const char* transfer_error_name(TransferError error) noexcept {
    switch (error) {
        case TransferError::invalid_material_state: return "invalid_material_state";
        case TransferError::invalid_target: return "invalid_target";
        case TransferError::unknown_actor: return "unknown_actor";
        case TransferError::unsupported_source: return "unsupported_source";
        case TransferError::nothing_to_recover: return "nothing_to_recover";
        case TransferError::invalid_amount: return "invalid_amount";
        case TransferError::unavailable_cargo: return "unavailable_cargo";
        case TransferError::occupied_target: return "occupied_target";
        case TransferError::insufficient_capacity: return "insufficient_capacity";
        case TransferError::incompatible_work_recipe: return "incompatible_work_recipe";
        case TransferError::quantity_overflow: return "quantity_overflow";
    }
    return "unknown_error";
}

TransferPlan prepare_recovery(const State& state, const Config& config,
                               const RecoverySelection& selection) {
    const auto error = validate(state, config, selection.target.path);
    if (error != Error::none) return invalid_state(error);
    if (!state.cargo.contains(selection.actor)) return refused(TransferError::unknown_actor);
    if (const auto failure = target_error(selection.target)) return refused(*failure);

    Cargo moved;
    if (selection.target.holder == Holder::collector) moved.raw_units = state.stock.collector;
    else if (selection.target.holder == Holder::belt) moved.raw_units = state.stock.belt;
    else {
        moved.raw_units = state.stock.input;
        moved.products = state.stock.output;
        if (state.processing) moved.work_lots.push_back(*state.processing);
    }
    if (moved.raw_units == 0 && moved.products == 0 && moved.work_lots.empty()) {
        return refused(TransferError::nothing_to_recover);
    }
    auto next = state;
    auto& cargo = next.cargo.at(selection.actor);
    if (!add(cargo.raw_units, moved.raw_units) || !add(cargo.products, moved.products)) {
        return refused(TransferError::quantity_overflow);
    }
    for (const auto& lot : moved.work_lots) cargo.work_lots.push_back(lot);
    if (selection.target.holder == Holder::processor) {
        next.stock.input = 0;
        next.stock.output = 0;
        next.processing.reset();
    } else raw_slot(next, selection.target.holder) = 0;
    const auto output_error = validate(next, config, selection.target.path);
    if (output_error != Error::none) return invalid_state(output_error);
    return prepared(std::move(next), std::move(moved), selection.actor, selection.target,
                    TransferDirection::machine_to_actor);
}

TransferPlan prepare_insertion(const State& state, const Config& config,
                                const InsertionSelection& selection) {
    const auto error = validate(state, config, selection.target.path);
    if (error != Error::none) return invalid_state(error);
    const auto actor = state.cargo.find(selection.actor);
    if (actor == state.cargo.end()) return refused(TransferError::unknown_actor);
    if (const auto failure = target_error(selection.target)) return refused(*failure);
    auto next = state;
    auto& cargo = next.cargo.at(selection.actor);
    Cargo moved;
    if (const auto* raw = std::get_if<RawInsertion>(&selection.contents)) {
        if (raw->amount < 1) return refused(TransferError::invalid_amount);
        if (raw->amount > cargo.raw_units) return refused(TransferError::unavailable_cargo);
        auto& slot = raw_slot(next, selection.target.holder);
        if (raw->amount > capacity(config, selection.target.holder) - slot) {
            return refused(TransferError::insufficient_capacity);
        }
        if (!add(slot, raw->amount)) return refused(TransferError::quantity_overflow);
        cargo.raw_units -= raw->amount;
        moved.raw_units = raw->amount;
    } else {
        const auto* work = std::get_if<WorkInsertion>(&selection.contents);
        if (!work || work->id < 1) return refused(TransferError::unavailable_cargo);
        const auto lot = std::find_if(cargo.work_lots.begin(), cargo.work_lots.end(),
            [&](const WorkLot& value) { return value.id == work->id; });
        if (lot == cargo.work_lots.end()) return refused(TransferError::unavailable_cargo);
        if (selection.target.holder != Holder::processor) return refused(TransferError::invalid_target);
        if (next.processing) return refused(TransferError::occupied_target);
        if (!selection.target.accepts_work || *selection.target.accepts_work != lot->recipe) {
            return refused(TransferError::incompatible_work_recipe);
        }
        next.processing = *lot;
        moved.work_lots.push_back(*lot);
        cargo.work_lots.erase(lot);
    }
    const auto output_error = validate(next, config, selection.target.path);
    if (output_error != Error::none) return invalid_state(output_error);
    return prepared(std::move(next), std::move(moved), selection.actor, selection.target,
                    TransferDirection::actor_to_machine);
}

}  // namespace factory::materials
