#pragma once

#include "factory/value.hpp"

#include <array>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <variant>

namespace factory::godot_world::projection_contract {

using Value = values::Value;
using Object = Value::Object;

enum class Type { string, integer, floating, boolean, array, object, integer2, integer3, floating3 };

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

// These records have the same required shape in ordinary and arrival worlds.
// Counts and profile-specific additions may differ without changing the wire.
enum class Container { object, object_values, array_elements };

struct Record {
    std::string_view name;
    Container container;
    std::span<const Field> fields;
};

inline constexpr std::array stock_fields{
    Field{"source", Type::integer}, Field{"collector", Type::integer},
    Field{"belt", Type::integer}, Field{"input", Type::integer},
    Field{"held", Type::integer}, Field{"output", Type::integer},
    Field{"player", Type::integer},
};
inline constexpr std::array cargo_fields{
    Field{"raw", Type::integer}, Field{"products", Type::integer},
    Field{"work_lots", Type::array},
};
inline constexpr std::array dropped_fields{
    Field{"center", Type::integer3}, Field{"raw", Type::integer},
    Field{"products", Type::integer}, Field{"work_lots", Type::array},
};
inline constexpr std::array actor_fields{
    Field{"position", Type::floating3}, Field{"capabilities", Type::object},
    Field{"ready", Type::boolean}, Field{"native_epoch", Type::integer},
    Field{"harvest_clear", Type::object},
};
inline constexpr std::array cut_fields{
    Field{"target", Type::string}, Field{"remaining_ticks", Type::integer},
    Field{"duration_ticks", Type::integer}, Field{"interrupted", Type::boolean},
};
inline constexpr std::array deposit_fields{
    Field{"id", Type::string}, Field{"cells", Type::array},
    Field{"initial_units", Type::integer}, Field{"collector_capacity", Type::integer},
    Field{"maximum_depth", Type::floating},
};
inline constexpr std::array entity_fields{
    Field{"kind", Type::string}, Field{"generation", Type::integer},
    Field{"center", Type::integer3}, Field{"axis", Type::integer},
    Field{"relay_axis", Type::integer}, Field{"teeth", Type::integer},
    Field{"half_span", Type::integer}, Field{"rotation", Type::integer},
    Field{"cell", Type::integer2},
};
inline constexpr std::array transmission_fields{
    Field{"kind", Type::string}, Field{"generation", Type::integer},
    Field{"center", Type::integer3}, Field{"axis", Type::integer},
    Field{"relay_axis", Type::integer}, Field{"teeth", Type::integer},
    Field{"half_span", Type::integer}, Field{"rotation", Type::integer},
};
inline constexpr std::array span_fields{
    Field{"generation", Type::integer}, Field{"order", Type::integer},
    Field{"from", Type::string}, Field{"to", Type::string},
    Field{"phase", Type::integer}, Field{"slots", Type::array},
};
inline constexpr std::array motion_fields{
    Field{"state", Type::string}, Field{"numerator", Type::integer},
    Field{"denominator", Type::integer},
};
inline constexpr std::array foundation_fields{
    Field{"cell", Type::integer2}, Field{"level", Type::integer},
    Field{"generation", Type::integer},
};
inline constexpr std::array engagement_fields{
    Field{"a", Type::string}, Field{"b", Type::string},
    Field{"kind", Type::integer},
};
inline constexpr std::array records{
    Record{"stock", Container::object, stock_fields},
    Record{"cargo", Container::object_values, cargo_fields},
    Record{"dropped_material", Container::array_elements, dropped_fields},
    Record{"actors", Container::object_values, actor_fields},
    Record{"manual_cuts", Container::object_values, cut_fields},
    Record{"source_deposit", Container::object, deposit_fields},
    Record{"entities", Container::object_values, entity_fields},
    Record{"transmission_parts", Container::object_values, transmission_fields},
    Record{"belt_spans", Container::object_values, span_fields},
    Record{"motion", Container::object_values, motion_fields},
    Record{"foundations", Container::object_values, foundation_fields},
    Record{"engagements", Container::array_elements, engagement_fields},
};

inline bool typed(const Value& value, Type type) {
    switch (type) {
        case Type::string: return std::holds_alternative<std::string>(value.storage());
        case Type::integer: return std::holds_alternative<Value::Integer>(value.storage());
        case Type::floating: return std::holds_alternative<double>(value.storage());
        case Type::boolean: return std::holds_alternative<bool>(value.storage());
        case Type::array: return std::holds_alternative<Value::Array>(value.storage());
        case Type::object: return std::holds_alternative<Object>(value.storage());
        case Type::integer2:
        case Type::integer3:
        case Type::floating3: {
            const auto* entries = std::get_if<Value::Array>(&value.storage());
            if (!entries || entries->size() != (type == Type::integer2 ? 2 : 3)) return false;
            for (const auto& entry : *entries)
                if (!typed(entry, type == Type::floating3 ? Type::floating : Type::integer))
                    return false;
            return true;
        }
    }
    return false;
}

inline bool required_fields(const Object& object, std::span<const Field> fields) {
    for (const auto& field : fields) {
        const auto found = object.find(std::string(field.name));
        if (found == object.end() || !typed(found->second, field.type)) return false;
    }
    return true;
}

inline bool complete_record(const Value& value, const Record& record) {
    if (record.container == Container::array_elements) {
        const auto* entries = std::get_if<Value::Array>(&value.storage());
        if (!entries) return false;
        for (const auto& entry : *entries) {
            const auto* object = std::get_if<Object>(&entry.storage());
            if (!object || !required_fields(*object, record.fields)) return false;
        }
        return true;
    }
    const auto* object = std::get_if<Object>(&value.storage());
    if (!object) return false;
    if (record.container == Container::object) return required_fields(*object, record.fields);
    for (const auto& [key, entry] : *object) {
        (void)key;
        const auto* fields = std::get_if<Object>(&entry.storage());
        if (!fields || !required_fields(*fields, record.fields)) return false;
    }
    return true;
}

inline bool complete(const Value& value, bool engine_view = false) {
    const auto* object = std::get_if<Object>(&value.storage());
    if (!object) return false;
    if (!required_fields(*object, host_fields)) return false;
    for (const auto& record : records) {
        const auto found = object->find(std::string(record.name));
        if (found == object->end() || !complete_record(found->second, record)) return false;
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
        case Type::floating: return "floating";
        case Type::boolean: return "boolean";
        case Type::array: return "array";
        case Type::object: return "object";
        case Type::integer2: return "integer2";
        case Type::integer3: return "integer3";
        case Type::floating3: return "floating3";
    }
    return "";
}

inline const char* container_name(Container container) {
    switch (container) {
        case Container::object: return "object";
        case Container::object_values: return "object_values";
        case Container::array_elements: return "array_elements";
    }
    return "";
}

inline Value record_fields() {
    Object output;
    for (const auto& record : records) {
        Object fields;
        for (const auto& field : record.fields)
            fields.emplace(std::string(field.name), Value(type_name(field.type)));
        output.emplace(std::string(record.name), Value(Object{
            {"container", Value(container_name(record.container))},
            {"fields", Value(std::move(fields))}}));
    }
    return Value(std::move(output));
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
