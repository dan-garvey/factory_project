#pragma once

#include "factory/command_contract.hpp"

#include <array>
#include <string_view>

namespace factory::press_commands {

using command_contract::Field;
using command_contract::Object;
using command_contract::Schema;
using command_contract::Type;

enum class Action { none, stroke_shear, feed, feed_broad, refeed_broad, compact, refeed, turn };

inline Schema schema(Action action) {
    static constexpr std::array stroke_shear{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"sheet_id", "sheet_id", Type::integer},
    };
    static constexpr std::array feed{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"entry", "entry", Type::array},
    };
    static constexpr std::array feed_broad{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
    };
    static constexpr std::array refeed_broad{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"work_id", "work_id", Type::integer},
    };
    static constexpr std::array compact{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"entry", "entry", Type::array},
        Field{"drive", "drive", Type::string},
    };
    static constexpr std::array refeed{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"entry", "entry", Type::array},
        Field{"work_id", "work_id", Type::integer},
    };
    static constexpr std::array turn{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"drive", "drive", Type::string},
        Field{"exit", "exit", Type::array},
    };
    switch (action) {
        case Action::stroke_shear: return {"stroke_broad_shear", stroke_shear};
        case Action::feed: return {"feed_press", feed};
        case Action::feed_broad: return {"feed_broad_press", feed_broad};
        case Action::refeed_broad: return {"refeed_broad_press_work", refeed_broad};
        case Action::compact: return {"compact_offcuts", compact};
        case Action::refeed: return {"refeed_press_work", refeed};
        case Action::turn: return {"turn_press_crank", turn};
        case Action::none: return {};
    }
    return {};
}

inline Action parse(std::string_view name) {
    for (const auto action : {Action::stroke_shear, Action::feed, Action::feed_broad,
                              Action::refeed_broad, Action::compact, Action::refeed,
                              Action::turn})
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

} // namespace factory::press_commands
