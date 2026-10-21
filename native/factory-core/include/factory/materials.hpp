#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace factory::materials {

using Quantity = std::int64_t;
using WorkId = std::int64_t;
inline constexpr Quantity work_subticks_per_tick = 4096;
inline constexpr Quantity maximum_work_subticks_per_tick = 16 * work_subticks_per_tick;

// Canonical data for the unadopted finite material fixture. The sole World and
// its command, admission and persistence boundaries remain separate.

struct RecipeSignature {
    Quantity input_units_per_product{1};
    Quantity cycle_ticks{2};
    bool operator==(const RecipeSignature&) const = default;
};

// A lot owns its original recipe input exactly once. Its positive serial belongs
// to the containing World context; it is not a native body or process identity.
// Zero remaining ticks means ready work waiting for output, not an absent lot.
struct WorkLot {
    WorkId id{};
    RecipeSignature recipe;
    Quantity remaining_ticks{};
    Quantity completed_subticks{};
    bool operator==(const WorkLot&) const = default;
};

struct Cargo {
    Quantity raw_units{};
    Quantity products{};
    std::vector<WorkLot> work_lots;
    bool operator==(const Cargo&) const = default;
};

// These are revisable fixture values, supplied by the caller, not game content.
struct Config {
    Quantity input_units_per_product{1};
    Quantity collector_capacity{1};
    Quantity cycle_ticks{2};
};

struct Stock {
    Quantity source{};
    Quantity collector{};
    Quantity belt{};
    Quantity input{};
    Quantity output{};
    bool operator==(const Stock&) const = default;
};

struct State {
    Quantity initial_units{};
    Stock stock;
    // One canonical Cargo for each admitted actor. Projection compatibility maps
    // are derived elsewhere; they cannot be another mutable inventory.
    std::map<std::string, Cargo> cargo;
    std::optional<WorkLot> processing;
    WorkId next_work_id{1};
    bool operator==(const State&) const = default;
};

// The current topology authority supplies these facts. This library does not
// infer transmission, accept client links, or create another mechanical owner.
struct Path {
    bool collector_present{};
    bool belt_present{};
    bool processor_present{};
    bool collector_to_belt{};
    bool belt_to_processor{};
    bool powered{};
};

// Resolved local drive facts, never a client permission or another solver.
// Path.powered remains the coarse fixture enable. Each active sender moves its
// own output, and stopped receiving buffers may accept raw material. Processor
// power alone advances/starts machine work. These are revisable fixture choices.
struct MachinePower {
    bool collector{};
    bool belt{};
    bool processor{};
    Quantity processor_work_per_tick{work_subticks_per_tick};
};

enum class Error {
    none,
    invalid_configuration,
    invalid_state,
    invalid_path,
    quantity_overflow,
    invalid_actor,
    unavailable_output,
    work_id_overflow,
};

[[nodiscard]] const char* error_name(Error error) noexcept;
// Validate exact conservation, capacities and work identity/progress. Every lot
// must match the selected single-recipe profile. A current work serial occurs
// only once, and next_work_id exceeds all present serials. World additionally
// validates the expected roster and serials retained in checkpoint history.
[[nodiscard]] Error validate(const State&, const Config&, const Path&) noexcept;

// A refusal leaves every field unchanged. One step advances only material work;
// the existing command owner still owns revisions, request identity and replay.
// Starting a lot allocates one serial with checked increment. Finishing releases
// that lot once; carried lots do not advance. No transfer restarts their timer.
[[nodiscard]] Error step(State&, const Config&, const Path&);

// Explicit local power under the same fixed tick order and coarse enable.
// A powered absent machine is invalid_path. An inactive machine does not move
// its contents or advance its work; other active machines may continue. State,
// Path and the existing three-argument API keep their original representation
// and behavior. World still owns trusted stepping and mechanical derivation.
[[nodiscard]] Error step(State&, const Config&, const Path&, const MachinePower&);

// Call only after the authoritative adapter has admitted this actor and reach
// and has excluded a cached request. This function is not an admission API.
// The actor must already have canonical Cargo. Retrieval credits products only;
// it neither creates an actor nor converts raw material or work to products.
[[nodiscard]] Error retrieve(State&, const Config&, const Path&,
                             const std::string& actor, Quantity amount);

}  // namespace factory::materials
