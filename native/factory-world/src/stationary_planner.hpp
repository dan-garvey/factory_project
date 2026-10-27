#pragma once

#include "plan_common.hpp"

#include <optional>
#include <string>

namespace factory::world {

struct StationaryCommand {
    enum class Action {
        place, place_connected, remove, set_drive, collect, recover,
        insert_raw, insert_work, shaft_between, remove_shaft_between,
    };
    Action action{Action::place};
    std::optional<std::string> target;
    std::optional<authority::Integer> generation;
    std::optional<std::string> to;
    std::optional<authority::Integer> to_generation;
    std::optional<std::string> role_name;
    std::optional<std::string> axis_name;
    std::optional<std::string> relay_axis_name;
    std::optional<mechanics::Point> center;
    std::optional<authority::Integer> teeth;
    std::optional<authority::Integer> half_span;
    std::optional<authority::Integer> wheel_tiles;
    std::optional<authority::Integer> rotation;
    std::optional<authority::Integer> amount;
    std::optional<authority::Integer> work_id;
    std::optional<bool> enabled;
    bool has_rotation{};
    bool has_wheel_tiles{};
    bool has_relay_axis{};
};

// World checks command shape and actor gates before this planner proposes a
// candidate. World alone validates and commits the transaction.
[[nodiscard]] std::optional<StationaryCommand> stationary_command(
    const std::string& action, const authority::Object& intent);
[[nodiscard]] Owner::Decision plan_stationary(const Profile&, const Binding&,
    const Snapshot&, const StationaryCommand&, const ObserveActor&);

} // namespace factory::world
