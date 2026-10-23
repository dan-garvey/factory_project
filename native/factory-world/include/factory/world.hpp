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

struct FreightBeacon {
    std::string id;
    mechanics::Point center{};
    authority::Integer generation{};
    bool operator==(const FreightBeacon&) const = default;
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

struct PressProgressWitness {
    // Whole remaining-tick reductions observed in actual automatic material
    // steps. This is checkpoint evidence, not a second owner of WorkLot state.
    authority::Integer automatic_remaining_ticks{};
    bool manual_seen{};
    bool operator==(const PressProgressWitness&) const = default;
};

[[nodiscard]] mechanics::Point landing_hub_center(const mechanics::Point& pod_center);
[[nodiscard]] mechanics::Point landing_freight_center(const mechanics::Point& pod_center);
// Reversible first-shift order sizes; shipped_products is cumulative physical custody.
inline constexpr authority::Integer repeat_order_target = 3;
inline constexpr authority::Integer completed_freight_target = 1 + repeat_order_target;

// Provisional first-chapter ratings for placed drive components. The same
// values bound native motion and are projected with workshop recipes.
[[nodiscard]] constexpr std::optional<authority::Integer> placed_drive_load_rating(
        materials::Component kind) noexcept {
    switch (kind) {
        case materials::Component::wooden_shaft:
        case materials::Component::wooden_cog: return 8;
        case materials::Component::softmetal_shaft:
        case materials::Component::softmetal_cog: return 24;
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
    std::optional<FreightBeacon> freight_beacon;
    std::optional<HandCrank> hand_crank;
    std::map<std::string, PlacedComponent> placed_components;
    // A finished modular press item retains its work identity while waiting at
    // its outlet. Once it enters a belt, the exported identity remains as a
    // checkpoint witness; material quantities still belong only to Cargo.
    std::map<mechanics::Point, materials::WorkId> press_output_at_exit;
    std::map<mechanics::Point, std::set<materials::WorkId>> press_output_exported;
    std::map<materials::WorkId, PressProgressWitness> press_progress;
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

[[nodiscard]] DrivePower drive_power(const stationary::Topology&);
[[nodiscard]] DrivePower drive_power(const Profile&, const State&);
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
    [[nodiscard]] Advance tick() noexcept;

private:
    World(Profile profile, std::unique_ptr<Owner> owner)
        : profile_(std::move(profile)), owner_(std::move(owner)) {}

    [[nodiscard]] Owner::Decision plan(const Binding&, const Snapshot&,
        const authority::Object&, const ObserveActor&) const;

    Profile profile_;
    std::unique_ptr<Owner> owner_;
    // Tick changes material custody, not the power graph. Commands can change
    // either topology or the drive switch and invalidate this derived result.
    std::optional<DrivePower> tick_drive_;
};

}  // namespace factory::world
