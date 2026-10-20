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
    [[nodiscard]] bool placement_blocked(const authority::Point&) const;

    world::Profile profile_;
    std::unique_ptr<Owned> owned_;
};

}  // namespace factory::godot_world
