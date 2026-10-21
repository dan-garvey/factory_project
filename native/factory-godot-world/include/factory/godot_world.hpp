#pragma once

#include "factory/checkpoint.hpp"

#include <map>
#include <memory>
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
    // Trusted terrain producer, separate from the authenticated command wire.
    // Immutable emitted grid vertices are shared with rendered/native collision.
    [[nodiscard]] values::Value configure_terrain(const values::Value::Object&);
    [[nodiscard]] values::Value command(const std::string& bound_actor,
                                       const values::Value::Object& wire);
    [[nodiscard]] values::Value publish_actor(const std::string& actor,
                                             const values::Value::Array& position,
                                             values::Value::Integer epoch);
    [[nodiscard]] values::Value invalidate_actor(const std::string& actor);
    [[nodiscard]] values::Value advance();
    [[nodiscard]] values::Value projection() const;
    [[nodiscard]] values::Value checkpoint() const;
    [[nodiscard]] values::Value validate_checkpoint(const values::Value&) const;
    [[nodiscard]] values::Value restore_checkpoint(const values::Value&);

private:
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

    [[nodiscard]] world::ObserveActor observe() const;
    [[nodiscard]] Decoded decode(const values::Value&) const;
    [[nodiscard]] bool placement_blocked(const authority::Point& center,
                                        const authority::Point& half_extents) const;

    world::Profile profile_;
    std::vector<double> terrain_axis_, terrain_heights_;
    std::vector<std::pair<authority::Point, authority::Point>> terrain_obstacles_;
    [[nodiscard]] bool site_blocked(const authority::Point& low, const authority::Point& high) const;
    [[nodiscard]] std::optional<std::pair<double, double>> terrain_range(double x, double z,
        double half_x = 0.825, double half_z = 0.825) const;
    [[nodiscard]] const char* machine_site_refusal(const world::State&, const mechanics::Point& center) const;
    [[nodiscard]] const char* transmission_obstacle_refusal(const mechanics::Point& center, mechanics::Axis axis, bool gear) const;
    [[nodiscard]] const char* wheel_site_refusal(const mechanics::Point& center, mechanics::Axis axis, mechanics::Integer tiles) const;
    [[nodiscard]] const char* collector_site_refusal(const mechanics::Point& center) const;
    std::unique_ptr<Owned> owned_;
};

}  // namespace factory::godot_world
