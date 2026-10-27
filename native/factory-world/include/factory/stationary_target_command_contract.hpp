#pragma once

#include "factory/command_contract.hpp"

#include <array>
#include <string_view>

namespace factory::stationary_target_commands {

using command_contract::Field;
using command_contract::Object;
using command_contract::Schema;
using command_contract::Type;

enum class Action {
    none, remove, recover, collect, insert_raw, insert_work,
    shaft_between, remove_shaft_between, set_drive,
};

inline Schema schema(Action action) {
    static constexpr std::array target{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
    };
    static constexpr std::array amount{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"amount", "amount", Type::integer},
    };
    static constexpr std::array work{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"work_id", "work_id", Type::integer},
    };
    static constexpr std::array endpoints{
        Field{"from", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"to", "to", Type::string},
        Field{"", "to_generation", Type::integer},
    };
    static constexpr std::array drive{
        Field{"", "target", Type::string},
        Field{"", "generation", Type::integer},
        Field{"", "enabled", Type::boolean},
    };
    switch (action) {
        case Action::remove: return {"remove", target};
        case Action::recover: return {"recover", target};
        case Action::collect: return {"collect", amount};
        case Action::insert_raw: return {"insert_raw", amount};
        case Action::insert_work: return {"insert_work", work};
        case Action::shaft_between: return {"shaft_between", endpoints};
        case Action::remove_shaft_between: return {"remove_shaft_between", endpoints};
        case Action::set_drive: return {"set_drive", drive};
        case Action::none: return {};
    }
    return {};
}

inline Action parse(std::string_view name) {
    for (const auto action : {Action::remove, Action::recover, Action::collect,
                              Action::insert_raw, Action::insert_work,
                              Action::shaft_between, Action::remove_shaft_between,
                              Action::set_drive})
        if (schema(action).name == name) return action;
    return Action::none;
}

inline std::string_view wire_name(Action action) {
    switch (action) {
        case Action::collect: return "retrieve";
        case Action::shaft_between: return "connect_drive";
        case Action::remove_shaft_between: return "disconnect_drive";
        case Action::set_drive: return {};
        default: return schema(action).name;
    }
}

inline Schema wire_schema(Action action) { return {wire_name(action), schema(action).fields}; }

inline Action parse_wire(std::string_view name) {
    for (const auto action : {Action::remove, Action::recover, Action::collect,
                              Action::insert_raw, Action::insert_work,
                              Action::shaft_between, Action::remove_shaft_between})
        if (wire_name(action) == name) return action;
    return Action::none;
}

// Host derives target generations from its snapshot. Defer secondary field
// types until World checks the normalized command, preserving refusal order.
inline bool valid_wire_before_target(const Object& wire, Action action) {
    static constexpr std::array<std::string_view, 3> deferred{"to", "amount", "work_id"};
    return command_contract::valid(wire, wire_schema(action), false, deferred);
}

// World checks target identity and generation after the command shape.
inline bool valid_intent_before_target(const Object& intent, Action action) {
    static constexpr std::array<std::string_view, 4> deferred{
        "target", "generation", "to", "to_generation"};
    return command_contract::valid(intent, schema(action), true, deferred);
}

inline bool historical_wire(const Object& wire, const Object& intent, Action action) {
    if (action == Action::set_drive) return false;
    // Host admits these fields before World checks their types. A refused
    // malformed request remains a valid saved receipt when both copies agree.
    static constexpr std::array<std::string_view, 2> deferred{"amount", "work_id"};
    if (!command_contract::valid(wire, wire_schema(action), false, deferred) ||
        !command_contract::valid(intent, schema(action), true, deferred)) return false;
    for (const auto& field : schema(action).fields) {
        if (field.wire.empty()) continue;
        const auto original = wire.find(std::string(field.wire));
        const auto normalized = intent.find(std::string(field.intent));
        if (original == wire.end() || normalized == intent.end() ||
            values::typed_difference(original->second, normalized->second)) return false;
    }
    return true;
}

} // namespace factory::stationary_target_commands
