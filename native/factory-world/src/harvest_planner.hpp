#pragma once

#include "plan_common.hpp"

#include <optional>
#include <string>

namespace factory::world {

struct HarvestCommand {
    enum class Kind { start, fast, finish, cancel };
    Kind kind{};
    std::string target;
};

// World admits the common command shape and pending-actor rule before selecting
// this planner. Only the World owner commits the returned candidate.
[[nodiscard]] std::optional<HarvestCommand> harvest_command(
    const std::string& action, const authority::Object& intent);
[[nodiscard]] Owner::Decision plan_harvest(const Profile&, const Binding&,
    const Snapshot&, const HarvestCommand&, const ObserveActor&);

} // namespace factory::world
