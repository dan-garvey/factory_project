#pragma once

#include "factory/component_command_contract.hpp"
#include "plan_common.hpp"

#include <optional>
#include <string>

namespace factory::world {

struct ComponentCommand {
    component_commands::Action action{component_commands::Action::none};
    std::optional<std::string> component_name;
    std::optional<mechanics::Point> center;
    std::optional<std::string> target;
    std::optional<authority::Integer> generation;
};

// World checks the wire shape and actor gates before this planner proposes a
// candidate. World alone validates and commits the transaction.
[[nodiscard]] std::optional<ComponentCommand> component_command(
    const std::string& action, const authority::Object& intent);
[[nodiscard]] Owner::Decision plan_component(const Profile&, const Binding&,
    const Snapshot&, const ComponentCommand&, const ObserveActor&);

} // namespace factory::world
