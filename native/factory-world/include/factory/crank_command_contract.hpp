#pragma once

#include "factory/command_contract.hpp"

#include <array>
#include <string_view>

namespace factory::crank_commands {

using command_contract::Field;
using command_contract::Object;
using command_contract::Schema;
using command_contract::Type;

enum class Action { none, attach, detach, operate, turn, turn_slide };

inline Schema schema(Action action) {
    static constexpr std::array attach{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"crank", "crank", Type::string},
        Field{"", "crank_generation", Type::integer},
        Field{"port", "port", Type::array},
        Field{"face", "face", Type::array, true},
    };
    static constexpr std::array detach{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
    };
    static constexpr std::array operate{
        Field{"", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"entity", "crank", Type::string},
        Field{"", "crank_generation", Type::integer},
        Field{"", "port", Type::array},
        Field{"", "face", Type::array, true},
    };
    static constexpr std::array turn{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
    };
    static constexpr std::array turn_slide{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"port", "port", Type::array},
    };
    switch (action) {
        case Action::attach: return {"attach_hand_crank", attach};
        case Action::detach: return {"detach_hand_crank", detach};
        case Action::operate: return {"operate_hand_crank", operate};
        case Action::turn: return {"turn_hand_crank", turn};
        case Action::turn_slide: return {"turn_slide_crank", turn_slide};
        case Action::none: return {};
    }
    return {};
}

inline Action parse(std::string_view name) {
    for (const auto action : {Action::attach, Action::detach, Action::operate,
                              Action::turn, Action::turn_slide})
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

} // namespace factory::crank_commands
