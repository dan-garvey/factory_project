#pragma once

#include "factory/command_contract.hpp"
#include "factory/mechanics.hpp"

#include <array>
#include <cmath>
#include <optional>
#include <string_view>

namespace factory::foundation_commands {

using command_contract::Field;
using command_contract::Object;
using command_contract::Schema;
using command_contract::Type;
using Integer = values::Value::Integer;
using Center = std::array<Integer, 3>;

inline constexpr Integer maximum_area_side = 256;

enum class Action { none, place_one, place_area, remove_one };

inline Schema schema(Action action) {
    static constexpr std::array place_one{
        Field{"cell", "", Type::array},
        Field{"level", "", Type::integer},
        Field{"", "center", Type::array},
    };
    static constexpr std::array place_area{
        Field{"cell", "", Type::array},
        Field{"end_cell", "", Type::array},
        Field{"level", "", Type::integer},
        Field{"", "center", Type::array},
        Field{"", "end", Type::array},
    };
    static constexpr std::array remove_one{
        Field{"entity", "target", Type::string},
        Field{"", "generation", Type::integer},
    };
    switch (action) {
        case Action::place_one: return {"place_foundation", place_one};
        case Action::place_area: return {"place_foundations", place_area};
        case Action::remove_one: return {"remove_foundation", remove_one};
        case Action::none: return {};
    }
    return {};
}

inline Action parse(std::string_view name) {
    for (const auto action : {Action::place_one, Action::place_area, Action::remove_one})
        if (schema(action).name == name) return action;
    return Action::none;
}

// A player removes a foundation through the ordinary remove wire. Host chooses
// the native foundation action only after looking up the current target.
inline std::string_view wire_name(Action action) {
    return action == Action::remove_one ? "remove" : schema(action).name;
}

inline Schema wire_schema(Action action) { return {wire_name(action), schema(action).fields}; }

inline bool valid_wire(const Object& wire, Action action) {
    return command_contract::valid_wire(wire, wire_schema(action));
}
inline bool valid_wire_before_geometry(const Object& wire, Action action) {
    static constexpr std::array<std::string_view, 3> deferred{"cell", "end_cell", "level"};
    return command_contract::valid(wire, wire_schema(action), false, deferred);
}
inline bool valid_intent(const Object& intent, Action action) {
    return command_contract::valid_intent(intent, schema(action));
}
inline bool valid_intent_before_geometry(const Object& intent, Action action) {
    static constexpr std::array<std::string_view, 4> deferred{"center", "end", "target", "generation"};
    return command_contract::valid(intent, schema(action), true, deferred);
}

inline std::optional<Center> center(const Object& wire, std::string_view name) {
    const auto cell = wire.find(std::string(name));
    const auto level = wire.find("level");
    if (cell == wire.end() || level == wire.end()) return std::nullopt;
    const auto* coordinates = std::get_if<values::Value::Array>(&cell->second.storage());
    const auto* height = std::get_if<Integer>(&level->second.storage());
    if (!coordinates || coordinates->size() != 2 || !height ||
        *height < -mechanics::maximum_coordinate || *height > mechanics::maximum_coordinate)
        return std::nullopt;
    const auto* x = std::get_if<Integer>(&coordinates->at(0).storage());
    const auto* z = std::get_if<Integer>(&coordinates->at(1).storage());
    constexpr Integer maximum_cell = mechanics::maximum_coordinate / 4;
    if (!x || !z || *x < -maximum_cell || *x > maximum_cell ||
        *z < -maximum_cell || *z > maximum_cell) return std::nullopt;
    return Center{4 * *x, *height, 4 * *z};
}

inline bool area_fits(const Center& first, const Center& last) {
    const auto width = std::abs(last[0] - first[0]) / 4 + 1;
    const auto depth = std::abs(last[2] - first[2]) / 4 + 1;
    return width <= maximum_area_side && depth <= maximum_area_side &&
        width * depth <= maximum_area_side;
}

inline values::Value center_value(const Center& point) {
    return values::Value(values::Value::Array{
        values::Value(point[0]), values::Value(point[1]), values::Value(point[2])});
}

inline bool historical_wire(const Object& wire, const Object& intent, Action action) {
    if (!valid_wire(wire, action) || !valid_intent(intent, action)) return false;
    if (action == Action::remove_one)
        return !values::typed_difference(wire.at("entity"), intent.at("target"));
    const auto first = center(wire, "cell");
    const auto last = action == Action::place_area ? center(wire, "end_cell") : first;
    if (!first || !last || !area_fits(*first, *last) ||
        values::typed_difference(center_value(*first), intent.at("center"))) return false;
    return action != Action::place_area ||
        !values::typed_difference(center_value(*last), intent.at("end"));
}

} // namespace factory::foundation_commands
