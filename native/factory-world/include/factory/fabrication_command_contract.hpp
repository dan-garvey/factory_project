#pragma once

#include "factory/command_contract.hpp"

#include <array>
#include <string_view>

namespace factory::fabrication_commands {

using command_contract::Field;
using command_contract::Object;
using command_contract::Schema;
using command_contract::Type;

enum class Action { none, field_craft, foundation, component, part, stow_hub, deploy_hub };

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
        Field{"teeth", "teeth", Type::integer, true},
        Field{"half_span", "half_span", Type::integer},
    };
    static constexpr std::array stow_hub{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
    };
    static constexpr std::array deploy_hub{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"center", "center", Type::array},
    };
    switch (action) {
        case Action::field_craft: return {"field_craft", field_craft};
        case Action::foundation: return {"craft_foundation", foundation};
        case Action::component: return {"craft_component", component};
        case Action::part: return {"craft_part", part};
        case Action::stow_hub: return {"stow_fabrication_hub", stow_hub};
        case Action::deploy_hub: return {"deploy_fabrication_hub", deploy_hub};
        case Action::none: return {};
    }
    return {};
}

inline Action parse(std::string_view name) {
    for (const auto action : {Action::field_craft, Action::foundation,
                              Action::component, Action::part,
                              Action::stow_hub, Action::deploy_hub})
        if (schema(action).name == name) return action;
    return Action::none;
}

inline bool sized_part(const Object& command, Action action) {
    if (action != Action::part) return true;
    const auto found = command.find("role");
    return found != command.end() &&
        std::holds_alternative<std::string>(found->second.storage()) &&
        (std::get<std::string>(found->second.storage()) == "gear") == command.contains("teeth");
}
inline bool valid_wire(const Object& wire, Action action) {
    return command_contract::valid_wire(wire, schema(action)) && sized_part(wire, action);
}
// Host has historically reported a present malformed deploy center as
// invalid_center after checking the other wire fields.
inline bool valid_hub_wire_before_geometry(const Object& wire, Action action) {
    if (action == Action::stow_hub) return valid_wire(wire, action);
    if (action != Action::deploy_hub) return false;
    static constexpr std::array<std::string_view, 1> center{"center"};
    return command_contract::valid(wire, schema(action), false, center);
}
inline bool valid_intent(const Object& intent, Action action) {
    return command_contract::valid_intent(intent, schema(action)) && sized_part(intent, action);
}
inline bool historical_wire(const Object& wire, const Object& intent, Action action) {
    return valid_wire(wire, action) && valid_intent(intent, action) &&
        command_contract::historical_wire(wire, intent, schema(action));
}

} // namespace factory::fabrication_commands
