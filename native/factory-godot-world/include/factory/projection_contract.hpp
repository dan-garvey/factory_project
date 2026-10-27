#pragma once

#include "factory/value.hpp"

#include <array>
#include <string>
#include <string_view>
#include <utility>
#include <variant>

namespace factory::godot_world::projection_contract {

using Value = values::Value;
using Object = Value::Object;

enum class Type { string, integer, boolean, array, object };

struct Field {
    std::string_view name;
    Type type;
};

// Every Host projection has these fields in both ordinary and arrival worlds.
// Profile-specific additions remain optional. The extension adds the one
// derived engineering view without changing World state.
inline constexpr std::array host_fields{
    Field{"context", Type::string},
    Field{"revision", Type::integer},
    Field{"order", Type::integer},
    Field{"initial_feed", Type::integer},
    Field{"recipe_input", Type::integer},
    Field{"entities", Type::object},
    Field{"transmission_parts", Type::object},
    Field{"links", Type::array},
    Field{"drive_links", Type::array},
    Field{"engagements", Type::array},
    Field{"motion", Type::object},
    Field{"inventories", Type::object},
    Field{"cargo", Type::object},
    Field{"part_kits", Type::object},
    Field{"part_specifications", Type::object},
    Field{"parts", Type::object},
    Field{"actors", Type::object},
    Field{"manual_cuts", Type::object},
    Field{"foundations", Type::object},
    Field{"source_deposit", Type::object},
    Field{"powered", Type::boolean},
    Field{"power_enabled", Type::boolean},
    Field{"options", Type::object},
    Field{"adapter_profile", Type::object},
    Field{"belt_spans", Type::object},
    Field{"line_belt_raw", Type::integer},
    Field{"dropped_material", Type::array},
    Field{"stock", Type::object},
    Field{"remaining", Type::integer},
};

inline constexpr Field engineering_field{"opening_engineering", Type::object};

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

inline bool complete(const Value& value, bool engine_view = false) {
    const auto* object = std::get_if<Object>(&value.storage());
    if (!object) return false;
    for (const auto& field : host_fields) {
        const auto found = object->find(std::string(field.name));
        if (found == object->end() || !typed(found->second, field.type)) return false;
    }
    if (engine_view) {
        const auto found = object->find(std::string(engineering_field.name));
        if (found == object->end() || !typed(found->second, engineering_field.type)) return false;
    }
    return true;
}

inline const char* type_name(Type type) {
    switch (type) {
        case Type::string: return "string";
        case Type::integer: return "integer";
        case Type::boolean: return "boolean";
        case Type::array: return "array";
        case Type::object: return "object";
    }
    return "";
}

inline Value fields(bool engine_view = false) {
    Object result;
    for (const auto& field : host_fields)
        result.emplace(std::string(field.name), Value(type_name(field.type)));
    if (engine_view)
        result.emplace(std::string(engineering_field.name),
            Value(type_name(engineering_field.type)));
    return Value(std::move(result));
}

} // namespace factory::godot_world::projection_contract
