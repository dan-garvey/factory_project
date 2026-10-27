#pragma once

#include "factory/value.hpp"

#include <array>
#include <span>
#include <string>
#include <string_view>
#include <variant>

namespace factory::command_contract {

using Value = values::Value;
using Object = Value::Object;

enum class Type { string, integer, boolean, array, object };

// An absent wire name marks a field derived from native state. Matching wire
// and intent names must retain their exact typed value through normalization.
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

inline bool typed(const Value& value, Type type) {
    switch (type) {
        case Type::string: return std::holds_alternative<std::string>(value.storage());
        case Type::integer: return std::holds_alternative<Value::Integer>(value.storage());
        case Type::boolean: return std::holds_alternative<bool>(value.storage());
        case Type::array: return std::holds_alternative<Value::Array>(value.storage());
        case Type::object: return std::holds_alternative<Object>(value.storage());
    }
    return false;
}

inline bool valid(const Object& object, Schema schema, bool intent,
        std::span<const std::string_view> deferred_types = {}) {
    if (schema.name.empty()) return false;
    const auto found_action = object.find("action");
    if (found_action == object.end() ||
        !std::holds_alternative<std::string>(found_action->second.storage()) ||
        std::get<std::string>(found_action->second.storage()) != schema.name) return false;
    const auto base = intent ?
        std::array<std::string_view, 5>{"context", "client", "request", "actor", "action"} :
        std::array<std::string_view, 5>{"context", "client", "request", "action", ""};
    std::size_t count = intent ? 5 : 4;
    for (const auto name : base) if (!name.empty() && !object.contains(std::string(name))) return false;
    if (intent && object.contains("wire")) {
        if (!std::holds_alternative<Object>(object.at("wire").storage())) return false;
        ++count;
    }
    for (const auto& field : schema.fields) {
        const auto name = intent ? field.intent : field.wire;
        if (name.empty()) continue;
        const auto found = object.find(std::string(name));
        if (found == object.end()) {
            if (!field.optional) return false;
            continue;
        }
        bool deferred = false;
        for (const auto deferred_name : deferred_types)
            if (deferred_name == name) deferred = true;
        if (!deferred && !typed(found->second, field.type)) return false;
        ++count;
    }
    return object.size() == count;
}

inline bool valid_wire(const Object& wire, Schema schema) { return valid(wire, schema, false); }
inline bool valid_intent(const Object& intent, Schema schema) { return valid(intent, schema, true); }

inline bool historical_wire(const Object& wire, const Object& intent, Schema schema) {
    if (!valid_wire(wire, schema) || !valid_intent(intent, schema)) return false;
    for (const auto& field : schema.fields) {
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

} // namespace factory::command_contract
