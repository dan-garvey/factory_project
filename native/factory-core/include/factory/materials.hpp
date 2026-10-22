#pragma once

#include <array>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace factory::materials {

using Quantity = std::int64_t;
using WorkId = std::int64_t;
using DropPoint = std::array<Quantity, 3>;
inline constexpr std::size_t maximum_drop_points = 256;
inline constexpr Quantity maximum_drop_coordinate = 1000004;
inline constexpr Quantity work_subticks_per_tick = 4096;
inline constexpr Quantity maximum_work_subticks_per_tick = 16 * work_subticks_per_tick;

// Convert a signed shaft rate to distance per tick. Inclined tile centers are
// sqrt(2) farther apart; the same surface speed traverses fewer tile units.
[[nodiscard]] Quantity belt_speed_subticks(Quantity numerator, Quantity denominator, bool inclined) noexcept;

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

// A pure, bounded transport proposal. Each occupied slot carries one raw unit,
// product, or whole work lot. World must validate recipe, identity and total
// custody against its complete State before committing the returned candidate.
inline constexpr std::size_t maximum_belt_slots = 21;
struct BeltLane {
    std::vector<std::optional<Cargo>> slots;
    // Signed fractional distance retained when motion reverses or stops.
    Quantity phase{};
    // Fraction of one subtick retained across ticks and power reversals.
    Quantity remainder{};
    Quantity remainder_denominator{1};
    bool operator==(const BeltLane&) const = default;
};
struct BeltAdvance {
    BeltLane candidate;
    std::vector<Cargo> delivered;
};

// Move at most one slot per unit of fixed-point distance. Positive speed moves
// toward the last slot; negative speed moves toward the first. A full output
// blocks the leading item and propagates backpressure without losing custody.
// The caller supplies speed and receiver capacity from authoritative facts.
// Invalid inputs return no proposal and leave the supplied lane untouched.
[[nodiscard]] std::optional<BeltAdvance> advance_belt_lane(
    const BeltLane&, Quantity signed_subticks, Quantity receiver_capacity);
[[nodiscard]] std::optional<BeltAdvance> advance_belt_lane_rate(
    const BeltLane&, Quantity numerator, Quantity denominator, int direction,
    bool inclined, Quantity receiver_capacity);

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
    // Loose material remains owned by this state even if its belt is removed.
    std::map<DropPoint, Cargo> dropped_material{};
    // Live custody belongs to the one canonical material State, keyed by the
    // World-owned belt span identity. World validates matching geometry.
    std::map<std::string, BeltLane> belt_lanes{};
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
    bool belt_forward{true};
    std::optional<DropPoint> reverse_drop{};
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
    unavailable_drop,
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

// World must first authenticate the actor and admit reach to the exact point.
[[nodiscard]] Error pickup_material(State&, const Config&, const Path&, const std::string&, const DropPoint&);

// Call only after the authoritative adapter has admitted this actor and reach
// and has excluded a cached request. This function is not an admission API.
// The actor must already have canonical Cargo. Retrieval credits products only;
// it neither creates an actor nor converts raw material or work to products.
[[nodiscard]] Error retrieve(State&, const Config&, const Path&,
                             const std::string& actor, Quantity amount);

}  // namespace factory::materials
