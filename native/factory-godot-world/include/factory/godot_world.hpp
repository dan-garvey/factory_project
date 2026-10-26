#pragma once

#include "factory/checkpoint.hpp"

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace factory::godot_world {

// The engine-facing owner of one native World. It has no script Model, second
// quantity store, network endpoint, file or clock. The existing Session and
// ActorWorld producer call this on their owning engine thread.
class Host final {
public:
    [[nodiscard]] values::Value initialize(const std::string& context,
                                          const std::vector<std::string>& actors);
    [[nodiscard]] values::Value initialize_arrival(const std::string& context,
                                                  const std::vector<std::string>& actors);
    // Isolated subsystem fixtures exercise advanced hardware with the same
    // finite stock but without the opening's staged content rule.
    [[nodiscard]] values::Value initialize_arrival_advanced_fixture(const std::string& context,
                                                  const std::vector<std::string>& actors);
    // Trusted terrain producer, separate from the authenticated command wire.
    // Immutable emitted grid vertices are shared with rendered/native collision.
    [[nodiscard]] values::Value configure_terrain(const values::Value::Object&);
    [[nodiscard]] values::Value command(const std::string& bound_actor,
                                       const values::Value::Object& wire);
    [[nodiscard]] values::Value publish_actor(const std::string& actor,
                                             const values::Value::Array& position,
                                             values::Value::Integer epoch);
    // Read only the accepted actor pose for the physical bridge. Full
    // projection also derives every machine's power and material state.
    [[nodiscard]] values::Value actor_projection(const std::string& actor) const;
    [[nodiscard]] values::Value invalidate_actor(const std::string& actor);
    [[nodiscard]] values::Value advance();
    // Trusted tick reader: only fields that World::tick can change. The
    // extension merges these into its last complete projection.
    [[nodiscard]] values::Value advance_tick_fields();
    [[nodiscard]] values::Value projection() const;
    [[nodiscard]] values::Value checkpoint() const;
    [[nodiscard]] values::Value validate_checkpoint(const values::Value&) const;
    [[nodiscard]] values::Value restore_checkpoint(const values::Value&);

private:
    [[nodiscard]] values::Value::Object tick_fields(const world::Snapshot&) const;
    [[nodiscard]] bool settle_manual_cuts(const std::optional<std::string>& observed_actor = std::nullopt);
    [[nodiscard]] values::Value initialize_site(const std::string& context,
                                               const std::vector<std::string>& actors,
                                               bool arrival, bool advanced_fixture = false);
    struct Actor {
        authority::Point position{};
        authority::Integer epoch{};
        bool ready{};
    };
    struct Owned {
        std::unique_ptr<world::World> world;
        std::map<std::string, Actor> actors;
        bool native_started{};
    };
    struct Decoded {
        std::unique_ptr<Owned> candidate;
        std::string refusal;
    };
    struct TransmissionSupport {
        authority::Point foot, bearing;
        std::vector<std::pair<authority::Point, authority::Point>> boxes;
    };

    [[nodiscard]] world::ObserveActor observe() const;
    [[nodiscard]] Decoded decode(const values::Value&) const;
    [[nodiscard]] bool placement_blocked(const authority::Point& center,
                                        const authority::Point& half_extents) const;

    world::Profile profile_;
    std::vector<double> terrain_axis_, terrain_heights_;
    std::vector<std::pair<authority::Point, authority::Point>> terrain_obstacles_;
    std::optional<std::size_t> source_obstacle_index_;
    std::map<std::size_t, std::string> tree_obstacle_sources_;
    [[nodiscard]] bool clear_harvest_path(const world::State& state, const std::string& source,
        const authority::Point& actor, const authority::Point& contact) const;
    [[nodiscard]] values::Value::Object harvest_clearances(const world::State& state,
        const Actor& actor) const;
    [[nodiscard]] bool site_blocked(const authority::Point& low, const authority::Point& high,
        std::optional<std::size_t> ignored = std::nullopt) const;
    [[nodiscard]] std::optional<std::pair<double, double>> terrain_range(double x, double z,
        double half_x = 0.825, double half_z = 0.825) const;
    [[nodiscard]] const char* machine_site_refusal(const world::State&, const mechanics::Point& center,
        bool collector) const;
    [[nodiscard]] const char* component_site_refusal(const world::State& state,
        std::optional<materials::Component> kind, const mechanics::Point& center) const;
    [[nodiscard]] const char* component_space_refusal(const world::State& state,
        std::optional<materials::Component> kind, const mechanics::Point& center,
        const std::string* current_id = nullptr) const;
    [[nodiscard]] const char* supplied_space_refusal(const world::State& state) const;
    [[nodiscard]] std::map<std::string, TransmissionSupport> transmission_supports(const world::State&) const;
    [[nodiscard]] const char* support_change_refusal(const world::State& before,
        const world::State& after, bool preserve_surviving_stands = false) const;
    [[nodiscard]] const char* transmission_site_refusal(const world::State&, const mechanics::Point& center,
        mechanics::Axis axis, bool gear) const;
    [[nodiscard]] const char* wheel_site_refusal(const mechanics::Point& center, mechanics::Axis axis, mechanics::Integer tiles) const;
    [[nodiscard]] const char* collector_site_refusal(const mechanics::Point& center) const;
    std::unique_ptr<Owned> owned_;
};

}  // namespace factory::godot_world
