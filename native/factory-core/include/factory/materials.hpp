#pragma once

#include <array>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace factory::materials {

using Quantity = std::int64_t;
using WorkId = std::int64_t;
using DropPoint = std::array<Quantity, 3>;
inline constexpr std::size_t maximum_drop_points = 4096;
inline constexpr std::size_t maximum_belt_lanes = 4096;
inline constexpr std::size_t maximum_live_work_lots = 4096;
inline constexpr Quantity maximum_drop_coordinate = 1000004;
// A fitted tray holds four one-unit copper offcuts before its work face stalls.
inline constexpr Quantity press_offcut_receiver_capacity = 4;
inline constexpr Quantity press_plate_receiver_capacity = 4;
inline constexpr Quantity work_subticks_per_tick = 4096;
inline constexpr Quantity maximum_work_subticks_per_tick = 16 * work_subticks_per_tick;

// Convert a signed shaft rate to distance per tick. Inclined tile centers are
// sqrt(2) farther apart; the same surface speed traverses fewer tile units.
[[nodiscard]] Quantity belt_speed_subticks(Quantity numerator, Quantity denominator, bool inclined) noexcept;

// Canonical data for the unadopted finite material fixture. The sole World and
// its command, admission and persistence boundaries remain separate.

enum class WorkOutput { plate, sheet };

struct RecipeSignature {
    Quantity input_units_per_product{1};
    Quantity cycle_ticks{2};
    WorkOutput output{WorkOutput::plate};
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
    Quantity work_remainder{};
    Quantity work_remainder_denominator{1};
    bool operator==(const WorkLot&) const = default;
};

// Apply one trusted signed-drive magnitude to an already authenticated lot.
// Callers still own power, geometry and material-custody validation.
void advance_work_lot(WorkLot&, Quantity subticks, Quantity remainder,
                      Quantity remainder_denominator) noexcept;

// The same serial survives the transition from one broad work batch to its
// finished sheet. Rotation is a horizontal quarter turn relative to the
// work-face origin; its 2x2 footprint remains one item until the shear.
struct Sheet {
    WorkId id{};
    Quantity rotation{};
    bool operator==(const Sheet&) const = default;
};

// The initial chapter bill has no intermediate recipe inputs: every component
// is made directly from carried timber or copper ore. These IDs are stable
// within the experimental arrival checkpoint, not a final item catalogue.
enum class Component {
    wooden_frame,
    wooden_shaft,
    wooden_cog,
    receiver_tray,
    tool_mount,
    sliding_guide,
    cutting_edge,
    anvil,
    ram_face,
    copper_shaft,
    copper_cog,
    wooden_workbench,
    wooden_slide,
    copper_slide,
};

struct ComponentCost {
    Quantity timber{};
    Quantity ore{};
    bool operator==(const ComponentCost&) const = default;
};

[[nodiscard]] const char* component_name(Component component) noexcept;
[[nodiscard]] std::optional<Component> component_from_name(const std::string& name) noexcept;
[[nodiscard]] std::optional<ComponentCost> component_cost(Component component) noexcept;

struct Cargo {
    Quantity raw_units{};
    Quantity products{};
    std::vector<WorkLot> work_lots;
    // Copper forming retains the difference between a four-unit stock chunk
    // and a three-unit plate. Sheets are separate twelve-unit items with
    // retained identity and orientation, not an inventory count.
    Quantity offcuts{};
    std::vector<Sheet> sheets;
    // Unshaped timber stays in the same authoritative actor cargo as ore.
    // Existing machine buffers and belts do not accept timber yet.
    Quantity timber{};
    // Crafted parts remain in the same actor custody ledger as their inputs.
    std::map<Component, Quantity> components;
    Cargo() = default;
    Cargo(Quantity raw, Quantity finished, std::vector<WorkLot> lots, Quantity wood = 0)
        : raw_units(raw), products(finished), work_lots(std::move(lots)), timber(wood) {}
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

struct TimberSite {
    DropPoint center{}; // The common quarter-tile world grid.
    Quantity initial{};
    bool operator==(const TimberSite&) const = default;
};

struct OreSite {
    std::string id;
    DropPoint center{};
    bool operator==(const OreSite&) const = default;
};

// These are revisable fixture values, supplied by the caller, not game content.
struct Config {
    Quantity input_units_per_product{1};
    Quantity collector_capacity{1};
    Quantity cycle_ticks{2};
    std::map<std::string, TimberSite> timber_sites;
    std::optional<OreSite> manual_ore;
    Quantity hand_carry_capacity{32};
    Quantity component_capacity{24};
    Quantity raw_mass{1};
    // Zero keeps the existing whole-input recipe mass for non-copper fixtures.
    Quantity plate_mass{};
    Quantity sheet_mass{};
    Config() = default;
    Config(Quantity input, Quantity capacity, Quantity ticks)
        : input_units_per_product(input), collector_capacity(capacity), cycle_ticks(ticks) {}
};

struct Stock {
    Quantity source{};
    Quantity collector{};
    Quantity belt{};
    Quantity input{};
    Quantity output{};
    Quantity offcuts{};
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
    // Each site's initial quantity is immutable Config; only these remaining
    // quantities move into actor cargo through the World request owner.
    std::map<std::string, Quantity> timber_remaining{};
    // World owns geometry and identity; this count keeps installed parts in
    // the same conserved material ledger as actor cargo and recipe inputs.
    std::map<Component, Quantity> placed_components{};
    // Material embodied in fabricated stationary kits and their installed
    // parts. World matches these totals to accepted fabrication history and
    // the exact native kit/topology census.
    Quantity fabricated_timber{};
    Quantity fabricated_raw{};
    State() = default;
    State(Quantity initial, Stock contents, std::map<std::string, Cargo> actors,
          std::optional<WorkLot> work, WorkId serial)
        : initial_units(initial), stock(contents), cargo(std::move(actors)),
          processing(std::move(work)), next_work_id(serial) {}
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
    Quantity processor_work_remainder{};
    Quantity processor_work_remainder_denominator{1};
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
    unavailable_source,
    inventory_full,
    unavailable_recipe,
    unavailable_input,
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

// A placed press uses the same work clock and material ledger as the legacy
// processor. World authenticates the crank, assembly, selected exit and reach.
// The first turn starts a lot; later turns advance it one tick. A ready lot
// waits at the work point until its physical exit can receive the product.
[[nodiscard]] Error turn_press(State&, const Config&, const Path&,
                               const DropPoint& work, const DropPoint& exit,
                               bool plate_receiver = false);

// World admits the four-cell contact, actor reach, live coupled drive and
// outlet footprint before these custody changes. Feeding moves three carried
// stock chunks to one supported work area; turning keeps one serial and exact
// partial progress until one oriented twelve-mass sheet occupies that area.
[[nodiscard]] Error feed_broad_press(State&, const Config&, const Path&,
                                     const std::string& actor, const DropPoint& work,
                                     std::optional<WorkId> carried_work = std::nullopt);
[[nodiscard]] Error turn_broad_press(State&, const Config&, const Path&,
                                     const DropPoint& work, Quantity output_rotation,
                                     Quantity work_subticks = work_subticks_per_tick,
                                     Quantity work_remainder = 0,
                                     Quantity work_remainder_denominator = 1);

// World authenticates the four-cell support, clearance and actor reach before
// a carried sheet is placed. The sheet keeps its serial and orientation.
[[nodiscard]] Error place_sheet(State&, const Config&, const Path&,
                                const std::string& actor, WorkId sheet_id,
                                const DropPoint& origin);

// World authenticates the four supported cutting cells, full-width blade,
// stroke clearance, live drive and exact progress. Core then exchanges one
// identified twelve-mass sheet for four separately collectible plates at the
// same four cells. Occupied output leaves the entire sheet unchanged.
[[nodiscard]] Error shear_sheet(State&, const Config&, const Path&,
                                WorkId sheet_id, const DropPoint& origin);

// A ready press may compact exactly one stock chunk's mass of recovered
// copper offcuts at its clear work point. World authenticates the assembled
// press, crank holder and physical reach before this custody transfer.
[[nodiscard]] Error compact_offcuts(State&, const Config&, const Path&,
                                    const std::string& actor, const DropPoint& work);

// World supplies only ready, rotating modular presses with unique work and
// exit points. All supplied presses advance in one candidate material state,
// so many local machines do not copy and validate the entire ledger each.
// A missing or incompatible work item and an occupied exit pause that press.
struct PressStep {
    DropPoint work{};
    DropPoint exit{};
    // World supplies this only for one unambiguous, physically placed tray.
    // Without a tray the offcut stays at the work point for manual recovery.
    std::optional<DropPoint> offcut_receiver{};
    Quantity work_subticks{work_subticks_per_tick};
    Quantity work_remainder{};
    Quantity work_remainder_denominator{1};
    // A fitted plate tray can retain four distinct completed workpieces at
    // the exit. World owns the tray geometry and the work identity ledger.
    bool plate_receiver{};
    bool operator==(const PressStep&) const = default;
};
[[nodiscard]] Error step_presses(State&, const Config&, const Path&,
                                 const std::vector<PressStep>&);

// World must first authenticate the actor and admit reach to the exact point.
[[nodiscard]] Error pickup_material(State&, const Config&, const Path&, const std::string&, const DropPoint&);

// World authenticates the actor, target identity and physical reach first.
// The existing ore source feeds both hand extraction and the collector.
[[nodiscard]] Error harvest_source(State&, const Config&, const Path&,
                                   const std::string& actor, const std::string& source_id);

// World authenticates the actor and admits local hub/tool reach before calling.
// Each recipe consumes only raw carried inputs and credits one typed part.
[[nodiscard]] Error craft_component(State&, const Config&, const Path&,
                                    const std::string& actor, Component component);

// Call only after the authoritative adapter has admitted this actor and reach
// and has excluded a cached request. This function is not an admission API.
// The actor must already have canonical Cargo. Retrieval credits products only;
// it neither creates an actor nor converts raw material or work to products.
[[nodiscard]] Error retrieve(State&, const Config&, const Path&,
                             const std::string& actor, Quantity amount);

}  // namespace factory::materials
