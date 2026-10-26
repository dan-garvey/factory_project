#pragma once

#include "factory/command_contract.hpp"

#include <array>
#include <string_view>

namespace factory::belt_commands {

using command_contract::Field;
using command_contract::Object;
using command_contract::Schema;
using command_contract::Type;

enum class Action { none, place, place_selected, remove, select, recover_slot, load_slot };

inline Schema schema(Action action) {
    static constexpr std::array place{
        Field{"from", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"to", "to", Type::string},
        Field{"", "to_generation", Type::integer},
    };
    static constexpr std::array place_selected{
        Field{"from", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"to", "to", Type::string},
        Field{"", "to_generation", Type::integer},
        Field{"selection", "selection", Type::string},
    };
    static constexpr std::array target{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
    };
    static constexpr std::array recover_slot{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"slot", "slot", Type::integer},
        Field{"expected", "expected", Type::object},
    };
    static constexpr std::array load_slot{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"slot", "slot", Type::integer},
        Field{"item", "item", Type::string},
        Field{"work_id", "work_id", Type::integer},
    };
    switch (action) {
        case Action::place: return {"place_belt_span", place};
        case Action::place_selected: return {"place_selected_belt_span", place_selected};
        case Action::remove: return {"remove_belt_span", target};
        case Action::select: return {"select_belt_shaft", target};
        case Action::recover_slot: return {"recover_belt_slot", recover_slot};
        case Action::load_slot: return {"load_belt_slot", load_slot};
        case Action::none: return {};
    }
    return {};
}

inline Action parse(std::string_view name) {
    for (const auto action : {Action::place, Action::place_selected, Action::remove,
                              Action::select, Action::recover_slot, Action::load_slot})
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

} // namespace factory::belt_commands
