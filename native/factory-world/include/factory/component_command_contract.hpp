#pragma once

#include "factory/command_contract.hpp"

#include <array>
#include <string_view>

namespace factory::component_commands {

using command_contract::Field;
using command_contract::Object;
using command_contract::Schema;
using command_contract::Type;

enum class Action { none, place, reclaim };

inline Schema schema(Action action) {
    static constexpr std::array place{
        Field{"component", "component", Type::string},
        Field{"center", "center", Type::array},
    };
    static constexpr std::array reclaim{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
    };
    switch (action) {
        case Action::place: return {"place_component", place};
        case Action::reclaim: return {"reclaim_component", reclaim};
        case Action::none: return {};
    }
    return {};
}

inline Action parse(std::string_view name) {
    for (const auto action : {Action::place, Action::reclaim})
        if (schema(action).name == name) return action;
    return Action::none;
}

inline bool valid_wire(const Object& wire, Action action) {
    return command_contract::valid_wire(wire, schema(action));
}
inline bool valid_intent(const Object& intent, Action action) {
    return command_contract::valid_intent(intent, schema(action));
}
inline bool historical_wire(const Object& wire, const Object& intent, Action action) {
    return command_contract::historical_wire(wire, intent, schema(action));
}

} // namespace factory::component_commands
