#pragma once

#include "factory/command_contract.hpp"

#include <array>
#include <string_view>

namespace factory::material_commands {

using command_contract::Field;
using command_contract::Object;
using command_contract::Schema;
using command_contract::Type;

enum class Action { none, pickup, place_sheet, push_sheet, push_small };

inline Schema schema(Action action) {
    static constexpr std::array pickup{
        Field{"center", "center", Type::array},
        Field{"expected", "expected", Type::object},
    };
    static constexpr std::array place_sheet{
        Field{"center", "center", Type::array},
        Field{"sheet_id", "sheet_id", Type::integer},
    };
    static constexpr std::array push_sheet{
        Field{"from", "from", Type::array},
        Field{"to", "to", Type::array},
        Field{"sheet_id", "sheet_id", Type::integer},
    };
    static constexpr std::array push_small{
        Field{"from", "from", Type::array},
        Field{"to", "to", Type::array},
        Field{"form", "form", Type::string},
    };
    switch (action) {
        case Action::pickup: return {"pickup_material", pickup};
        case Action::place_sheet: return {"place_sheet", place_sheet};
        case Action::push_sheet: return {"push_channel_sheet", push_sheet};
        case Action::push_small: return {"push_channel_small", push_small};
        case Action::none: return {};
    }
    return {};
}

inline Action parse(std::string_view name) {
    for (const auto action : {Action::pickup, Action::place_sheet,
                              Action::push_sheet, Action::push_small})
        if (schema(action).name == name) return action;
    return Action::none;
}

inline bool valid_wire(const Object& wire, Action action) {
    return command_contract::valid_wire(wire, schema(action));
}
// Host reports malformed physical points as invalid_center after the exact
// command keys and all non-point value types have been checked here.
inline bool valid_wire_before_geometry(const Object& wire, Action action) {
    static constexpr std::array<std::string_view, 1> center{"center"};
    static constexpr std::array<std::string_view, 2> endpoints{"from", "to"};
    const std::span<const std::string_view> deferred =
        action == Action::pickup || action == Action::place_sheet ?
            std::span<const std::string_view>(center) :
            std::span<const std::string_view>(endpoints);
    return command_contract::valid(wire, schema(action), false, deferred);
}
inline bool valid_intent(const Object& intent, Action action) {
    return command_contract::valid_intent(intent, schema(action));
}
// The direct World pickup path has historically reported invalid_center for a
// present center with the wrong type; its planner still checks that geometry.
inline bool valid_pickup_intent_before_geometry(const Object& intent) {
    static constexpr std::array<std::string_view, 1> center{"center"};
    return command_contract::valid(intent, schema(Action::pickup), true, center);
}
inline bool historical_wire(const Object& wire, const Object& intent, Action action) {
    return command_contract::historical_wire(wire, intent, schema(action));
}

} // namespace factory::material_commands
