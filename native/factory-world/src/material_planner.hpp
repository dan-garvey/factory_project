#pragma once

#include "factory/material_command_contract.hpp"
#include "plan_common.hpp"

#include <optional>
#include <string>

namespace factory::world {

struct MaterialCommand {
    material_commands::Action action{material_commands::Action::none};
    std::optional<mechanics::Point> center;
    std::optional<mechanics::Point> from;
    std::optional<mechanics::Point> to;
    authority::Object expected;
    authority::Integer sheet_id{};
    std::string form;
};

// World checks the shared request shape and actor gates before this planner
// proposes a native candidate. World alone validates and commits the result.
[[nodiscard]] std::optional<MaterialCommand> material_command(
    const std::string& action, const authority::Object& intent);
[[nodiscard]] Owner::Decision plan_material(const Profile&, const Binding&,
    const Snapshot&, const MaterialCommand&, const ObserveActor&);

} // namespace factory::world
