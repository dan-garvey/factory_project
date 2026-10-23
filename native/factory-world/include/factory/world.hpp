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

[[nodiscard]] mechanics::Point landing_hub_center(const mechanics::Point& pod_center);

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
    std::optional<HandCrank> hand_crank;
    std::map<std::string, PlacedComponent> placed_components;
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
};

}  // namespace factory::world
