#pragma once

#include "factory/command_contract.hpp"
#include "factory/mechanics.hpp"

#include <array>
#include <string_view>

namespace factory::transmission_placement {

using command_contract::Field;
using command_contract::Object;
using command_contract::Schema;
using command_contract::Type;
using Integer = values::Value::Integer;
using Array = values::Value::Array;

enum class Action { none, shaft, gear, relay };

inline Schema schema(Action action, bool wire) {
    static constexpr std::array shaft{
        Field{"center", "center", Type::array}, Field{"axis", "axis", Type::string},
        Field{"half_span", "half_span", Type::integer},
        Field{"", "role", Type::string}, Field{"", "teeth", Type::integer},
    };
    static constexpr std::array gear{
        Field{"center", "center", Type::array}, Field{"axis", "axis", Type::string},
        Field{"teeth", "teeth", Type::integer},
        Field{"", "role", Type::string}, Field{"", "half_span", Type::integer},
    };
    static constexpr std::array relay{
        Field{"kind", "role", Type::string}, Field{"center", "center", Type::array},
        Field{"axis", "axis", Type::string},
        Field{"relay_axis", "relay_axis", Type::string, true},
        Field{"", "teeth", Type::integer}, Field{"", "half_span", Type::integer},
    };
    switch (action) {
        case Action::shaft: return {wire ? "place_shaft" : "place", shaft};
        case Action::gear: return {wire ? "place_gear" : "place", gear};
        case Action::relay: return {wire ? "place_relay" : "place", relay};
        case Action::none: return {};
    }
    return {};
}

inline Action parse_wire(std::string_view name) {
    for (const auto action : {Action::shaft, Action::gear, Action::relay})
        if (schema(action, true).name == name) return action;
    return Action::none;
}

inline bool relay_kind(std::string_view name) {
    return name == "gearbox" || name == "vertical_gearbox" || name == "chain_drive";
}

// Host still gives malformed centers, axes and sizes their established named
// refusals. Check the key set here before those values are read.
inline bool admission_shape(const Object& wire, Action action) {
    static constexpr std::array shaft_deferred{
        std::string_view{"center"}, std::string_view{"axis"},
        std::string_view{"half_span"},
    };
    static constexpr std::array gear_deferred{
        std::string_view{"center"}, std::string_view{"axis"},
        std::string_view{"teeth"},
    };
    static constexpr std::array relay_deferred{
        std::string_view{"center"}, std::string_view{"axis"},
    };
    switch (action) {
        case Action::shaft: return command_contract::valid(wire, schema(action, true), false, shaft_deferred);
        case Action::gear: return command_contract::valid(wire, schema(action, true), false, gear_deferred);
        case Action::relay: return command_contract::valid(wire, schema(action, true), false, relay_deferred);
        case Action::none: return false;
    }
    return false;
}

inline bool valid_wire(const Object& wire, Action action) {
    return command_contract::valid_wire(wire, schema(action, true));
}

inline std::string role(const Object& wire, Action action) {
    if (action == Action::shaft) return "shaft";
    if (action == Action::gear) return "gear";
    return std::get<std::string>(wire.at("kind").storage());
}

inline Integer teeth(const Object& wire, Action action) {
    return action == Action::gear ? std::get<Integer>(wire.at("teeth").storage()) : Integer{0};
}

inline Integer half_span(const Object& wire, Action action) {
    return action == Action::shaft ? std::get<Integer>(wire.at("half_span").storage()) : Integer{0};
}

inline void normalize(Object& intent, const Object& wire, Action action) {
    intent.at("action") = values::Value(std::string(schema(action, false).name));
    intent.emplace("role", values::Value(role(wire, action)));
    intent.emplace("center", wire.at("center"));
    intent.emplace("axis", wire.at("axis"));
    intent.emplace("teeth", values::Value(teeth(wire, action)));
    intent.emplace("half_span", values::Value(half_span(wire, action)));
    if (action == Action::relay && wire.contains("relay_axis"))
        intent.emplace("relay_axis", wire.at("relay_axis"));
}

inline bool valid_intent(const Object& intent, Action action) {
    if (!command_contract::valid_intent(intent, schema(action, false))) return false;
    const auto& selected_role = std::get<std::string>(intent.at("role").storage());
    if (action == Action::relay && !relay_kind(selected_role)) return false;
    return (action != Action::shaft || selected_role == "shaft") &&
        (action != Action::gear || selected_role == "gear") &&
        (action == Action::gear || std::get<Integer>(intent.at("teeth").storage()) == 0) &&
        (action == Action::shaft || std::get<Integer>(intent.at("half_span").storage()) == 0) &&
        (action != Action::relay ||
         intent.contains("relay_axis") == (selected_role == "chain_drive"));
}

// Direct World callers can submit a relay without an adapter wire. Keep their
// historical key-only admission: the stationary planner still gives malformed
// part values its established invalid_part refusal.
inline bool direct_relay_intent_shape(const Object& intent, std::string_view normalized_action) {
    if ((normalized_action != "place" && normalized_action != "place_connected") ||
        !intent.contains("relay_axis")) return false;
    static constexpr std::array deferred{
        std::string_view{"role"}, std::string_view{"center"},
        std::string_view{"axis"}, std::string_view{"teeth"},
        std::string_view{"half_span"}, std::string_view{"relay_axis"},
    };
    return command_contract::valid(intent,
        {normalized_action, schema(Action::relay, false).fields}, true, deferred);
}

inline bool valid_center(const Array& center) {
    if (center.size() != 3) return false;
    for (const auto& value : center) {
        const auto* coordinate = std::get_if<Integer>(&value.storage());
        if (!coordinate || *coordinate < -mechanics::maximum_coordinate ||
            *coordinate > mechanics::maximum_coordinate) return false;
    }
    return true;
}

inline bool valid_axis(std::string_view axis) {
    return axis == "x" || axis == "y" || axis == "z";
}

inline bool historical_wire(const Object& wire, const Object& intent, Action action) {
    if (!valid_wire(wire, action) || !valid_intent(intent, action)) return false;
    for (const auto& field : schema(action, true).fields) {
        if (field.wire.empty()) continue;
        const auto original = wire.find(std::string(field.wire));
        const auto normalized = intent.find(std::string(field.intent));
        if (original == wire.end()) {
            if (normalized != intent.end()) return false;
        } else if (normalized == intent.end() ||
                   values::typed_difference(original->second, normalized->second)) return false;
    }
    if (std::get<std::string>(intent.at("role").storage()) != role(wire, action) ||
        std::get<Integer>(intent.at("teeth").storage()) != teeth(wire, action) ||
        std::get<Integer>(intent.at("half_span").storage()) != half_span(wire, action)) return false;
    const auto& center = std::get<Array>(wire.at("center").storage());
    const auto& axis = std::get<std::string>(wire.at("axis").storage());
    if (!valid_center(center) || !valid_axis(axis)) return false;
    if (action == Action::shaft)
        return std::get<Integer>(wire.at("half_span").storage()) == 2;
    if (action == Action::gear) {
        const auto teeth = std::get<Integer>(wire.at("teeth").storage());
        return teeth > 0 && teeth <= mechanics::maximum_dimension;
    }
    const auto& role = std::get<std::string>(wire.at("kind").storage());
    if ((role == "gearbox" && axis != "y") ||
        (role == "vertical_gearbox" && axis == "y")) return false;
    if (role != "chain_drive") return true;
    const auto& relay_axis = std::get<std::string>(wire.at("relay_axis").storage());
    return valid_axis(relay_axis) && relay_axis != axis;
}

} // namespace factory::transmission_placement
