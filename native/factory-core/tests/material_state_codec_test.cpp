#include "factory/material_state_codec.hpp"

#include <iostream>
#include <limits>
#include <optional>
#include <stdexcept>
#include <utility>

namespace m = factory::materials;
using factory::values::Value;
using Object = Value::Object;
namespace {

int checks = 0;
const m::Config config{2, 2, 4};
const m::Path path{true, true, true, true, true, true};
const std::vector<std::string> roster{"P", "Q"};

void check(bool good) {
    if (!good) throw std::runtime_error("A material codec control failed.");
    ++checks;
}
Value integer(m::Quantity value) { return Value(value); }

m::State fixture() {
    m::State state;
    state.initial_units = 16;
    state.stock = {6, 1, 1, 1, 1};
    state.cargo = {{"P", m::Cargo{1, 0, {{8, {2, 4}, 0}}}}, {"Q", {}}};
    state.processing = m::WorkLot{7, {2, 4}, 3, m::work_subticks_per_tick / 2};
    state.next_work_id = 9;
    return state;
}

// Independent literal: nine loose raw units, one output product, one processing
// lot and P's raw unit plus ready carried lot account for all sixteen raw units.
Value literal() {
    return Value(Object{
        {"schema", integer(5)}, {"initial_units", integer(16)}, {"dropped_material", Value(Value::Array{})},
        {"belt_lanes", Value(Object{})},
        {"stock", Value(Object{{"source", integer(6)}, {"collector", integer(1)},
            {"belt", integer(1)}, {"input", integer(1)}, {"output", integer(1)}})},
        {"cargo", Value(Object{
            {"P", Value(Object{{"raw_units", integer(1)}, {"products", integer(0)},
                {"work_lots", Value(Value::Array{Value(Object{
                    {"id", integer(8)},
                    {"recipe", Value(Object{{"input_units_per_product", integer(2)},
                                             {"cycle_ticks", integer(4)}})},
                    {"remaining_ticks", integer(0)}, {"completed_subticks", integer(0)}})})}})},
            {"Q", Value(Object{{"raw_units", integer(0)}, {"products", integer(0)},
                                {"work_lots", Value(Value::Array{})}})}})},
        {"processing", Value(Object{
            {"id", integer(7)},
            {"recipe", Value(Object{{"input_units_per_product", integer(2)},
                                     {"cycle_ticks", integer(4)}})},
            {"remaining_ticks", integer(3)}, {"completed_subticks", integer(m::work_subticks_per_tick / 2)}})},
        {"next_work_id", integer(9)}});
}

Value edited(const Value& value, const std::vector<std::string>& keys,
             const std::optional<Value>& replacement, std::size_t index = 0) {
    auto object = std::get<Object>(value.storage());
    if (index + 1 == keys.size()) {
        if (replacement) object.insert_or_assign(keys[index], *replacement);
        else object.erase(keys[index]);
    } else object.at(keys[index]) = edited(object.at(keys[index]), keys, replacement, index + 1);
    return Value(std::move(object));
}

void bad(const Value& value, m::CodecReason reason, const std::string& field,
         m::Error material_error = m::Error::none) {
    const auto original = value;
    const auto result = m::decode_material_state(value, config, path, roster);
    check(std::holds_alternative<m::CodecRefusal>(result));
    const auto& refusal = std::get<m::CodecRefusal>(result);
    check(refusal.reason == reason && refusal.path == field && refusal.material_error == material_error);
    check(!factory::values::typed_difference(original, value));
}

void round_trip(const m::State& state, const m::Path& context = path,
                const std::vector<std::string>& actors = roster) {
    const auto original = state;
    const auto encoded = m::encode_material_state(state, config, context, actors);
    check(std::holds_alternative<Value>(encoded));
    const auto decoded = m::decode_material_state(std::get<Value>(encoded), config, context, actors);
    check(std::holds_alternative<m::State>(decoded));
    check(std::get<m::State>(decoded) == original && state == original);
}

}  // namespace

int main() {
    try {
        const auto state = fixture();
        check(m::validate(state, config, path) == m::Error::none);
        const auto encoded = m::encode_material_state(state, config, path, {"Q", "P"});
        check(std::holds_alternative<Value>(encoded));
        check(!factory::values::typed_difference(literal(), std::get<Value>(encoded)));
        const auto decoded = m::decode_material_state(literal(), config, path, roster);
        check(std::holds_alternative<m::State>(decoded));
        check(std::get<m::State>(decoded) == state);
        check(std::get<m::State>(decoded).processing->remaining_ticks == 3);
        check(std::get<m::State>(decoded).cargo.at("P").work_lots.at(0).remaining_ticks == 0);
        round_trip(state);

        auto dropped = state;
        dropped.stock.source -= 2;
        dropped.dropped_material.emplace(m::DropPoint{-2, 0, 4}, m::Cargo{2, 0, {}});
        round_trip(dropped); // Loose custody survives without a machine owner.

        auto typed_drop = state;
        typed_drop.stock.source -= 2;
        auto carried_work = typed_drop.cargo.at("P").work_lots.front();
        typed_drop.cargo.at("P").work_lots.clear();
        typed_drop.dropped_material.emplace(m::DropPoint{-2, 0, 4}, m::Cargo{0, 1, {carried_work}});
        round_trip(typed_drop); // Plates and exact workpiece identity share the same loose store.
        typed_drop.cargo.at("P").work_lots.push_back(carried_work);
        check(m::validate(typed_drop, config, path) == m::Error::invalid_state);

        auto on_belt = state;
        on_belt.stock.source -= 1;
        const auto carried_lot = on_belt.cargo.at("P").work_lots.front();
        on_belt.cargo.at("P").work_lots.clear();
        on_belt.belt_lanes.emplace("span", m::BeltLane{{m::Cargo{1, 0, {}}, std::nullopt,
            m::Cargo{0, 0, {carried_lot}}}, -123, -2, 3});
        round_trip(on_belt);
        auto changed_rate = m::advance_belt_lane_rate(on_belt.belt_lanes.at("span"), 1, 7, 1, false, 0);
        check(changed_rate.has_value() && changed_rate->candidate.remainder_denominator == 21 && changed_rate->delivered.empty());
        auto changed_state = on_belt;
        changed_state.belt_lanes.at("span") = changed_rate->candidate;
        const auto changed_encoded = m::encode_material_state(changed_state, config, path, roster);
        check(std::holds_alternative<Value>(changed_encoded));
        const auto changed_decoded = m::decode_material_state(std::get<Value>(changed_encoded), config, path, roster);
        check(std::holds_alternative<m::State>(changed_decoded));
        const auto continued = m::advance_belt_lane_rate(changed_rate->candidate, 1, 7, -1, false, 0);
        const auto restored = m::advance_belt_lane_rate(std::get<m::State>(changed_decoded).belt_lanes.at("span"), 1, 7, -1, false, 0);
        check(continued && restored && continued->candidate == restored->candidate && continued->delivered == restored->delivered);
        auto duplicated = on_belt;
        duplicated.cargo.at("Q").work_lots.push_back(carried_lot);
        check(m::validate(duplicated, config, path) == m::Error::invalid_state);
        auto lost = on_belt;
        lost.belt_lanes.at("span").slots.front().reset();
        check(m::validate(lost, config, path) == m::Error::invalid_state);

        auto ready = state;
        ready.processing->remaining_ticks = 0;
        ready.processing->completed_subticks = 0;
        round_trip(ready); // Ready work remains present, separate from null.
        auto carried = state;
        carried.cargo.at("P").work_lots.insert(carried.cargo.at("P").work_lots.begin(), *carried.processing);
        carried.processing.reset();
        round_trip(carried); // Original array order and both lot identities survive.

        bad(Value(Value::Array{}), m::CodecReason::wrong_type, "$");
        bad(edited(literal(), {"schema"}, std::nullopt), m::CodecReason::missing_field, "$.schema");
        bad(edited(literal(), {"schema"}, integer(1)), m::CodecReason::unsupported_schema, "$.schema");
        bad(edited(literal(), {"schema"}, integer(2)), m::CodecReason::unsupported_schema, "$.schema");
        bad(edited(literal(), {"schema"}, integer(3)), m::CodecReason::unsupported_schema, "$.schema");
        bad(edited(literal(), {"schema"}, integer(4)), m::CodecReason::unsupported_schema, "$.schema");
        bad(edited(literal(), {"dropped_material"}, std::nullopt), m::CodecReason::missing_field, "$.dropped_material");
        bad(edited(literal(), {"dropped_material"}, Value(Object{})), m::CodecReason::wrong_type, "$.dropped_material");
        const Value drop(Object{{"point", Value(Value::Array{integer(-2), integer(0), integer(4)})},
                                {"cargo", Value(Object{{"raw_units", integer(1)}, {"products", integer(0)}, {"work_lots", Value(Value::Array{})}})}});
        bad(edited(literal(), {"dropped_material"}, Value(Value::Array{drop, drop})),
            m::CodecReason::invalid_material_state, "$.dropped_material[1].point");
        const Value malformed_drop(Object{{"point", Value(Value::Array{integer(-2), integer(0)})},
                                          {"cargo", Value(Object{{"raw_units", integer(1)}, {"products", integer(0)}, {"work_lots", Value(Value::Array{})}})}});
        bad(edited(literal(), {"dropped_material"}, Value(Value::Array{malformed_drop})),
            m::CodecReason::invalid_material_state, "$.dropped_material[0].point");
        bad(edited(literal(), {"schema"}, Value(1.0)), m::CodecReason::wrong_type, "$.schema");
        bad(edited(literal(), {"unknown"}, integer(0)), m::CodecReason::unexpected_field, "$");
        bad(edited(literal(), {"stock", "source"}, std::nullopt), m::CodecReason::missing_field, "$.stock.source");
        bad(edited(literal(), {"stock", "other"}, integer(0)), m::CodecReason::unexpected_field, "$.stock");
        bad(edited(literal(), {"stock", "source"}, Value(6.0)), m::CodecReason::wrong_type, "$.stock.source");
        bad(edited(literal(), {"stock", "source"}, Value(true)), m::CodecReason::wrong_type, "$.stock.source");
        bad(edited(literal(), {"stock", "source"}, Value("6")), m::CodecReason::wrong_type, "$.stock.source");
        bad(edited(literal(), {"stock", "source"}, integer(-1)), m::CodecReason::invalid_material_state, "$", m::Error::invalid_state);
        bad(edited(literal(), {"stock", "source"}, integer(5)), m::CodecReason::invalid_material_state, "$", m::Error::invalid_state);
        bad(edited(literal(), {"processing"}, Value(false)), m::CodecReason::wrong_type, "$.processing");
        bad(edited(literal(), {"processing", "id"}, Value(7.0)), m::CodecReason::wrong_type, "$.processing.id");
        bad(edited(literal(), {"processing", "id"}, integer(8)), m::CodecReason::invalid_material_state, "$", m::Error::invalid_state);
        bad(edited(literal(), {"next_work_id"}, integer(8)), m::CodecReason::invalid_material_state, "$", m::Error::invalid_state);
        bad(edited(literal(), {"processing", "remaining_ticks"}, integer(-1)), m::CodecReason::invalid_material_state, "$", m::Error::invalid_state);
        bad(edited(literal(), {"processing", "remaining_ticks"}, integer(5)), m::CodecReason::invalid_material_state, "$", m::Error::invalid_state);
        bad(edited(literal(), {"processing", "completed_subticks"}, integer(m::work_subticks_per_tick)), m::CodecReason::invalid_material_state, "$", m::Error::invalid_state);
        bad(edited(literal(), {"processing", "completed_subticks"}, std::nullopt), m::CodecReason::missing_field, "$.processing.completed_subticks");
        bad(edited(literal(), {"processing", "recipe", "cycle_ticks"}, integer(5)), m::CodecReason::invalid_material_state, "$", m::Error::invalid_state);
        bad(edited(literal(), {"processing", "recipe", "extra"}, integer(0)), m::CodecReason::unexpected_field, "$.processing.recipe");
        bad(edited(literal(), {"cargo", "P", "raw_units"}, Value(1.0)), m::CodecReason::wrong_type, "$.cargo[\"P\"].raw_units");
        bad(edited(literal(), {"cargo", "P", "work_lots"}, Value(Object{})), m::CodecReason::wrong_type, "$.cargo[\"P\"].work_lots");
        bad(edited(literal(), {"cargo", "Q"}, std::nullopt), m::CodecReason::roster_mismatch, "$.cargo");
        bad(edited(literal(), {"cargo", "R"}, Value(Object{})), m::CodecReason::roster_mismatch, "$.cargo");
        bad(edited(literal(), {"cargo", "Q", "extra"}, integer(0)), m::CodecReason::unexpected_field, "$.cargo[\"Q\"]");
        const auto processing_record = std::get<Object>(literal().storage()).at("processing");
        const auto floating_lot = edited(processing_record, {"id"}, Value(8.0));
        bad(edited(literal(), {"cargo", "P", "work_lots"}, Value(Value::Array{floating_lot})),
            m::CodecReason::wrong_type, "$.cargo[\"P\"].work_lots[0].id");
        const auto unknown_lot = edited(processing_record, {"extra"}, integer(0));
        bad(edited(literal(), {"cargo", "P", "work_lots"}, Value(Value::Array{unknown_lot})),
            m::CodecReason::unexpected_field, "$.cargo[\"P\"].work_lots[0]");
        bad(edited(literal(), {"next_work_id"}, Value(9007199254740994.0)),
            m::CodecReason::wrong_type, "$.next_work_id");
        const auto over_capacity = edited(edited(literal(), {"stock", "source"}, integer(4)),
                                          {"stock", "collector"}, integer(3));
        bad(over_capacity, m::CodecReason::invalid_material_state, "$", m::Error::invalid_state);
        const auto overflow = edited(literal(), {"stock", "source"},
                                     integer(std::numeric_limits<m::Quantity>::max()));
        bad(overflow, m::CodecReason::invalid_material_state, "$", m::Error::quantity_overflow);

        for (const auto& actors : std::vector<std::vector<std::string>>{{"P", "P"}, {"", "Q"}}) {
            const auto result = m::encode_material_state(state, config, path, actors);
            check(std::holds_alternative<m::CodecRefusal>(result));
            check(std::get<m::CodecRefusal>(result).reason == m::CodecReason::invalid_roster);
            const auto read = m::decode_material_state(literal(), config, path, actors);
            check(std::get<m::CodecRefusal>(read).reason == m::CodecReason::invalid_roster);
        }
        const auto mismatch = m::encode_material_state(state, config, path, {"P", "R"});
        check(std::get<m::CodecRefusal>(mismatch).reason == m::CodecReason::roster_mismatch);
        auto absent = path;
        absent.processor_present = false;
        const auto invalid_path = m::decode_material_state(literal(), config, absent, roster);
        check(std::get<m::CodecRefusal>(invalid_path).material_error == m::Error::invalid_path);
        const auto invalid_config = m::decode_material_state(literal(), {0, 2, 4}, path, roster);
        check(std::get<m::CodecRefusal>(invalid_config).material_error == m::Error::invalid_configuration);
        auto invalid_state = state;
        ++invalid_state.cargo.at("P").products;
        const auto invalid_encode = m::encode_material_state(invalid_state, config, path, roster);
        check(std::get<m::CodecRefusal>(invalid_encode).material_error == m::Error::invalid_state);

        for (const auto total : {m::Quantity{9007199254740993LL}, std::numeric_limits<m::Quantity>::max()}) {
            m::State large;
            large.initial_units = total;
            large.stock.source = total;
            large.cargo = {{"P", {}}, {"Q", {}}};
            large.next_work_id = std::numeric_limits<m::WorkId>::max();
            round_trip(large, {});
        }
        auto large_serial = state;
        large_serial.processing->id = 9007199254740993LL;
        large_serial.next_work_id = 9007199254740994LL;
        round_trip(large_serial);
        m::State empty;
        round_trip(empty, {}, {});
        check(state == fixture());
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks
                  << ",\"evidence\":\"invented_material_codec_controls\"}\n";
        return 0;
    } catch (...) {
        std::cerr << "{\"status\":\"fail\",\"evidence\":\"invented_material_codec_controls\"}\n";
        return 1;
    }
}
