#include "native/factory-godot-world/src/arrival_configuration.hpp"
#include "native/factory-godot-world/src/checkpoint_envelope.hpp"
#include "factory/checkpoint.hpp"

#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <string_view>
#include <variant>

namespace {
using Value = factory::values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
namespace envelope = factory::godot_world::checkpoint_envelope;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

void check_reason(const Object& outer, std::string_view expected) {
    const auto parsed = envelope::parse(Value(outer));
    const auto* refusal = std::get_if<const char*>(&parsed);
    check(refusal && std::string_view(*refusal) == expected,
          "Malformed save envelopes must retain their existing refusal reason.");
}

void versioned_envelopes() {
    const auto content = factory::godot_world::make_arrival_configuration(true, false, {"P", "Q"});
    check(content.has_value(), "The authored two-worker arrival state must exist.");
    auto world = factory::world::World::create("checkpoint-envelope", content->profile, content->seed);
    check(world != nullptr, "The native World must admit its authored arrival state.");
    const auto snapshot = world->snapshot();
    std::map<std::string, factory::authority::Point> actor_positions;
    for (const auto& [actor, point] : content->actor_starts)
        actor_positions.emplace(actor, point);
    const auto saved = envelope::encode(content->profile, snapshot, actor_positions, {});
    check(saved.has_value(), "The trusted native World must produce an adapter save envelope.");
    const auto& outer = std::get<Object>(saved->storage());
    const auto parsed = envelope::parse(*saved);
    const auto* current = std::get_if<envelope::Parsed>(&parsed);
    check(current && current->schema == 4 && current->world == &outer.at("world") &&
          current->actors == &std::get<Object>(outer.at("actors").storage()) &&
          current->context && *current->context == "checkpoint-envelope" &&
          current->support_routes.empty() && current->actors->size() == 2 &&
          std::get<Array>(current->actors->at("P").storage()).size() == 3,
          "A current save carries its exact native payload, context and both physical actor seeds.");
    check(current && std::holds_alternative<factory::world::Snapshot>(
              factory::world::decode_checkpoint(content->profile, *current->context, *current->world)) &&
          world->snapshot().state == snapshot.state && world->snapshot().revision == snapshot.revision,
          "Parsing does not change the native World or weaken its separate checkpoint validation.");

    auto historical = outer;
    historical.at("schema") = Value(Integer{3});
    historical.erase("support_routes");
    const Value historical_value(historical);
    const auto old = envelope::parse(historical_value);
    const auto* old_fields = std::get_if<envelope::Parsed>(&old);
    check(old_fields && old_fields->schema == 3 && old_fields->support_routes.empty(),
          "The previously accepted schema 3 save has no authored support route preferences.");

    auto routed = outer;
    routed.at("support_routes") = Value(Object{{"shaft-one", Value(Integer{2})}});
    const Value routed_value(routed);
    const auto routed_fields = envelope::parse(routed_value);
    const auto* parsed_routes = std::get_if<envelope::Parsed>(&routed_fields);
    check(parsed_routes && parsed_routes->support_routes.at("shaft-one") == 2,
          "Schema 4 keeps the integer support route for Host's later physical validation.");

    const Value missing_root(nullptr);
    const auto non_object = envelope::parse(missing_root);
    check(std::get_if<const char*>(&non_object) != nullptr,
          "A non-object save cannot enter the native decoder.");
    auto malformed = outer;
    malformed.at("schema") = Value(Integer{2});
    check_reason(malformed, "invalid_checkpoint");
    malformed = outer;
    malformed.at("schema") = Value(true);
    check_reason(malformed, "invalid_checkpoint");
    malformed = outer;
    malformed.emplace("unknown", Value(true));
    check_reason(malformed, "invalid_checkpoint");
    malformed = outer;
    malformed.at("format") = Value("another-format");
    check_reason(malformed, "invalid_checkpoint");
    malformed = outer;
    malformed.at("actors") = Value(Array{});
    check_reason(malformed, "invalid_checkpoint");
    malformed = outer;
    malformed.erase("support_routes");
    check_reason(malformed, "invalid_checkpoint");
    malformed = outer;
    malformed.at("support_routes") = Value(Array{});
    check_reason(malformed, "invalid_checkpoint");
    malformed = outer;
    malformed.at("support_routes") = Value(Object{{"shaft-one", Value(Integer{-1})}});
    check_reason(malformed, "invalid_support_route");
    malformed = outer;
    malformed.at("support_routes") = Value(Object{{"shaft-one", Value("second")}});
    check_reason(malformed, "invalid_support_route");
    malformed = outer;
    malformed.at("world") = Value(nullptr);
    check_reason(malformed, "invalid_context");
    malformed = historical;
    malformed.emplace("support_routes", Value(Object{}));
    check_reason(malformed, "invalid_checkpoint");
}
}  // namespace

int main() {
    try {
        versioned_envelopes();
        std::cout << "CHECKPOINT_ENVELOPE_PASS " << checks << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Checkpoint envelope check failed: " << error.what() << '\n';
        return 1;
    }
}
