#pragma once

#include "factory/command_contract.hpp"

#include <array>
#include <string_view>

namespace factory::fabrication_commands {

using command_contract::Field;
using command_contract::Object;
using command_contract::Schema;
using command_contract::Type;

enum class Action { none, field_craft, foundation, component, part };

inline Schema schema(Action action) {
    static constexpr std::array field_craft{
        Field{"component", "component", Type::string},
    };
    static constexpr std::array foundation{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
    };
    static constexpr std::array component{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"component", "component", Type::string},
    };
    static constexpr std::array part{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"role", "role", Type::string},
        Field{"half_span", "half_span", Type::integer},
    };
    switch (action) {
        case Action::field_craft: return {"field_craft", field_craft};
        case Action::foundation: return {"craft_foundation", foundation};
        case Action::component: return {"craft_component", component};
        case Action::part: return {"craft_part", part};
        case Action::none: return {};
    }
    return {};
}

inline Action parse(std::string_view name) {
    for (const auto action : {Action::field_craft, Action::foundation,
                              Action::component, Action::part})
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

} // namespace factory::fabrication_commands
