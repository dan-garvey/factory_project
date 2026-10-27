#include "checkpoint_envelope.hpp"

#include "factory/checkpoint.hpp"

#include <utility>

namespace factory::godot_world::checkpoint_envelope {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;

template<class T> const T* field(const Object& object, const char* name) {
    const auto found = object.find(name);
    return found == object.end() ? nullptr : std::get_if<T>(&found->second.storage());
}
}  // namespace

std::optional<Value> encode(const world::Profile& profile, const world::Snapshot& snapshot,
    const std::map<std::string, authority::Point>& actor_positions,
    const std::map<std::string, std::size_t>& support_routes) {
    auto encoded = world::encode_checkpoint(profile, snapshot);
    if (!std::holds_alternative<Value>(encoded)) return std::nullopt;
    Object actors;
    for (const auto& [actor, position] : actor_positions)
        actors.emplace(actor, Value(Array{Value(position[0]), Value(position[1]), Value(position[2])}));
    Object routes;
    for (const auto& [id, route] : support_routes)
        routes.emplace(id, Value(static_cast<Integer>(route)));
    return Value(Object{{"schema", Value(Integer{4})}, {"format", Value("factory-native-physical")},
        {"world", std::move(std::get<Value>(encoded))}, {"actors", Value(std::move(actors))},
        {"support_routes", Value(std::move(routes))}});
}

ParseResult parse(const Value& input) {
    const auto* root = std::get_if<Object>(&input.storage());
    const auto* schema = root ? field<Integer>(*root, "schema") : nullptr;
    if (!root || !schema || (*schema != 3 && *schema != 4) ||
        root->size() != (*schema == 4 ? 5u : 4u) ||
        !field<std::string>(*root, "format") ||
        *field<std::string>(*root, "format") != "factory-native-physical" ||
        !root->contains("world") || !field<Object>(*root, "actors")) return "invalid_checkpoint";

    Parsed parsed;
    parsed.schema = *schema;
    parsed.world = &root->at("world");
    parsed.actors = field<Object>(*root, "actors");
    if (*schema == 4) {
        const auto* routes = field<Object>(*root, "support_routes");
        if (!routes) return "invalid_checkpoint";
        for (const auto& [id, value] : *routes) {
            const auto* route = std::get_if<Integer>(&value.storage());
            if (!route || *route < 0) return "invalid_support_route";
            parsed.support_routes.emplace(id, static_cast<std::size_t>(*route));
        }
    }

    const auto* native = std::get_if<Object>(&parsed.world->storage());
    const auto* history = native ? field<Object>(*native, "history") : nullptr;
    parsed.context = history ? field<std::string>(*history, "context") : nullptr;
    if (!parsed.context) return "invalid_context";
    return parsed;
}

}  // namespace factory::godot_world::checkpoint_envelope
