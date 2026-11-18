#pragma once

#include "factory/world.hpp"

namespace factory::world::piston_assembly {
[[nodiscard]] std::optional<piston::Config> configuration(const State&, const std::string&);
[[nodiscard]] bool valid(const State&);
[[nodiscard]] bool socket_reach_target(const Profile&, const State&, const std::string& owner,
    const mechanics::Point& reference, const authority::Point& target);
[[nodiscard]] std::optional<mechanics::Part> spindle(const std::string&, const PlacedComponent&);
[[nodiscard]] authority::Point position(const Profile&, const State&, const PlacedComponent&);
[[nodiscard]] mechanics::Point displacement(const State&, const std::string& parent);
[[nodiscard]] const char* placement_refusal(const State&, const PlacedComponent&);
[[nodiscard]] const char* placement_refusal(const State&, const stationary::PlacedPart&);
[[nodiscard]] const char* reclaim_refusal(const State&, const stationary::PlacedPart&);
[[nodiscard]] const char* reclaim_refusal(const State&, const std::string&);
[[nodiscard]] bool advance(State&, const DrivePower&, const ObservePiston&);
// Contacts are evaluated inside each rigid frame. The only cross-frame power
// link is the piston's physical inner shaft; arbitrary edges are never accepted.
[[nodiscard]] mechanics::Result power(const State&, const std::vector<mechanics::Part>&,
    const std::vector<mechanics::Drive>&, const std::vector<mechanics::BeltSpan>&,
    const std::map<std::string,std::string>& owners);
} // namespace factory::world::piston_assembly
