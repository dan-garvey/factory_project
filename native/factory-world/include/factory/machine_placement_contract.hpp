#pragma once

#include "factory/command_contract.hpp"
#include "factory/mechanics.hpp"

#include <array>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

namespace factory::machine_placement {

using command_contract::Field;
using command_contract::Object;
using command_contract::Schema;
using command_contract::Type;
using Integer = values::Value::Integer;
using Array = values::Value::Array;
using Value = values::Value;

inline Schema wire_schema() {
    static constexpr std::array fields{
        Field{"kind", "role", Type::string}, Field{"cell", "center", Type::array},
        Field{"axis", "axis", Type::string, true},
        Field{"level", "", Type::integer, true},
        Field{"rotation", "rotation", Type::integer, true},
        Field{"tiles", "wheel_tiles", Type::integer, true},
    };
    return {"place", fields};
}

inline Schema intent_schema(std::string_view action) {
    static constexpr std::array fields{
        Field{"", "role", Type::string}, Field{"", "center", Type::array},
        Field{"", "axis", Type::string}, Field{"", "teeth", Type::integer},
        Field{"", "half_span", Type::integer},
        Field{"", "rotation", Type::integer, true},
        Field{"", "wheel_tiles", Type::integer, true},
    };
    return {action == "place" || action == "place_connected" ? action : std::string_view{}, fields};
}

inline const std::string* kind(const Object& wire) {
    const auto found = wire.find("kind");
    return found == wire.end() ? nullptr : std::get_if<std::string>(&found->second.storage());
}

inline bool valid_kind(std::string_view name) {
    return name == "collector" || name == "processor" || name == "wheel" || name == "gear";
}

// Keep malformed field values available to Host's specific refusal paths.
// Conditional optional fields are a wire-shape error before value decoding.
inline bool admission_shape(const Object& wire) {
    static constexpr std::array deferred{
        std::string_view{"kind"}, std::string_view{"cell"},
        std::string_view{"axis"}, std::string_view{"level"},
        std::string_view{"rotation"}, std::string_view{"tiles"},
    };
    if (!command_contract::valid(wire, wire_schema(), false, deferred)) return false;
    const auto* selected = kind(wire);
    return (!wire.contains("rotation") ||
            (selected && (*selected == "collector" || *selected == "processor"))) &&
        (!wire.contains("tiles") || (selected && *selected == "wheel"));
}

inline bool valid_wire(const Object& wire) {
    return admission_shape(wire) && command_contract::valid_wire(wire, wire_schema());
}

inline bool valid_intent(const Object& intent, std::string_view action) {
    return command_contract::valid_intent(intent, intent_schema(action)) &&
        !(intent.contains("rotation") && intent.contains("wheel_tiles"));
}

inline bool valid_axis(std::string_view axis) {
    return axis == "x" || axis == "y" || axis == "z";
}

inline bool valid_rotation(const Object& wire) {
    if (!wire.contains("rotation")) return true;
    const auto* value = std::get_if<Integer>(&wire.at("rotation").storage());
    return value && *value >= 0 && *value <= 3;
}

inline bool valid_tiles(const Object& wire) {
    if (!wire.contains("tiles")) return true;
    const auto* value = std::get_if<Integer>(&wire.at("tiles").storage());
    return value && *value >= 3 && *value <= mechanics::maximum_dimension;
}

inline std::optional<mechanics::Point> center(const Object& wire) {
    const auto found = wire.find("cell");
    const auto* cell = found == wire.end() ? nullptr : std::get_if<Array>(&found->second.storage());
    if (!cell || cell->size() != 2) return std::nullopt;
    const auto* x = std::get_if<Integer>(&cell->at(0).storage());
    const auto* z = std::get_if<Integer>(&cell->at(1).storage());
    const auto level_field = wire.find("level");
    const auto* level = level_field == wire.end() ? nullptr :
        std::get_if<Integer>(&level_field->second.storage());
    if (!x || !z || *x < -250000 || *x > 250000 || *z < -250000 || *z > 250000 ||
        (level_field != wire.end() && (!level || *level < -1000000 || *level > 1000000)))
        return std::nullopt;
    return mechanics::Point{4 * *x, level ? *level : Integer{0}, 4 * *z};
}

inline bool aligned(const mechanics::Point& center) { return center[1] % 4 == 0; }

inline std::string role(std::string_view kind) {
    return kind == "wheel" ? "waterwheel" : std::string(kind);
}

inline std::string_view action(std::string_view kind) {
    return kind == "collector" || kind == "processor" ? "place_connected" : "place";
}

inline Integer teeth(std::string_view kind) { return kind == "gear" ? Integer{2} : Integer{0}; }

inline bool normalize(Object& intent, const Object& wire) {
    const auto* selected = kind(wire);
    const auto position = center(wire);
    if (!selected || !valid_kind(*selected) || !position) return false;
    intent.at("action") = Value(std::string(action(*selected)));
    intent.emplace("role", Value(role(*selected)));
    intent.emplace("center", Value(Array{Value((*position)[0]), Value((*position)[1]), Value((*position)[2])}));
    const auto axis = wire.find("axis");
    intent.emplace("axis", axis == wire.end() ? Value("x") : axis->second);
    intent.emplace("teeth", Value(teeth(*selected)));
    intent.emplace("half_span", Value(Integer{0}));
    if (wire.contains("rotation")) intent.emplace("rotation", wire.at("rotation"));
    if (wire.contains("tiles")) intent.emplace("wheel_tiles", wire.at("tiles"));
    return true;
}

inline bool historical_wire(const Object& wire, const Object& intent,
        std::string_view normalized_action) {
    if (!valid_wire(wire) || !valid_intent(intent, normalized_action) ||
        !valid_rotation(wire) || !valid_tiles(wire)) return false;
    const auto* selected = kind(wire);
    const auto position = center(wire);
    if (!selected || !valid_kind(*selected) || !position ||
        action(*selected) != normalized_action)
        return false;
    const auto axis = wire.find("axis");
    const auto* axis_name = axis == wire.end() ? nullptr :
        std::get_if<std::string>(&axis->second.storage());
    if (axis_name && !valid_axis(*axis_name)) return false;
    const Object expected{{"role", Value(role(*selected))},
        {"center", Value(Array{Value((*position)[0]), Value((*position)[1]), Value((*position)[2])})},
        {"axis", axis == wire.end() ? Value("x") : axis->second},
        {"teeth", Value(teeth(*selected))}, {"half_span", Value(Integer{0})}};
    for (const auto& [name, value] : expected) {
        const auto found = intent.find(name);
        if (found == intent.end() || values::typed_difference(value, found->second)) return false;
    }
    for (const auto& [wire_name, intent_name] :
            {std::pair{"rotation", "rotation"}, std::pair{"tiles", "wheel_tiles"}}) {
        const auto original = wire.find(wire_name);
        const auto translated = intent.find(intent_name);
        if ((original == wire.end()) != (translated == intent.end()) ||
            (original != wire.end() && values::typed_difference(original->second, translated->second)))
            return false;
    }
    return true;
}

} // namespace factory::machine_placement
