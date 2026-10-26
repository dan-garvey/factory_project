#pragma once

#include "plan_common.hpp"

#include <optional>
#include <string>

namespace factory::world {

struct FabricationCommand {
    enum class Kind { field_component, foundation, component, part };
    Kind kind{};
    std::string target;
    authority::Integer generation{};
    std::string recipe_name;
    authority::Integer half_span{};
};

// World admits shape, progression and pending-actor rules before this planner.
// The owner alone commits the proposed candidate and records retry/history.
[[nodiscard]] std::optional<FabricationCommand> fabrication_command(
    const std::string& action, const authority::Object& intent);
[[nodiscard]] Owner::Decision plan_fabrication(const Profile&, const Binding&,
    const Snapshot&, const FabricationCommand&, const ObserveActor&);

} // namespace factory::world
