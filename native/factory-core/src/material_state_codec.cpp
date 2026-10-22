#include "factory/material_state_codec.hpp"

#include <algorithm>
#include <initializer_list>
#include <set>
#include <string_view>
#include <utility>

namespace factory::materials {
namespace {

using values::Type;
using values::Value;
using Object = Value::Object;
using Roster = std::set<std::string>;

[[noreturn]] void refuse(CodecReason reason, const std::string& path,
                         Error error = Error::none) {
    throw CodecRefusal{reason, path, error};
}

std::string actor_path(const std::string& actor) {
    constexpr char hex[] = "0123456789abcdef";
    std::string result = "$.cargo[\"";
    for (const unsigned char character : actor) {
        if (character == '"' || character == '\\') {
            result += '\\';
            result += static_cast<char>(character);
        } else if (character < 0x20) {
            result += "\\u00";
            result += hex[character >> 4];
            result += hex[character & 0xf];
        } else result += static_cast<char>(character);
    }
    return result + "\"]";
}

Roster expected_roster(const std::vector<std::string>& roster) {
    Roster result;
    for (const auto& actor : roster) {
        if (actor.empty() || !result.insert(actor).second)
            refuse(CodecReason::invalid_roster, "$.cargo");
    }
    return result;
}

const Object& object(const Value& value, const std::string& path) {
    if (value.type() != Type::object) refuse(CodecReason::wrong_type, path);
    return std::get<Object>(value.storage());
}

const Object& fields(const Value& value, const std::string& path,
                     std::initializer_list<std::string_view> names) {
    const auto& result = object(value, path);
    for (const auto name : names) {
        if (!result.contains(std::string(name)))
            refuse(CodecReason::missing_field, path + "." + std::string(name));
    }
    for (const auto& [name, entry] : result) {
        (void)entry;
        if (std::find(names.begin(), names.end(), name) == names.end())
            refuse(CodecReason::unexpected_field, path);
    }
    return result;
}

Quantity integer(const Value& value, const std::string& path) {
    if (value.type() != Type::integer) refuse(CodecReason::wrong_type, path);
    return std::get<Value::Integer>(value.storage());
}

void validate_state(const State& state, const Config& config, const Path& path,
                    const Roster& roster) {
    if (state.cargo.size() != roster.size()) refuse(CodecReason::roster_mismatch, "$.cargo");
    for (const auto& [actor, cargo] : state.cargo) {
        (void)cargo;
        if (!roster.contains(actor)) refuse(CodecReason::roster_mismatch, "$.cargo");
    }
    const auto error = validate(state, config, path);
    if (error != Error::none) refuse(CodecReason::invalid_material_state, "$", error);
}

Value encode_lot(const WorkLot& lot) {
    return Value(Object{
        {"id", Value(lot.id)},
        {"recipe", Value(Object{
            {"input_units_per_product", Value(lot.recipe.input_units_per_product)},
            {"cycle_ticks", Value(lot.recipe.cycle_ticks)}})},
        {"remaining_ticks", Value(lot.remaining_ticks)},
        {"completed_subticks", Value(lot.completed_subticks)},
        {"work_remainder", Value(lot.work_remainder)},
        {"work_remainder_denominator", Value(lot.work_remainder_denominator)}});
}

WorkLot decode_lot(const Value& value, const std::string& path) {
    const auto& lot = fields(value, path, {"id", "recipe", "remaining_ticks", "completed_subticks", "work_remainder", "work_remainder_denominator"});
    const auto& recipe = fields(lot.at("recipe"), path + ".recipe",
                                {"input_units_per_product", "cycle_ticks"});
    return WorkLot{
        integer(lot.at("id"), path + ".id"),
        {integer(recipe.at("input_units_per_product"), path + ".recipe.input_units_per_product"),
         integer(recipe.at("cycle_ticks"), path + ".recipe.cycle_ticks")},
        integer(lot.at("remaining_ticks"), path + ".remaining_ticks"),
        integer(lot.at("completed_subticks"), path + ".completed_subticks"),
        integer(lot.at("work_remainder"), path + ".work_remainder"),
        integer(lot.at("work_remainder_denominator"), path + ".work_remainder_denominator")};
}

Value encode_cargo(const Cargo& cargo, bool resources) {
    Value::Array lots;
    lots.reserve(cargo.work_lots.size());
    for (const auto& lot : cargo.work_lots) lots.push_back(encode_lot(lot));
    Object output{{"raw_units", Value(cargo.raw_units)},
        {"products", Value(cargo.products)}, {"work_lots", Value(std::move(lots))}};
    if (resources) {
        output.emplace("timber", Value(cargo.timber));
        Object components;
        for (const auto& [kind, count] : cargo.components)
            components.emplace(component_name(kind), Value(count));
        output.emplace("components", Value(std::move(components)));
    }
    return Value(std::move(output));
}

Cargo decode_cargo(const Value& value, const std::string& path, bool resources) {
    const auto& entries = resources ?
        fields(value, path, {"raw_units", "products", "work_lots", "timber", "components"}) :
        fields(value, path, {"raw_units", "products", "work_lots"});
    const auto& lots = entries.at("work_lots");
    if (lots.type() != Type::array) refuse(CodecReason::wrong_type, path + ".work_lots");
    Cargo cargo;
    cargo.raw_units = integer(entries.at("raw_units"), path + ".raw_units");
    cargo.products = integer(entries.at("products"), path + ".products");
    if (resources) {
        cargo.timber = integer(entries.at("timber"), path + ".timber");
        const auto& components = object(entries.at("components"), path + ".components");
        if (components.size() > 11) refuse(CodecReason::invalid_material_state, path + ".components");
        for (const auto& [name, count] : components) {
            const auto component = component_from_name(name);
            if (!component) refuse(CodecReason::invalid_material_state, path + ".components." + name);
            cargo.components.emplace(*component, integer(count, path + ".components." + name));
        }
    }
    const auto& array = std::get<Value::Array>(lots.storage());
    cargo.work_lots.reserve(array.size());
    for (std::size_t index = 0; index < array.size(); ++index)
        cargo.work_lots.push_back(decode_lot(array[index],
            path + ".work_lots[" + std::to_string(index) + "]"));
    return cargo;
}

}  // namespace

const char* codec_reason_name(CodecReason reason) noexcept {
    switch (reason) {
        case CodecReason::invalid_roster: return "invalid_roster";
        case CodecReason::roster_mismatch: return "roster_mismatch";
        case CodecReason::wrong_type: return "wrong_type";
        case CodecReason::missing_field: return "missing_field";
        case CodecReason::unexpected_field: return "unexpected_field";
        case CodecReason::unsupported_schema: return "unsupported_schema";
        case CodecReason::invalid_material_state: return "invalid_material_state";
    }
    return "unknown_codec_reason";
}

MaterialEncoding encode_material_state(const State& state, const Config& config,
                                       const Path& path, const std::vector<std::string>& actors) {
    try {
        const bool resources = config.manual_ore || !config.timber_sites.empty();
        const auto roster = expected_roster(actors);
        validate_state(state, config, path, roster);
        Object cargo;
        for (const auto& [actor, contents] : state.cargo)
            cargo.emplace(actor, encode_cargo(contents, resources));
        Value::Array drops;
        for (const auto& [point, contents] : state.dropped_material)
            drops.emplace_back(Object{{"point", Value(Value::Array{Value(point[0]), Value(point[1]), Value(point[2])})},
                                      {"cargo", encode_cargo(contents, resources)}});
        Object lanes;
        for (const auto& [id, lane] : state.belt_lanes) {
            Value::Array slots;
            for (const auto& item : lane.slots) slots.push_back(item ? encode_cargo(*item, resources) : Value(nullptr));
            lanes.emplace(id, Value(Object{{"phase", Value(lane.phase)}, {"remainder", Value(lane.remainder)},
                {"remainder_denominator", Value(lane.remainder_denominator)}, {"slots", Value(std::move(slots))}}));
        }
        const auto& stock = state.stock;
        Object output{
            {"schema", Value(Value::Integer{resources ? 9 : 6})},
            {"initial_units", Value(state.initial_units)},
            {"stock", Value(Object{
                {"source", Value(stock.source)}, {"collector", Value(stock.collector)},
                {"belt", Value(stock.belt)}, {"input", Value(stock.input)},
                {"output", Value(stock.output)}})},
            {"cargo", Value(std::move(cargo))},
            {"dropped_material", Value(std::move(drops))},
            {"belt_lanes", Value(std::move(lanes))},
            {"processing", state.processing ? encode_lot(*state.processing) : Value(nullptr)},
            {"next_work_id", Value(state.next_work_id)}};
        if (resources) {
            Object remaining;
            for (const auto& [id, count] : state.timber_remaining)
                remaining.emplace(id, Value(count));
            output.emplace("timber_remaining", Value(std::move(remaining)));
            Object placed;
            for (const auto& [kind, count] : state.placed_components)
                placed.emplace(component_name(kind), Value(count));
            output.emplace("placed_components", Value(std::move(placed)));
        }
        return Value(std::move(output));
    } catch (const CodecRefusal& refusal) { return refusal; }
}

MaterialDecoding decode_material_state(const Value& value, const Config& config,
                                       const Path& path, const std::vector<std::string>& actors) {
    try {
        const bool resources = config.manual_ore || !config.timber_sites.empty();
        const auto roster = expected_roster(actors);
        const auto& root = resources ? fields(value, "$",
            {"schema", "initial_units", "stock", "cargo", "dropped_material", "belt_lanes", "processing", "next_work_id", "timber_remaining", "placed_components"}) :
            fields(value, "$", {"schema", "initial_units", "stock", "cargo", "dropped_material", "belt_lanes", "processing", "next_work_id"});
        if (integer(root.at("schema"), "$.schema") != (resources ? 9 : 6))
            refuse(CodecReason::unsupported_schema, "$.schema");
        const auto& stock = fields(root.at("stock"), "$.stock",
                                    {"source", "collector", "belt", "input", "output"});
        State candidate;
        candidate.initial_units = integer(root.at("initial_units"), "$.initial_units");
        candidate.stock = {
            integer(stock.at("source"), "$.stock.source"),
            integer(stock.at("collector"), "$.stock.collector"),
            integer(stock.at("belt"), "$.stock.belt"),
            integer(stock.at("input"), "$.stock.input"),
            integer(stock.at("output"), "$.stock.output")};
        if (resources) {
            const auto& trees = object(root.at("timber_remaining"), "$.timber_remaining");
            if (trees.size() > 16) refuse(CodecReason::invalid_material_state, "$.timber_remaining");
            for (const auto& [id, count] : trees)
                candidate.timber_remaining.emplace(id, integer(count, "$.timber_remaining." + id));
            const auto& placed = object(root.at("placed_components"), "$.placed_components");
            if (placed.size() > 11) refuse(CodecReason::invalid_material_state, "$.placed_components");
            for (const auto& [name, count] : placed) {
                const auto kind = component_from_name(name);
                if (!kind) refuse(CodecReason::invalid_material_state, "$.placed_components." + name);
                candidate.placed_components.emplace(*kind, integer(count, "$.placed_components." + name));
            }
        }
        const auto& lanes = object(root.at("belt_lanes"), "$.belt_lanes");
        if (lanes.size() > 256) refuse(CodecReason::invalid_material_state, "$.belt_lanes");
        for (const auto& [id, value_lane] : lanes) {
            const auto& entry = fields(value_lane, "$.belt_lanes", {"phase", "remainder", "remainder_denominator", "slots"});
            if (entry.at("slots").type() != Type::array) refuse(CodecReason::wrong_type, "$.belt_lanes.slots");
            const auto& slots = std::get<Value::Array>(entry.at("slots").storage());
            if (slots.size() < 2 || slots.size() > maximum_belt_slots)
                refuse(CodecReason::invalid_material_state, "$.belt_lanes.slots");
            BeltLane lane;
            lane.phase = integer(entry.at("phase"), "$.belt_lanes.phase");
            lane.remainder = integer(entry.at("remainder"), "$.belt_lanes.remainder");
            lane.remainder_denominator = integer(entry.at("remainder_denominator"), "$.belt_lanes.remainder_denominator");
            for (const auto& value_item : slots) {
                if (value_item.type() == Type::null) {
                    lane.slots.emplace_back(std::nullopt);
                } else {
                    const auto& item = resources ?
                        fields(value_item, "$.belt_lanes.item", {"raw_units", "products", "work_lots", "timber", "components"}) :
                        fields(value_item, "$.belt_lanes.item", {"raw_units", "products", "work_lots"});
                    if (item.at("work_lots").type() != Type::array ||
                        std::get<Value::Array>(item.at("work_lots").storage()).size() > 1)
                        refuse(CodecReason::invalid_material_state, "$.belt_lanes.item");
                    lane.slots.emplace_back(decode_cargo(value_item, "$.belt_lanes.item", resources));
                }
            }
            candidate.belt_lanes.emplace(id, std::move(lane));
        }
        if (root.at("dropped_material").type() != Type::array) refuse(CodecReason::wrong_type, "$.dropped_material");
        const auto& drops = std::get<Value::Array>(root.at("dropped_material").storage());
        if (drops.size() > maximum_drop_points) refuse(CodecReason::invalid_material_state, "$");
        for (std::size_t i = 0; i < drops.size(); ++i) {
            const auto path = "$.dropped_material[" + std::to_string(i) + "]";
            const auto& entry = fields(drops[i], path, {"point", "cargo"});
            if (entry.at("point").type() != Type::array) refuse(CodecReason::wrong_type, path + ".point");
            const auto& coordinates = std::get<Value::Array>(entry.at("point").storage());
            if (coordinates.size() != 3) refuse(CodecReason::invalid_material_state, path + ".point");
            DropPoint point{};
            for (std::size_t j = 0; j < 3; ++j)
                point[j] = integer(coordinates[j], path + ".point[" + std::to_string(j) + "]");
            if (!candidate.dropped_material.emplace(point, decode_cargo(entry.at("cargo"), path + ".cargo", resources)).second)
                refuse(CodecReason::invalid_material_state, path + ".point");
        }
        const auto& cargo = object(root.at("cargo"), "$.cargo");
        if (cargo.size() != roster.size()) refuse(CodecReason::roster_mismatch, "$.cargo");
        for (const auto& [actor, contents] : cargo) {
            if (!roster.contains(actor)) refuse(CodecReason::roster_mismatch, "$.cargo");
            candidate.cargo.emplace(actor, decode_cargo(contents, actor_path(actor), resources));
        }
        if (root.at("processing").type() != Type::null)
            candidate.processing = decode_lot(root.at("processing"), "$.processing");
        candidate.next_work_id = integer(root.at("next_work_id"), "$.next_work_id");
        validate_state(candidate, config, path, roster);
        return candidate;
    } catch (const CodecRefusal& refusal) { return refusal; }
}

}  // namespace factory::materials
