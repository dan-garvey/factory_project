#pragma once

#include "factory/press_command_contract.hpp"
#include "plan_common.hpp"

#include <optional>
#include <string>

namespace factory::world {

struct PressCommand {
    press_commands::Action action{press_commands::Action::none};
    std::optional<std::string> target;
    std::optional<authority::Integer> generation;
    std::optional<authority::Integer> sheet_id;
    std::optional<authority::Integer> work_id;
    std::optional<std::string> drive;
    std::optional<values::Value::Array> entry;
    std::optional<values::Value::Array> exit;
};

// World checks the wire shape and actor gates before this planner proposes a
// candidate. World alone validates and commits the transaction.
[[nodiscard]] std::optional<PressCommand> press_command(
    const std::string& action, const authority::Object& intent);
[[nodiscard]] Owner::Decision plan_press(const Profile&, const Binding&,
    const Snapshot&, const PressCommand&, const ObserveActor&);

} // namespace factory::world
