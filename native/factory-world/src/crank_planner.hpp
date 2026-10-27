#pragma once

#include "factory/crank_command_contract.hpp"
#include "plan_common.hpp"

#include <optional>
#include <string>

namespace factory::world {

struct CrankCommand {
    crank_commands::Action action{crank_commands::Action::none};
    std::optional<std::string> target;
    std::optional<authority::Integer> generation;
    std::optional<std::string> crank;
    std::optional<authority::Integer> crank_generation;
    std::optional<values::Value::Array> port;
    std::optional<values::Value::Array> face;
};

// World checks wire shape and actor gates before this planner proposes a
// candidate. World alone validates and commits the transaction.
[[nodiscard]] std::optional<CrankCommand> crank_command(
    const std::string& action, const authority::Object& intent);
[[nodiscard]] Owner::Decision plan_crank(const Profile&, const Binding&,
    const Snapshot&, const CrankCommand&, const ObserveActor&);

} // namespace factory::world
