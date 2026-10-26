#pragma once

#include "factory/belt_command_contract.hpp"
#include "plan_common.hpp"

#include <optional>
#include <string>

namespace factory::world {

struct BeltCommand {
    belt_commands::Action action{belt_commands::Action::none};
    std::string target;
    authority::Integer generation{};
    std::string to;
    authority::Integer to_generation{};
    std::string selection;
    authority::Integer slot{};
    authority::Object expected;
    std::string item;
    authority::Integer work_id{};
};

// World admits the common command shape and pending-actor rule before this
// typed planner proposes a candidate. World alone commits the decision.
[[nodiscard]] std::optional<BeltCommand> belt_command(
    const std::string& action, const authority::Object& intent);
[[nodiscard]] Owner::Decision plan_belt(const Profile&, const Binding&,
    const Snapshot&, const BeltCommand&, const ObserveActor&);

} // namespace factory::world
