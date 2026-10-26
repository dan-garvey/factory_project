#pragma once

#include "factory/value.hpp"

#include <array>
#include <span>
#include <string_view>
#include <variant>

namespace factory::crank_commands {

using Value = values::Value;
using Object = Value::Object;

enum class Action { none, attach, detach, operate, turn, turn_slide };
enum class Type { string, integer, array };

// An absent wire name marks a field derived from current native state. A field
// with both names must survive normalization unchanged, including its type.
struct Field {
    std::string_view wire;
    std::string_view intent;
    Type type;
    bool optional = false;
};

struct Schema {
    std::string_view name;
    std::span<const Field> fields;
};

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

inline bool typed(const Value& value, Type type) {
    switch (type) {
        case Type::string: return std::holds_alternative<std::string>(value.storage());
        case Type::integer: return std::holds_alternative<Value::Integer>(value.storage());
        case Type::array: return std::holds_alternative<Value::Array>(value.storage());
    }
    return false;
}

inline bool valid(const Object& object, Action action, bool intent) {
    if (action == Action::none) return false;
    const auto spec = schema(action);
    const auto found_action = object.find("action");
    if (found_action == object.end() ||
        !std::holds_alternative<std::string>(found_action->second.storage()) ||
        std::get<std::string>(found_action->second.storage()) != spec.name) return false;
    const auto base = intent ?
        std::array<std::string_view, 5>{"context", "client", "request", "actor", "action"} :
        std::array<std::string_view, 5>{"context", "client", "request", "action", ""};
    std::size_t count = intent ? 5 : 4;
    for (const auto name : base) if (!name.empty() && !object.contains(std::string(name))) return false;
    if (intent && object.contains("wire")) {
        if (!std::holds_alternative<Object>(object.at("wire").storage())) return false;
        ++count;
    }
    for (const auto& field : spec.fields) {
        const auto name = intent ? field.intent : field.wire;
        if (name.empty()) continue;
        const auto found = object.find(std::string(name));
        if (found == object.end()) {
            if (!field.optional) return false;
            continue;
        }
        if (!typed(found->second, field.type)) return false;
        ++count;
    }
    return object.size() == count;
}

inline bool valid_wire(const Object& wire, Action action) { return valid(wire, action, false); }
inline bool valid_intent(const Object& intent, Action action) { return valid(intent, action, true); }

inline bool historical_wire(const Object& wire, const Object& intent, Action action) {
    if (!valid_wire(wire, action) || !valid_intent(intent, action)) return false;
    for (const auto& field : schema(action).fields) {
        if (field.wire.empty()) continue;
        const auto original = wire.find(std::string(field.wire));
        const auto normalized = intent.find(std::string(field.intent));
        if (original == wire.end()) {
            if (normalized != intent.end()) return false;
        } else if (normalized == intent.end() ||
                   values::typed_difference(original->second, normalized->second)) return false;
    }
    return true;
}

} // namespace factory::crank_commands
