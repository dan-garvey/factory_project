#pragma once

#include "factory/authority_boundary.hpp"

#include <optional>
#include <set>
#include <string>
#include <variant>

namespace factory::godot_world::command_admission {

using Object = values::Value::Object;

struct BoundActor {
    std::string actor;
    std::string client;
};

struct Refusal {
    const char* reason;
};

struct Replay {
    Object intent;
};

struct Fresh {
    Object normalized;
};

using Decision = std::variant<Refusal, Replay, Fresh>;

// This only admits and translates the envelope. World owns request history,
// duplicate matching, action rules and every resulting state change.
[[nodiscard]] std::optional<BoundActor> bind_actor(const std::set<std::string>& actors,
    const std::string& bound_actor, const Object& wire);
[[nodiscard]] Decision examine(const BoundActor& bound,
    const authority::History& history, const Object& wire);

}  // namespace factory::godot_world::command_admission
