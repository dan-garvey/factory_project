#pragma once

#include "factory/materials.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <variant>

namespace factory::materials {

// This is a pure transfer proposal, not a command, reach or topology authority.
// World binds the actor, resolves the stable entity and generation to this
// fixture's holder, and supplies the current material Path. It rejects unknown
// or stale targets before planning and rechecks identity and admission before
// atomically committing a candidate with its cached command outcome.
enum class Holder { source, collector, belt, processor };

struct EntityRef {
    std::string id;
    std::int64_t generation{};
    bool operator==(const EntityRef&) const = default;
};

struct ResolvedTarget {
    EntityRef entity;
    Holder holder{Holder::source};
    Path path;
    // Only an eligible processor can accept work. In this first profile its
    // accepted signature must match Config exactly. This is a resolved machine
    // fact, not a client-supplied recipe or a second mutable configuration.
    std::optional<RecipeSignature> accepts_work;
};

struct RecoverySelection {
    std::string actor;
    ResolvedTarget target;
};

struct RawInsertion {
    Quantity amount{};
};

// Select an existing whole lot from the bound actor's Cargo. A command cannot
// supply replacement contents, recipe, progress or a newly invented work lot.
struct WorkInsertion {
    WorkId id{};
};

using Insertion = std::variant<RawInsertion, WorkInsertion>;

struct InsertionSelection {
    std::string actor;
    ResolvedTarget target;
    Insertion contents;
};

enum class TransferError {
    invalid_material_state,
    invalid_target,
    unknown_actor,
    unsupported_source,
    nothing_to_recover,
    invalid_amount,
    unavailable_cargo,
    occupied_target,
    insufficient_capacity,
    incompatible_work_recipe,
    quantity_overflow,
};

struct TransferRefusal {
    TransferError reason{TransferError::invalid_material_state};
    // Preserve the underlying material validation error when applicable.
    Error material_error{Error::none};
};

enum class TransferDirection { machine_to_actor, actor_to_machine };

struct TransferFacts {
    TransferDirection direction{TransferDirection::machine_to_actor};
    std::string actor;
    EntityRef affected_entity;
    Holder holder{Holder::source};
    // An immutable receipt value describing the move, not another live holder.
    Cargo moved;
};

struct PreparedTransfer {
    State candidate;
    TransferFacts facts;
};

using TransferPlan = std::variant<TransferRefusal, PreparedTransfer>;

[[nodiscard]] const char* transfer_error_name(TransferError) noexcept;

// Evacuate all selected machine contents into the existing actor's Cargo. A
// processor can contribute input raw, its whole lot and output products together.
// The remote source is never recoverable or refillable through this interface.
// Neither operation alters topology, kit, power, request history or a live World.
[[nodiscard]] TransferPlan prepare_recovery(const State&, const Config&,
                                            const RecoverySelection&);

// Insert positive raw units into an eligible raw holder, or move one whole lot
// to an empty compatible processing slot. Products stay products. Carried work pauses;
// insertion preserves its serial, recipe and remaining ticks, including zero.
// Invalid state, target, capacity, cargo or arithmetic returns only a refusal.
// A successful plan is a complete uncommitted replacement, never a partial move.
[[nodiscard]] TransferPlan prepare_insertion(const State&, const Config&,
                                             const InsertionSelection&);

}  // namespace factory::materials
