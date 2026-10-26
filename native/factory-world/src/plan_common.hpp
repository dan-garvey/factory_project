#pragma once

#include "factory/world.hpp"

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace factory::world {

inline constexpr std::size_t maximum_issued_entities = 4096;
inline constexpr std::string_view allocated_prefix = "native-part-";

template<class T> const T* field(const authority::Object& object, const char* name) {
    const auto found = object.find(name);
    return found == object.end() ? nullptr : std::get_if<T>(&found->second.storage());
}

[[nodiscard]] values::Value point_value(const authority::Point& point);
[[nodiscard]] bool add(authority::Integer& total, authority::Integer count);
[[nodiscard]] std::optional<stationary::Role> role(const std::string& value);
[[nodiscard]] const stationary::PlacedPart* part(const stationary::Topology&, const std::string& id);
[[nodiscard]] authority::Point anchor(const Profile&, const mechanics::Point&);
[[nodiscard]] values::Value removed_span_value(const stationary::PlacedBeltSpan&);
[[nodiscard]] values::Value lots_value(const std::vector<materials::WorkLot>&);
[[nodiscard]] bool copper_profile(const materials::Config&);
[[nodiscard]] values::Value belt_cargo_value(const materials::Cargo&, bool copper = false);
[[nodiscard]] authority::Object reach_facts(const Binding&, const authority::ReachReceipt&);
[[nodiscard]] Owner::Decision refused(std::string reason, std::string entity = {},
                                      authority::Object facts = {});
[[nodiscard]] Owner::Decision accepted(State state, std::string entity,
                                       authority::Object facts);

} // namespace factory::world
