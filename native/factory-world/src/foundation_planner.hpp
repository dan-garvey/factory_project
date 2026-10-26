#pragma once

#include "plan_common.hpp"

#include <optional>
#include <string>
#include <vector>

namespace factory::world {

struct FoundationCommand {
    enum class Kind { place_area, place_one, remove_one };
    Kind kind{};
    std::vector<mechanics::Point> cells;
    std::optional<mechanics::Point> center;
    std::optional<std::string> target;
    std::optional<authority::Integer> generation;
};

// World checks the request shape and actor gates before this planner proposes
// a candidate. Only World validates and commits that candidate.
[[nodiscard]] std::optional<FoundationCommand> foundation_command(
    const std::string& action, const authority::Object& intent);
[[nodiscard]] Owner::Decision plan_foundation(const Profile&, const Binding&,
    const Snapshot&, const FoundationCommand&, const ObserveActor&);

} // namespace factory::world
