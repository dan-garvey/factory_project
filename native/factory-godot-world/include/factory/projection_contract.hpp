#pragma once

#include "factory/value.hpp"

#include <array>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <variant>

namespace factory::godot_world::projection_contract {

using Value = values::Value;
using Object = Value::Object;

enum class Type { string, integer, floating, boolean, array, object, integer2, integer3,
                  floating2, floating3, string_pairs, integer_pairs, integer_values,
                  boolean_values,
                  string_array, nullable_string, integer3_or_empty, integer3_array,
                  floating3_pair };

struct Field {
    std::string_view name;
    Type type;
    bool optional{};
    std::string_view exact_text{};
    std::optional<Value::Integer> exact_integer{};
    std::span<const std::string_view> allowed_text{};
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
    Field{"links", Type::string_pairs},
    Field{"drive_links", Type::string_pairs},
    Field{"engagements", Type::array},
    Field{"motion", Type::object},
    Field{"inventories", Type::integer_values},
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

struct ConditionalField {
    std::string_view name;
    Type type;
    std::string_view required_with;
};

inline constexpr std::array conditional_fields{
    ConditionalField{"component_capacity", Type::integer, "options.arrival"},
    ConditionalField{"workshop_completed_actors", Type::string_array, "options.arrival"},
    ConditionalField{"first_plate_unlock", Type::boolean, "options.arrival"},
    ConditionalField{"material_mass", Type::object, "options.copper_material"},
    ConditionalField{"hand_sources", Type::object, "options.manual_sources"},
};

// These records describe native worksite views and the extension's derived view.
// Counts and profile-specific additions may differ without changing the wire.
enum class Container { object, object_values, array_elements, object_array_elements };

struct Record {
    std::string_view name;
    Container container;
    std::span<const Field> fields;
    // A dotted native projection fact decides profile-specific presence.
    std::string_view required_with{};
    bool engine_view_only{};
    std::string_view keys_with{};
    std::string_view identity_field{};
};

inline constexpr std::array stock_fields{
    Field{"source", Type::integer}, Field{"collector", Type::integer},
    Field{"belt", Type::integer}, Field{"input", Type::integer},
    Field{"held", Type::integer}, Field{"output", Type::integer},
    Field{"player", Type::integer},
};
inline constexpr std::array mass_fields{
    Field{"stock_chunks", Type::integer}, Field{"work_chunks", Type::integer},
    Field{"plates", Type::integer}, Field{"offcut_units", Type::integer},
    Field{"sheets", Type::integer}, Field{"embodied_chunks", Type::integer},
    Field{"accounted_mass", Type::integer}, Field{"initial_mass", Type::integer},
};
inline constexpr std::array<std::string_view, 2> hand_source_kinds{
    "tree", "ore_deposit"};
inline constexpr std::array hand_source_fields{
    Field{"kind", Type::string, false, {}, {}, hand_source_kinds},
    Field{"position", Type::floating3}, Field{"initial", Type::integer},
    Field{"remaining", Type::integer},
    Field{"contact_bounds", Type::floating3_pair, true},
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
    Field{"capabilities.build_reach", Type::floating},
    Field{"capabilities.harvest_reach", Type::floating},
    Field{"ready", Type::boolean}, Field{"native_epoch", Type::integer},
    Field{"harvest_clear", Type::boolean_values},
};
inline constexpr std::array cut_fields{
    Field{"target", Type::string}, Field{"remaining_ticks", Type::integer},
    Field{"duration_ticks", Type::integer}, Field{"interrupted", Type::boolean},
};
inline constexpr std::array deposit_fields{
    Field{"id", Type::string}, Field{"cells", Type::integer_pairs},
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
inline constexpr std::array adapter_profile_fields{
    Field{"pitch", Type::floating}, Field{"anchor_height", Type::floating},
    Field{"height_denominator", Type::integer}, Field{"height_step", Type::floating},
    Field{"foundation_depth", Type::floating}, Field{"wheel_radius", Type::integer},
    Field{"wheel_axle_offset", Type::integer}, Field{"capsule_radius", Type::floating},
    Field{"capsule_height", Type::floating},
    Field{"collector_intake_size", Type::floating3},
    Field{"collector_intake_x", Type::floating},
    Field{"collector_intake_y", Type::floating},
    Field{"collector_second_cell_z", Type::floating},
    Field{"collector_lift", Type::object},
};
inline constexpr std::array option_fields{
    Field{"opening", Type::boolean}, Field{"physical", Type::boolean},
    Field{"native", Type::boolean}, Field{"arrival", Type::boolean},
    Field{"copper_material", Type::boolean}, Field{"manual_sources", Type::boolean},
    Field{"foundations", Type::boolean},
    Field{"developer_conveniences", Type::boolean},
};
inline constexpr std::array collector_lift_fields{
    Field{"pickup_x", Type::floating}, Field{"pickup_y", Type::floating},
    Field{"pickup_size", Type::floating3}, Field{"carrier_x", Type::floating},
    Field{"carrier_bottom", Type::floating}, Field{"carrier_top_offset", Type::floating},
    Field{"carrier_size_xz", Type::floating2}, Field{"guide_offset", Type::floating2},
    Field{"guide_size", Type::floating2}, Field{"flight_offset_x", Type::floating},
    Field{"flight_raise_y", Type::floating}, Field{"flight_size", Type::floating3},
    Field{"flight_count", Type::integer}, Field{"flight_span", Type::floating},
    Field{"head_x", Type::floating}, Field{"head_y_offset", Type::floating},
    Field{"head_size_xy", Type::floating2}, Field{"head_z_size", Type::floating2},
};
inline constexpr std::array collector_assembly_fields{
    Field{"center", Type::integer3}, Field{"toward_ore", Type::integer3},
    Field{"status", Type::string},
};
inline constexpr std::array press_assembly_fields{
    Field{"frame", Type::string}, Field{"center", Type::integer3},
    Field{"status", Type::string},
};
inline constexpr std::array guided_press_assembly_fields{
    Field{"anvil", Type::string}, Field{"center", Type::integer3},
    Field{"status", Type::string},
};
inline constexpr std::array broad_assembly_fields{
    Field{"origin", Type::integer3}, Field{"geometry_status", Type::string},
    Field{"status", Type::string},
};
inline constexpr std::array kit_fields{
    Field{"collector", Type::integer}, Field{"belt", Type::integer},
    Field{"processor", Type::integer}, Field{"wheel", Type::integer},
    Field{"shaft", Type::integer}, Field{"gear", Type::integer},
    Field{"gearbox", Type::integer}, Field{"vertical_gearbox", Type::integer},
    Field{"chain_drive", Type::integer}, Field{"foundation", Type::integer},
};
inline constexpr std::array part_specification_fields{
    Field{"kind", Type::string}, Field{"teeth", Type::integer},
    Field{"half_span", Type::integer}, Field{"count", Type::integer},
};
inline constexpr std::array recipe_fields{
    Field{"timber", Type::integer}, Field{"copper", Type::integer},
};
inline constexpr std::array part_recipe_fields{
    Field{"kind", Type::string}, Field{"teeth", Type::integer},
    Field{"half_span", Type::integer}, Field{"timber", Type::integer},
    Field{"copper", Type::integer},
};
inline constexpr std::array supplied_hardware_fields{
    Field{"entity", Type::string}, Field{"generation", Type::integer},
    Field{"center", Type::floating3}, Field{"half", Type::floating3},
};
inline constexpr std::array landing_pod_fields{
    Field{"id", Type::string}, Field{"generation", Type::integer},
    Field{"center", Type::integer3}, Field{"deployed", Type::boolean},
    Field{"hub_ready", Type::boolean},
};
inline constexpr std::array fabrication_hub_fields{
    Field{"id", Type::string}, Field{"generation", Type::integer},
    Field{"installed", Type::boolean}, Field{"holder", Type::nullable_string},
    Field{"center", Type::integer3}, Field{"position", Type::floating3},
};
inline constexpr std::array fabrication_bench_fields{
    Field{"id", Type::string}, Field{"generation", Type::integer},
    Field{"center", Type::integer3}, Field{"position", Type::floating3},
};
inline constexpr std::array crank_item_fields{
    Field{"id", Type::string}, Field{"generation", Type::integer},
    Field{"holder", Type::string}, Field{"attached_to", Type::string},
    Field{"port", Type::integer3_or_empty}, Field{"face", Type::integer3_or_empty},
};
inline constexpr std::array placed_component_fields{
    Field{"component", Type::string}, Field{"generation", Type::integer},
    Field{"center", Type::integer3}, Field{"occupied", Type::object},
    Field{"occupied.center", Type::floating3},
    Field{"occupied.half", Type::floating3},
    Field{"position", Type::floating3},
    Field{"input_ports", Type::integer3_array, true},
    Field{"crank_axis", Type::integer, true},
};
inline constexpr std::array slide_phase_fields{
    Field{"subticks", Type::integer}, Field{"remainder", Type::integer},
    Field{"denominator", Type::integer}, Field{"cycle_subticks", Type::integer},
};
inline constexpr std::array<std::string_view, 6> engineering_phase_names{
    "unavailable", "first_shift", "move_source", "restore_drive", "deliver_more", "ready"};
inline constexpr std::array engineering_fields{
    Field{"schema", Type::integer, false, {}, Value::Integer{1}},
    Field{"format", Type::string, false, "factory-opening-engineering"},
    Field{"actor", Type::string},
    Field{"phase", Type::string, false, {}, {}, engineering_phase_names},
    Field{"known_actor", Type::boolean}, Field{"products", Type::integer},
    Field{"first_target", Type::integer}, Field{"target", Type::integer},
    Field{"wheel_cell", Type::integer2},
    Field{"source_at_target", Type::boolean},
    Field{"machines_running", Type::boolean},
    Field{"belt_forward", Type::boolean},
    Field{"placed_gears", Type::integer}, Field{"placed_shafts", Type::integer},
    Field{"ready", Type::boolean}, Field{"title", Type::string},
    Field{"brief", Type::string}, Field{"relocate_hint", Type::string},
    Field{"gear_hint", Type::string},
};
inline constexpr std::array records{
    Record{"stock", Container::object, stock_fields},
    Record{"material_mass", Container::object, mass_fields, "options.copper_material"},
    Record{"hand_sources", Container::object_values, hand_source_fields,
        "options.manual_sources"},
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
    Record{"adapter_profile", Container::object, adapter_profile_fields},
    Record{"adapter_profile.collector_lift", Container::object, collector_lift_fields},
    Record{"options", Container::object, option_fields},
    Record{"part_kits", Container::object_values, kit_fields},
    Record{"parts", Container::object, kit_fields},
    Record{"part_specifications", Container::object_array_elements,
        part_specification_fields},
    Record{"supplied_hardware_boxes", Container::object_values,
        supplied_hardware_fields, "options.arrival"},
    Record{"landing_pod", Container::object, landing_pod_fields, "options.arrival"},
    Record{"fabrication_hub", Container::object, fabrication_hub_fields, "options.arrival"},
    Record{"fabrication_benches", Container::array_elements,
        fabrication_bench_fields, "options.arrival"},
    Record{"crank_items", Container::object_values, crank_item_fields,
        "options.arrival"},
    Record{"placed_components", Container::object_values,
        placed_component_fields, "options.arrival"},
    Record{"slide_phases", Container::object_values, slide_phase_fields,
        "options.arrival"},
    Record{"component_recipes", Container::object_values, recipe_fields,
        "options.arrival"},
    Record{"part_recipes", Container::array_elements, part_recipe_fields,
        "options.arrival"},
    Record{"foundation_recipe", Container::object, recipe_fields,
        "options.arrival"},
    Record{"collector_assemblies", Container::array_elements, collector_assembly_fields,
        "options.arrival"},
    Record{"press_assemblies", Container::array_elements, press_assembly_fields,
        "options.arrival"},
    Record{"guided_press_assemblies", Container::array_elements,
        guided_press_assembly_fields, "options.arrival"},
    Record{"sliding_press_assemblies", Container::array_elements,
        guided_press_assembly_fields, "options.arrival"},
    Record{"broad_press_assemblies", Container::array_elements, broad_assembly_fields,
        "options.arrival"},
    Record{"broad_shear_assemblies", Container::array_elements, broad_assembly_fields,
        "options.arrival"},
    Record{"opening_engineering", Container::object_values, engineering_fields,
        {}, true, "inventories", "actor"},
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
        case Type::floating2:
        case Type::floating3: {
            const auto* entries = std::get_if<Value::Array>(&value.storage());
            if (!entries || entries->size() !=
                    (type == Type::integer2 || type == Type::floating2 ? 2 : 3)) return false;
            for (const auto& entry : *entries)
                if (!typed(entry, type == Type::floating2 || type == Type::floating3 ?
                        Type::floating : Type::integer))
                    return false;
            return true;
        }
        case Type::string_pairs:
        case Type::integer_pairs: {
            const auto* entries = std::get_if<Value::Array>(&value.storage());
            if (!entries) return false;
            for (const auto& entry : *entries) {
                const auto* pair = std::get_if<Value::Array>(&entry.storage());
                if (!pair || pair->size() != 2) return false;
                for (const auto& member : *pair)
                    if (!typed(member, type == Type::string_pairs ? Type::string : Type::integer))
                        return false;
            }
            return true;
        }
        case Type::integer_values: {
            const auto* entries = std::get_if<Object>(&value.storage());
            if (!entries) return false;
            for (const auto& [key, entry] : *entries) {
                (void)key;
                if (!typed(entry, Type::integer)) return false;
            }
            return true;
        }
        case Type::boolean_values: {
            const auto* entries = std::get_if<Object>(&value.storage());
            if (!entries) return false;
            for (const auto& [key, entry] : *entries) {
                (void)key;
                if (!typed(entry, Type::boolean)) return false;
            }
            return true;
        }
        case Type::string_array: {
            const auto* entries = std::get_if<Value::Array>(&value.storage());
            if (!entries) return false;
            for (const auto& entry : *entries)
                if (!typed(entry, Type::string)) return false;
            return true;
        }
        case Type::nullable_string:
            return std::holds_alternative<std::nullptr_t>(value.storage()) ||
                typed(value, Type::string);
        case Type::integer3_or_empty: {
            const auto* entries = std::get_if<Value::Array>(&value.storage());
            return entries && (entries->empty() || typed(value, Type::integer3));
        }
        case Type::integer3_array: {
            const auto* entries = std::get_if<Value::Array>(&value.storage());
            if (!entries) return false;
            for (const auto& entry : *entries)
                if (!typed(entry, Type::integer3)) return false;
            return true;
        }
        case Type::floating3_pair: {
            const auto* entries = std::get_if<Value::Array>(&value.storage());
            return entries && entries->size() == 2 &&
                typed((*entries)[0], Type::floating3) &&
                typed((*entries)[1], Type::floating3);
        }
    }
    return false;
}

inline const Value* record_at(const Object& projection, std::string_view path);

inline bool required_fields(const Object& object, std::span<const Field> fields) {
    for (const auto& field : fields) {
        const auto* found = record_at(object, field.name);
        if (!found) {
            if (field.optional) continue;
            return false;
        }
        if (!typed(*found, field.type)) return false;
        if (!field.exact_text.empty() &&
            std::get<std::string>(found->storage()) != field.exact_text) return false;
        if (field.exact_integer &&
            std::get<Value::Integer>(found->storage()) != *field.exact_integer) return false;
        if (!field.allowed_text.empty()) {
            const auto& name = std::get<std::string>(found->storage());
            bool allowed = false;
            for (const auto candidate : field.allowed_text)
                allowed |= name == candidate;
            if (!allowed) return false;
        }
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
        if (record.container == Container::object_array_elements) {
            const auto* entries = std::get_if<Value::Array>(&entry.storage());
            if (!entries) return false;
            for (const auto& item : *entries) {
                const auto* fields = std::get_if<Object>(&item.storage());
                if (!fields || !required_fields(*fields, record.fields)) return false;
            }
            continue;
        }
        const auto* fields = std::get_if<Object>(&entry.storage());
        if (!fields || !required_fields(*fields, record.fields)) return false;
        if (!record.identity_field.empty()) {
            const auto* identity = record_at(*fields, record.identity_field);
            const auto* name = identity ? std::get_if<std::string>(&identity->storage()) : nullptr;
            if (!name || *name != key) return false;
        }
    }
    return true;
}

inline const Value* record_at(const Object& projection, std::string_view path) {
    const Object* object = &projection;
    for (;;) {
        const auto separator = path.find('.');
        const auto found = object->find(std::string(path.substr(0, separator)));
        if (found == object->end()) return nullptr;
        if (separator == std::string_view::npos) return &found->second;
        object = std::get_if<Object>(&found->second.storage());
        if (!object) return nullptr;
        path.remove_prefix(separator + 1);
    }
}

inline bool required_with(const Object& projection, std::string_view path) {
    const auto* marker = record_at(projection, path);
    const auto* enabled = marker ? std::get_if<bool>(&marker->storage()) : nullptr;
    return enabled && *enabled;
}

inline bool complete(const Value& value, bool engine_view = false) {
    const auto* object = std::get_if<Object>(&value.storage());
    if (!object) return false;
    if (!required_fields(*object, host_fields)) return false;
    for (const auto& field : conditional_fields) {
        const auto found = object->find(std::string(field.name));
        if (found == object->end()) {
            if (!required_with(*object, field.required_with)) continue;
            return false;
        }
        if (!typed(found->second, field.type)) return false;
    }
    for (const auto& record : records) {
        if (record.engine_view_only && !engine_view) continue;
        const auto* found = record_at(*object, record.name);
        if (!found) {
            if (!record.required_with.empty() &&
                !required_with(*object, record.required_with)) continue;
            return false;
        }
        if (!complete_record(*found, record)) return false;
        if (!record.keys_with.empty()) {
            const auto* source = record_at(*object, record.keys_with);
            const auto* expected = source ? std::get_if<Object>(&source->storage()) : nullptr;
            const auto* actual = std::get_if<Object>(&found->storage());
            if (!expected || !actual || expected->size() != actual->size()) return false;
            for (const auto& [key, entry] : *expected) {
                (void)entry;
                if (!actual->contains(key)) return false;
            }
        }
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
        case Type::floating2: return "floating2";
        case Type::floating3: return "floating3";
        case Type::string_pairs: return "string_pairs";
        case Type::integer_pairs: return "integer_pairs";
        case Type::integer_values: return "integer_values";
        case Type::boolean_values: return "boolean_values";
        case Type::string_array: return "string_array";
        case Type::nullable_string: return "nullable_string";
        case Type::integer3_or_empty: return "integer3_or_empty";
        case Type::integer3_array: return "integer3_array";
        case Type::floating3_pair: return "floating3_pair";
    }
    return "";
}

inline const char* container_name(Container container) {
    switch (container) {
        case Container::object: return "object";
        case Container::object_values: return "object_values";
        case Container::array_elements: return "array_elements";
        case Container::object_array_elements: return "object_array_elements";
    }
    return "";
}

inline Value record_fields() {
    Object output;
    for (const auto& record : records) {
        Object fields;
        for (const auto& field : record.fields) {
            if (field.optional || !field.exact_text.empty() || field.exact_integer ||
                !field.allowed_text.empty()) {
                Object descriptor{{"type", Value(type_name(field.type))}};
                if (field.optional) descriptor.emplace("optional", Value(true));
                if (!field.exact_text.empty())
                    descriptor.emplace("equals", Value(std::string(field.exact_text)));
                if (field.exact_integer)
                    descriptor.emplace("equals", Value(*field.exact_integer));
                if (!field.allowed_text.empty()) {
                    Value::Array allowed;
                    for (const auto item : field.allowed_text)
                        allowed.emplace_back(std::string(item));
                    descriptor.emplace("allowed", Value(std::move(allowed)));
                }
                fields.emplace(std::string(field.name), Value(std::move(descriptor)));
            } else {
                fields.emplace(std::string(field.name), Value(type_name(field.type)));
            }
        }
        Object definition{{"container", Value(container_name(record.container))},
            {"fields", Value(std::move(fields))}};
        if (!record.required_with.empty())
            definition.emplace("required_with", Value(std::string(record.required_with)));
        if (record.engine_view_only)
            definition.emplace("engine_view_only", Value(true));
        if (!record.keys_with.empty())
            definition.emplace("keys_with", Value(std::string(record.keys_with)));
        if (!record.identity_field.empty())
            definition.emplace("identity_field", Value(std::string(record.identity_field)));
        output.emplace(std::string(record.name), Value(std::move(definition)));
    }
    return Value(std::move(output));
}

inline Value fields(bool engine_view = false) {
    Object result;
    for (const auto& field : host_fields)
        result.emplace(std::string(field.name), Value(type_name(field.type)));
    for (const auto& field : conditional_fields)
        result.emplace(std::string(field.name), Value(Object{
            {"type", Value(type_name(field.type))},
            {"required_with", Value(std::string(field.required_with))}}));
    if (engine_view)
        result.emplace(std::string(engineering_field.name),
            Value(type_name(engineering_field.type)));
    return Value(std::move(result));
}

} // namespace factory::godot_world::projection_contract
