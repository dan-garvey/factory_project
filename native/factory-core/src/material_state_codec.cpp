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
        {"remaining_ticks", Value(lot.remaining_ticks)}});
}

WorkLot decode_lot(const Value& value, const std::string& path) {
    const auto& lot = fields(value, path, {"id", "recipe", "remaining_ticks"});
    const auto& recipe = fields(lot.at("recipe"), path + ".recipe",
                                {"input_units_per_product", "cycle_ticks"});
    return WorkLot{
        integer(lot.at("id"), path + ".id"),
        {integer(recipe.at("input_units_per_product"), path + ".recipe.input_units_per_product"),
         integer(recipe.at("cycle_ticks"), path + ".recipe.cycle_ticks")},
        integer(lot.at("remaining_ticks"), path + ".remaining_ticks")};
}

Value encode_cargo(const Cargo& cargo) {
    Value::Array lots;
    lots.reserve(cargo.work_lots.size());
    for (const auto& lot : cargo.work_lots) lots.push_back(encode_lot(lot));
    return Value(Object{{"raw_units", Value(cargo.raw_units)},
                        {"products", Value(cargo.products)},
                        {"work_lots", Value(std::move(lots))}});
}

Cargo decode_cargo(const Value& value, const std::string& path) {
    const auto& entries = fields(value, path, {"raw_units", "products", "work_lots"});
    const auto& lots = entries.at("work_lots");
    if (lots.type() != Type::array) refuse(CodecReason::wrong_type, path + ".work_lots");
    Cargo cargo;
    cargo.raw_units = integer(entries.at("raw_units"), path + ".raw_units");
    cargo.products = integer(entries.at("products"), path + ".products");
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
        const auto roster = expected_roster(actors);
        validate_state(state, config, path, roster);
        Object cargo;
        for (const auto& [actor, contents] : state.cargo)
            cargo.emplace(actor, encode_cargo(contents));
        const auto& stock = state.stock;
        return Value(Object{
            {"schema", Value(Value::Integer{1})},
            {"initial_units", Value(state.initial_units)},
            {"stock", Value(Object{
                {"source", Value(stock.source)}, {"collector", Value(stock.collector)},
                {"belt", Value(stock.belt)}, {"input", Value(stock.input)},
                {"output", Value(stock.output)}})},
            {"cargo", Value(std::move(cargo))},
            {"processing", state.processing ? encode_lot(*state.processing) : Value(nullptr)},
            {"next_work_id", Value(state.next_work_id)}});
    } catch (const CodecRefusal& refusal) { return refusal; }
}

MaterialDecoding decode_material_state(const Value& value, const Config& config,
                                       const Path& path, const std::vector<std::string>& actors) {
    try {
        const auto roster = expected_roster(actors);
        const auto& root = fields(value, "$",
            {"schema", "initial_units", "stock", "cargo", "processing", "next_work_id"});
        if (integer(root.at("schema"), "$.schema") != 1)
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
        const auto& cargo = object(root.at("cargo"), "$.cargo");
        if (cargo.size() != roster.size()) refuse(CodecReason::roster_mismatch, "$.cargo");
        for (const auto& [actor, contents] : cargo) {
            if (!roster.contains(actor)) refuse(CodecReason::roster_mismatch, "$.cargo");
            candidate.cargo.emplace(actor, decode_cargo(contents, actor_path(actor)));
        }
        if (root.at("processing").type() != Type::null)
            candidate.processing = decode_lot(root.at("processing"), "$.processing");
        candidate.next_work_id = integer(root.at("next_work_id"), "$.next_work_id");
        validate_state(candidate, config, path, roster);
        return candidate;
    } catch (const CodecRefusal& refusal) { return refusal; }
}

}  // namespace factory::materials
