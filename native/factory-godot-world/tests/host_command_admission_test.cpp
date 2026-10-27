#include "native/factory-godot-world/src/host_command_admission.hpp"

#include <iostream>
#include <stdexcept>
#include <string>
#include <variant>

namespace {
using Value = factory::values::Value;
using Object = Value::Object;
using History = factory::authority::History;
namespace admission = factory::godot_world::command_admission;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

const Value& field(const Object& object, const char* name) { return object.at(name); }

void actor_and_retry_admission() {
    const std::set<std::string> actors{"P", "Q"};
    const Object original_wire{{"context", Value("opening")}, {"client", Value("P")},
        {"request", Value("build-1")}, {"action", Value("place")},
        {"cell", Value(Value::Array{Value(Value::Integer{2}), Value(Value::Integer{3})})}};
    const Object saved{{"context", Value("opening")}, {"client", Value("P")},
        {"request", Value("build-1")}, {"actor", Value("P")},
        {"action", Value("place")}, {"generation", Value(Value::Integer{4})},
        {"wire", Value(original_wire)}};
    History history{"opening", 1, {{saved, Object{{"accepted", Value(true)}}}}};
    const auto examine = [&](const std::string& actor, const Object& wire) {
        const auto bound = admission::bind_actor(actors, actor, wire);
        if (!bound) throw std::runtime_error("A valid test actor was refused.");
        return admission::examine(*bound, history, wire);
    };

    auto fresh_wire = original_wire;
    fresh_wire.at("request") = Value("build-2");
    const auto fresh = examine("P", fresh_wire);
    const auto* envelope = std::get_if<admission::Fresh>(&fresh);
    check(envelope && std::get<std::string>(field(envelope->normalized, "action").storage()) ==
            "adapter_refusal" &&
            !factory::values::typed_difference(field(envelope->normalized, "wire"), Value(fresh_wire)) &&
            std::get<std::string>(field(envelope->normalized, "actor").storage()) == "P",
          "A fresh request keeps its exact wire and bound actor in the native envelope.");
    const auto duplicate = examine("P", original_wire);
    const auto* replay = std::get_if<admission::Replay>(&duplicate);
    check(replay && std::get<Value::Integer>(field(replay->intent, "generation").storage()) == 4 &&
            !factory::values::typed_difference(field(replay->intent, "wire"), Value(original_wire)),
          "A retry uses the original normalized action and generation before current lookup.");
    auto changed_wire = original_wire;
    changed_wire.at("cell") = Value(Value::Array{Value(Value::Integer{9}), Value(Value::Integer{3})});
    const auto changed = examine("P", changed_wire);
    const auto* changed_replay = std::get_if<admission::Replay>(&changed);
    check(changed_replay &&
            !factory::values::typed_difference(field(changed_replay->intent, "wire"), Value(changed_wire)) &&
            std::get<Value::Integer>(field(changed_replay->intent, "generation").storage()) == 4 &&
            !factory::values::typed_difference(field(history.records.front().intent, "wire"),
                Value(original_wire)),
          "A reused ID carries the changed original wire to World without changing stored history.");
    auto q_wire = original_wire;
    q_wire.at("client") = Value("Q");
    check(std::holds_alternative<admission::Fresh>(examine("Q", q_wire)),
          "Another bound actor can use the same request ID without borrowing P's retry.");

    auto reserved = original_wire;
    reserved.at("request") = Value("native-cut-1");
    const auto rejected = examine("P", reserved);
    const auto* refusal = std::get_if<admission::Refusal>(&rejected);
    check(refusal && std::string(refusal->reason) == "reserved_request",
          "Client requests cannot occupy server-owned completion IDs.");
    check(!admission::bind_actor(actors, "Q", reserved),
          "Actor binding refuses before considering a reserved request or cached retry.");
    auto missing_client = original_wire;
    missing_client.erase("client");
    check(!admission::bind_actor(actors, "P", missing_client) &&
            !admission::bind_actor(actors, "not-in-roster", original_wire),
          "A missing client cannot inherit a bound actor from saved history.");
    auto malformed_request = fresh_wire;
    malformed_request.at("request") = Value(Value::Integer{7});
    const auto malformed = examine("P", malformed_request);
    const auto* null_request = std::get_if<admission::Fresh>(&malformed);
    check(null_request && std::holds_alternative<std::nullptr_t>(
              field(null_request->normalized, "request").storage()) &&
            !factory::values::typed_difference(field(null_request->normalized, "wire"),
                Value(malformed_request)),
          "A mistyped request remains intact in the wire for World's identity refusal.");
}
}  // namespace

int main() {
    try {
        actor_and_retry_admission();
        std::cout << "HOST_COMMAND_ADMISSION_PASS " << checks << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Host command admission test failed: " << error.what() << '\n';
        return 1;
    }
}
