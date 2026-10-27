#include "host_command_admission.hpp"

#include <utility>

namespace factory::godot_world::command_admission {
namespace {

const std::string* string_field(const Object& object, const char* name) {
    const auto found = object.find(name);
    return found == object.end() ? nullptr :
        std::get_if<std::string>(&found->second.storage());
}

}  // namespace

std::optional<BoundActor> bind_actor(const std::set<std::string>& actors,
        const std::string& bound_actor, const Object& wire) {
    const auto* client = string_field(wire, "client");
    if (!actors.contains(bound_actor) || !client || *client != bound_actor)
        return std::nullopt;
    return BoundActor{bound_actor, *client};
}

Decision examine(const BoundActor& bound, const authority::History& history,
        const Object& wire) {
    const auto* request = string_field(wire, "request");
    // Server-owned completion IDs cannot be occupied by a client request.
    if (request && request->starts_with("native-cut-"))
        return Refusal{"reserved_request"};
    // Original wire comparison precedes generation lookup or translation.
    // The only cache is World's existing history; no adapter map is created.
    if (request) for (const auto& record : history.records) {
        const auto* previous_client = string_field(record.intent, "client");
        const auto* previous_request = string_field(record.intent, "request");
        if (previous_client && *previous_client == bound.client && previous_request &&
                *previous_request == *request) {
            auto replay = record.intent;
            replay.insert_or_assign("wire", values::Value(wire));
            return Replay{std::move(replay)};
        }
    }
    return Fresh{Object{{"context", wire.contains("context") ? wire.at("context") : values::Value()},
        {"client", values::Value(bound.client)},
        {"request", request ? values::Value(*request) : values::Value()},
        {"actor", values::Value(bound.actor)},
        {"action", values::Value("adapter_refusal")}, {"wire", values::Value(wire)}}};
}

}  // namespace factory::godot_world::command_admission
