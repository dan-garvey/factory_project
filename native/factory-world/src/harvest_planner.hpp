#pragma once

#include "plan_common.hpp"
#include "factory/ore_column_target.hpp"

#include <optional>
#include <string>

namespace factory::world {

struct HarvestCommand {
    enum class Kind { start, fast, finish, cancel };
    Kind kind{};
    std::string target;
};

struct HarvestTarget {
    bool ore{};
    authority::Point reach_point{};
    std::optional<ore_columns::Target> column;
};
struct HarvestTargetResult {
    const char* reason{"none"};
    std::optional<HarvestTarget> target;
};
// Shared by command planning and ongoing native cut observation. The actor
// position must come from ObserveActor. No client position or receipt is read.
[[nodiscard]] HarvestTargetResult resolve_harvest_target(const Profile&, const State&,
    const std::string&, const authority::Point& actor_position);

// World admits the common command shape and pending-actor rule before selecting
// this planner. Only the World owner commits the returned candidate.
[[nodiscard]] std::optional<HarvestCommand> harvest_command(
    const std::string& action, const authority::Object& intent);
[[nodiscard]] Owner::Decision plan_harvest(const Profile&, const Binding&,
    const Snapshot&, const HarvestCommand&, const ObserveActor&);

} // namespace factory::world
