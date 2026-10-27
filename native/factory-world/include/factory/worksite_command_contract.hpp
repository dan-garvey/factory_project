#pragma once

#include "factory/command_contract.hpp"

#include <array>
#include <string_view>

namespace factory::worksite_commands {

using command_contract::Field;
using command_contract::Object;
using command_contract::Schema;
using command_contract::Type;

enum class Action { none, harvest, fast_harvest, finish_harvest, cancel_harvest, developer_conveniences };

inline Schema schema(Action action) {
    static constexpr std::array harvest{Field{"target", "target", Type::string}};
    static constexpr std::array toggle{Field{"enabled", "enabled", Type::boolean}};
    static constexpr std::array<Field, 0> empty{};
    switch (action) {
        case Action::harvest: return {"harvest_source", harvest};
        case Action::fast_harvest: return {"fast_harvest_source", harvest};
        case Action::finish_harvest: return {"finish_harvest", empty};
        case Action::cancel_harvest: return {"cancel_harvest", empty};
        case Action::developer_conveniences: return {"set_developer_conveniences", toggle};
        case Action::none: return {};
    }
    return {};
}

// Fast harvest is selected from native state after an ordinary harvest_source
// request. It has no separate player wire action.
inline Schema wire_schema(Action action) {
    const auto selected = schema(action);
    return {action == Action::fast_harvest ? schema(Action::harvest).name : selected.name,
        selected.fields};
}

inline Action parse_wire(std::string_view name) {
    for (const auto action : {Action::harvest, Action::finish_harvest,
                              Action::cancel_harvest, Action::developer_conveniences})
        if (schema(action).name == name) return action;
    return Action::none;
}

inline Action parse_intent(std::string_view name) {
    for (const auto action : {Action::harvest, Action::fast_harvest,
                              Action::finish_harvest, Action::cancel_harvest,
                              Action::developer_conveniences})
        if (schema(action).name == name) return action;
    return Action::none;
}

inline bool valid_wire(const Object& wire, Action action) {
    return command_contract::valid_wire(wire, wire_schema(action));
}

inline bool valid_intent(const Object& intent, Action action) {
    return command_contract::valid_intent(intent, schema(action));
}

inline bool historical_wire(const Object& wire, const Object& intent, Action action) {
    if (action != Action::fast_harvest)
        return command_contract::historical_wire(wire, intent, schema(action));
    if (!valid_wire(wire, action) || !valid_intent(intent, action)) return false;
    return !values::typed_difference(wire.at("target"), intent.at("target"));
}

} // namespace factory::worksite_commands
