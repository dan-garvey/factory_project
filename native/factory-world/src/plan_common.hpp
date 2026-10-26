#pragma once

#include "factory/world.hpp"

#include <string>
#include <variant>

namespace factory::world {

template<class T> const T* field(const authority::Object& object, const char* name) {
    const auto found = object.find(name);
    return found == object.end() ? nullptr : std::get_if<T>(&found->second.storage());
}

[[nodiscard]] values::Value point_value(const authority::Point& point);
[[nodiscard]] authority::Object reach_facts(const Binding&, const authority::ReachReceipt&);
[[nodiscard]] Owner::Decision refused(std::string reason, std::string entity = {},
                                      authority::Object facts = {});
[[nodiscard]] Owner::Decision accepted(State state, std::string entity,
                                       authority::Object facts);

} // namespace factory::world
