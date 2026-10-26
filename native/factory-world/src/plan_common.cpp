#include "plan_common.hpp"

#include <utility>

namespace factory::world {

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
