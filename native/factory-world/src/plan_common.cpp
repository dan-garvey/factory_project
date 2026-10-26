#include "plan_common.hpp"

#include <limits>
#include <utility>

namespace factory::world {

bool add(authority::Integer& total, authority::Integer count) {
    if (count < 0 || total > std::numeric_limits<authority::Integer>::max() - count)
        return false;
    total += count;
    return true;
}

std::optional<stationary::Role> role(const std::string& value) {
    using Role = stationary::Role;
    if (value == "collector") return Role::collector;
    if (value == "belt") return Role::belt;
    if (value == "processor") return Role::processor;
    if (value == "waterwheel") return Role::waterwheel;
    if (value == "gear") return Role::gear;
    if (value == "shaft") return Role::shaft;
    if (value == "gearbox") return Role::gearbox;
    if (value == "vertical_gearbox") return Role::vertical_gearbox;
    if (value == "chain_drive") return Role::chain_drive;
    return std::nullopt;
}

authority::Point anchor(const Profile& profile, const mechanics::Point& point) {
    return {static_cast<double>(point[0]) * profile.meters_per_grid_unit + profile.anchor_offset[0],
            static_cast<double>(point[1]) * profile.meters_per_grid_unit + profile.anchor_offset[1],
            static_cast<double>(point[2]) * profile.meters_per_grid_unit + profile.anchor_offset[2]};
}

values::Value point_value(const authority::Point& point) {
    using Value = values::Value;
    return Value(Value::Array{Value(point[0]), Value(point[1]), Value(point[2])});
}

authority::Object reach_facts(const Binding& binding, const authority::ReachReceipt& reach) {
    using Value = values::Value;
    Value::Array targets, distances;
    for (const auto& target : reach.targets) targets.push_back(point_value(target));
    for (const auto distance : reach.distances_squared) distances.emplace_back(distance);
    return {{"actor", Value(binding.actor)}, {"native_epoch", Value(reach.cut.native_epoch)},
        {"actor_position", point_value(reach.cut.position)}, {"targets", Value(std::move(targets))},
        {"distances_squared", Value(std::move(distances))}, {"build_reach", Value(reach.cut.build_reach)}};
}

Owner::Decision refused(std::string reason, std::string entity, authority::Object facts) {
    return {std::nullopt, {false, std::move(reason), std::move(entity), std::move(facts)}};
}

Owner::Decision accepted(State state, std::string entity, authority::Object facts) {
    return {std::move(state), {true, "ok", std::move(entity), std::move(facts)}};
}

} // namespace factory::world
