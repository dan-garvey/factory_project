#pragma once

#include "factory/world.hpp"

#include <cstddef>
#include <map>
#include <optional>
#include <string>
#include <variant>

namespace factory::godot_world::checkpoint_envelope {

// The parsed fields point into the input value and remain valid while that
// value is alive. World and Host still validate the native state and site.
struct Parsed {
    values::Value::Integer schema{};
    const values::Value* world{};
    const values::Value::Object* actors{};
    const std::string* context{};
    std::map<std::string, std::size_t> support_routes;
};
using ParseResult = std::variant<Parsed, const char*>;

[[nodiscard]] std::optional<values::Value> encode(const world::Profile& profile,
    const world::Snapshot& snapshot,
    const std::map<std::string, authority::Point>& actors,
    const std::map<std::string, std::size_t>& support_routes);
[[nodiscard]] ParseResult parse(const values::Value& input);

}  // namespace factory::godot_world::checkpoint_envelope
