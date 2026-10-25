#pragma once

#include "factory/assembly.hpp"
#include "factory/stationary.hpp"
#include "factory/transactions.hpp"
#include "factory/waterwheel.hpp"

#include <array>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace factory::world {

inline constexpr authority::Integer landing_deck_parts = 9;
inline constexpr authority::Integer foundation_timber_cost = 2;
// The ordinary World clock runs every 0.45 seconds. Three ticks give the
// visible hand action roughly one second without making bootstrap gathering a chore.
inline constexpr authority::Integer manual_cut_ticks = 3;
[[nodiscard]] std::array<mechanics::Point, landing_deck_parts> landing_deck_centers(
    const mechanics::Point& center);

// An experimental finite stationary profile, not permanent game content.
// These immutable facts are supplied by trusted startup, never decoded from a
// client command. There is only one canonical material State in the World.
struct Profile {
    materials::Config material;
    materials::Quantity initial_units{};
    std::set<std::string> actors;
    stationary::Kit finite_parts;
    // Trusted hub recipes mint stationary kits from the same finite actor
    // material cargo. The World history accounts for every minted piece.
    std::map<stationary::PartSpec, materials::ComponentCost> fabrication_parts;
    mechanics::Rate waterwheel_rate{1, 1};
    // Optional trusted, immutable site samples keyed by the wheel's X/Z grid
    // coordinates. Heights, radius and velocity use one hundredth of a grid
    // unit; no client supplies a source rate. Empty retains non-site fixtures.
    std::map<std::array<mechanics::Integer, 2>, waterwheel::Sample> water;
    mechanics::Integer wheel_radius{200};
    mechanics::Integer wheel_axle_offset{121};
    double meters_per_grid_unit{1.0};
    authority::Point anchor_offset{};
    double build_reach{4.0};
    // Zero uses build_reach in generic fixtures. Arrival sets the shorter
    // physical cutter reach, independently of construction reach.
    double manual_cut_reach{};
    // Separate construction custody; foundations are not mechanical hubs.
    authority::Integer foundation_parts{};
    // Immutable actor allocation before any construction history. A pod deck
    // spends from the common total but does not grant another actor a kit.
    std::map<std::string, authority::Integer> starting_foundation_kits;
    // Trusted landing-site center in the same quarter-tile grid as foundations.
    // The unfolded 3 x 3 deck spends nine of foundation_parts at startup.
    std::optional<mechanics::Point> landing_pod_center;
    // Trusted ore-facing workcells. The profile, not a client command,
    // decides which placed assemblies can extract from the finite deposit.
    std::vector<assembly::OreFace> collector_faces;
};

struct Foundation {
    mechanics::Point center{}; // X/Z tile centers, Y quarter-pitch top level.
    authority::Integer generation{};
    bool operator==(const Foundation&) const = default;
};

struct LandingPod {
    std::string id;
    mechanics::Point center{};
    authority::Integer generation{};
    bool operator==(const LandingPod&) const = default;
};

struct FabricationHub {
    std::string id;
    mechanics::Point center{};
    authority::Integer generation{};
    // A single issued pod workshop can be unbolted and carried by one actor.
    // Empty means it is installed at center on the common construction grid.
    std::optional<std::string> holder;
    FabricationHub(std::string name, mechanics::Point at, authority::Integer serial,
                   std::optional<std::string> carried_by = std::nullopt)
        : id(std::move(name)), center(at), generation(serial), holder(std::move(carried_by)) {}
    bool operator==(const FabricationHub&) const = default;
};

struct HandCrank {
    std::string id;
    authority::Integer generation{};
    // Empty means the pod tray holds this one physical tool.
    std::optional<std::string> holder;
    bool operator==(const HandCrank&) const = default;
};

struct PlacedComponent {
    materials::Component kind{};
    mechanics::Point center{}; // Absolute quarter-grid location, shared with other constructables.
    authority::Integer generation{};
    bool operator==(const PlacedComponent&) const = default;
};

struct PressAutoTransition {
    authority::Integer revision{};
    mechanics::Point work{};
    authority::Integer before_remaining{};
    authority::Integer after_remaining{};
    bool operator==(const PressAutoTransition&) const = default;
};

struct PressProgressWitness {
    // Native tick records each whole remaining-tick reduction for this WorkId.
    // These are checkpoint consistency evidence, not a second owner of work or
    // authentication of an arbitrarily rewritten checkpoint.
    authority::Integer automatic_remaining_ticks{};
    bool manual_seen{};
    bool refeed_seen{};
    std::vector<PressAutoTransition> automatic_transitions;
    bool operator==(const PressProgressWitness&) const = default;
};

struct PressOffcutDelivery {
    authority::Integer revision{};
    mechanics::Point work{};
    mechanics::Point exit{};
    mechanics::Point receiver{};
    bool operator==(const PressOffcutDelivery&) const = default;
};

[[nodiscard]] mechanics::Point landing_hub_center(const mechanics::Point& pod_center);

inline constexpr authority::Integer slide_cycle_subticks =
    4 * materials::work_subticks_per_tick;

// Provisional first-chapter ratings for placed drive components. The same
// values bound native motion and are projected with workshop recipes.
[[nodiscard]] constexpr std::optional<authority::Integer> placed_drive_load_rating(
        materials::Component kind) noexcept {
    switch (kind) {
        case materials::Component::wooden_shaft:
        case materials::Component::wooden_cog:
        case materials::Component::wooden_slide: return 8;
        case materials::Component::copper_shaft:
        case materials::Component::copper_cog:
        case materials::Component::copper_slide: return 24;
        default: return std::nullopt;
    }
}

struct State {
    materials::State material;
    stationary::Topology topology;
    std::map<std::string, stationary::Kit> kits;
    // Removed identities remain issued. Rebuilding allocates a new identity,
    // rather than retargeting historical receipts to a new physical object.
    std::map<std::string, authority::Integer> issued_entities;
    authority::Integer next_entity_serial{1};
    std::map<std::string, Foundation> foundations;
    std::map<std::string, authority::Integer> foundation_kits;
    std::optional<LandingPod> landing_pod;
    std::optional<FabricationHub> fabrication_hub;
    // Acquiring a formed plate completes the local actor's first workshop once.
    // Later inventory use cannot erase this witnessed chapter milestone.
    std::set<std::string> workshop_completed_actors;
    std::optional<HandCrank> hand_crank;
    std::map<std::string, PlacedComponent> placed_components;
    struct SlidePhase {
        // Four shaft turns make one reciprocal, unloaded carriage cycle.
        authority::Integer subticks{};
        authority::Integer remainder{};
        authority::Integer denominator{1};
        bool operator==(const SlidePhase&) const = default;
    };
    std::map<std::string, SlidePhase> slide_phases;
    struct ManualCut {
        std::string target;
        authority::Integer start_revision{};
        authority::Integer remaining_ticks{};
        // A trusted tick records the first lost-contact revision. An
        // interrupted cut cannot complete after the actor returns.
        authority::Integer interrupted_revision{};
        bool operator==(const ManualCut&) const = default;
    };
    std::map<std::string, ManualCut> manual_cuts;
    // Shared native test setting. Changing it cancels pending manual strokes.
    bool developer_conveniences{};
    // A finished modular press item retains its work identity while waiting at
    // its outlet. Once it enters a belt, the exported identity remains as a
    // checkpoint witness; material quantities still belong only to Cargo.
    std::map<mechanics::Point, materials::WorkId> press_output_at_exit;
    // A fitted outlet tray holds completed identities alongside the physical
    // plate count at that exact exit. Pickup clears both atomically.
    std::map<mechanics::Point, std::set<materials::WorkId>> press_output_at_receiver;
    std::map<mechanics::Point, std::set<materials::WorkId>> press_output_exported;
    std::map<materials::WorkId, PressProgressWitness> press_progress;
    struct ShearProgress {
        mechanics::Point origin{};
        authority::Integer strokes{};
        bool operator==(const ShearProgress&) const = default;
    };
    // An identified sheet keeps its completed cutting strokes through a
    // temporary loss of power. Four strokes consume it into four plate cells.
    std::map<materials::WorkId, ShearProgress> shear_progress;
    // One native tick receipt per automatically sheared offcut delivered to a
    // placed tray. Material quantity remains solely in material.dropped_material.
    std::map<materials::WorkId, PressOffcutDelivery> press_offcut_deliveries;
    // Belt-fed work remains in the same material State. These identity claims
    // distinguish its eventual product from actor-fed press history on restore.
    // Zero denotes a raw blank that has not yet received a WorkId.
    std::map<mechanics::Point, materials::WorkId> belt_press_work;
    std::map<mechanics::Point, std::set<materials::WorkId>> belt_press_products;
    std::set<materials::WorkId> belt_press_work_ids;
    bool operator==(const State&) const = default;
};

using Owner = TransactionOwner<State>;
using Snapshot = Owner::Snapshot;

// One authority tick of signed shaft travel. Returns false if the exact
// fractional phase cannot be represented without overflow.
[[nodiscard]] bool advance_slide_phase(State::SlidePhase& phase, mechanics::Rate rate);

struct Binding {
    // Session authenticates both fields. A client cannot choose another actor
    // or reuse another namespace to retrieve its cached requests.
    std::string actor;
    std::string client;
};

using ObserveActor = std::function<std::optional<authority::ActorCut>(const std::string&)>;

// Provisional speed-weighted load and source capacity for an entire connected
// component. Values are derived from World topology, never client supplied.
struct NetworkLoad {
    double capacity{};
    double impact{};
    bool overloaded{};
    // Actual placed part when its material rating is the limiting capacity.
    std::string limiting_part;
    bool operator==(const NetworkLoad&) const = default;
};
struct DrivePower {
    mechanics::Result mechanical;
    std::map<std::string, NetworkLoad> load;
};

enum class BroadPressDriveStatus {
    ready, invalid_power, invalid_geometry, unpowered, stopped, stalled,
    incompatible_axis, mismatched_rate, disconnected,
};

struct BroadPressDriveInspection {
    BroadPressDriveStatus status{BroadPressDriveStatus::invalid_power};
    std::optional<mechanics::Rate> stroke_rate;
    std::array<int, 4> pad_winding{};
};

// One index over a confirmed mechanical cut serves every four-cell candidate.
// Equal rates on separate networks are insufficient: the four cams must share
// one mechanically constrained component. The mirrored pad winding derives
// from its broad work-face row or column and is projected for visible art.
class BroadPressDriveIndex {
public:
    explicit BroadPressDriveIndex(const DrivePower& power);
    [[nodiscard]] BroadPressDriveInspection inspect(const assembly::BroadPress& press) const;
    [[nodiscard]] BroadPressDriveInspection inspect(const assembly::BroadShear& shear) const;
private:
    const DrivePower& power_;
    std::map<std::string, std::size_t> component_by_part_;
};

[[nodiscard]] DrivePower drive_power(const stationary::Topology&);
[[nodiscard]] DrivePower drive_power(const Profile&, const State&);
// A held crank engages one exposed X-side port for one command. This projects
// a temporary source into the same native graph; it is never a placed part.
[[nodiscard]] DrivePower hand_slide_power(const Profile&, const State&,
    const std::string& slide, const mechanics::Point& port);
[[nodiscard]] materials::Path material_path(const stationary::Topology&);
[[nodiscard]] materials::MachinePower machine_power(const stationary::Topology&);
[[nodiscard]] materials::MachinePower machine_power(const stationary::Topology&, const DrivePower&);
[[nodiscard]] materials::MachinePower machine_power(const Profile&, const State&);
[[nodiscard]] bool validate(const Profile&, const Snapshot&);

// Native domain implementation, still unadopted. Session remains the transport
// and authentication owner; Store remains the file owner. No body setter,
// registration, JSON import, fallback Model or second live clock is provided.
class World final {
public:
    [[nodiscard]] static std::unique_ptr<World> create(
        std::string context, Profile profile, const State& seed);
    [[nodiscard]] static std::unique_ptr<World> restore(
        const std::string& expected_context, Profile profile, const Snapshot& saved);

    [[nodiscard]] Snapshot snapshot() const { return owner_->snapshot(); }
    [[nodiscard]] bool has_manual_cuts() const noexcept {
        return !owner_->snapshot_ref().state.manual_cuts.empty();
    }

    // Exact retries are resolved before calling the host observation provider or
    // inspecting current targets. Fresh operations require literal scalar 3D
    // reach to canonical anchors. Placement targets use the validated grid scale.
    // The provider runs synchronously on the authority thread and must describe
    // its registered producer; no client-supplied observation enters this API.
    [[nodiscard]] Delivery command(const Binding&, const authority::Object&,
                                   const ObserveActor&) noexcept;
    // Cache a trusted adapter's schema/site refusal in this same request owner.
    // The adapter still authenticates the caller, and exact retries win first.
    [[nodiscard]] Delivery refuse(const Binding&, const authority::Object&,
                                  std::string reason) noexcept;

    // Called only by the owning host's simulation loop. Local machine power is
    // derived from current geometry, with no client tick or arbitrary edge API.
    [[nodiscard]] Advance tick(const ObserveActor& observe = {}) noexcept;

private:
    World(Profile profile, std::unique_ptr<Owner> owner)
        : profile_(std::move(profile)), owner_(std::move(owner)) {}

    [[nodiscard]] Owner::Decision plan(const Binding&, const Snapshot&,
        const authority::Object&, const ObserveActor&) const;

    Profile profile_;
    std::unique_ptr<Owner> owner_;
    struct TickLayout {
        std::vector<assembly::Part> placed;
        assembly::Layout layout;
        std::map<mechanics::Point, std::optional<assembly::Collector>> collectors_by_receiver;
        std::vector<std::pair<mechanics::Point, assembly::PressInspection>> presses_by_frame;
        std::vector<std::pair<mechanics::Point, assembly::GuidedPressInspection>> presses_by_anvil;
        std::vector<assembly::BroadPress> broad_presses;
        TickLayout(std::vector<assembly::Part> parts, const std::vector<assembly::OreFace>& faces)
            : placed(std::move(parts)), layout(placed) {
            // These inspections depend only on placed geometry. A material-only
            // tick cannot change them, while every command invalidates this cut.
            for (const auto& face : faces) {
                const auto inspected = layout.inspect_collector(face);
                if (!inspected.collector) continue;
                const auto [entry, inserted] = collectors_by_receiver.emplace(
                    inspected.collector->receiver_center, *inspected.collector);
                if (!inserted) entry->second.reset();
            }
            for (const auto& part : placed)
                if (part.kind == materials::Component::wooden_frame)
                    presses_by_frame.emplace_back(part.center, layout.inspect_press(part.center));
                else if (part.kind == materials::Component::anvil) {
                    presses_by_anvil.emplace_back(part.center, layout.inspect_guided_press(part.center));
                    const auto broad = layout.inspect_broad_press(part.center);
                    if (broad.press) broad_presses.push_back(*broad.press);
                }
        }
    };
    // Tick changes material custody, not the power graph. Commands can change
    // either topology or the drive switch and invalidate these derived views.
    std::unique_ptr<TickLayout> tick_layout_;
    std::optional<DrivePower> tick_drive_;
};

}  // namespace factory::world
