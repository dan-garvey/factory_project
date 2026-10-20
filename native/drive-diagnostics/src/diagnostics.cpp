#include "factory/drive_diagnostics.hpp"

#include <algorithm>
#include <optional>
#include <set>
#include <utility>

namespace factory::drive_diagnostics {
namespace g = mechanics;
namespace {
struct Solo {
    std::string source;
    g::Result result;
};
Witness explain(const g::Component& component, const std::vector<g::Part>& parts, const std::vector<g::Drive>& sources) {
    Witness witness;
    witness.component = component.parts;
    const std::set<std::string> members(component.parts.begin(), component.parts.end());
    std::vector<g::Part> local;
    for (const auto& part : parts) if (members.contains(part.id)) local.push_back(part);
    std::vector<g::Drive> drives;
    for (const auto& source : sources) if (members.contains(source.hub)) drives.push_back(source);
    std::sort(drives.begin(), drives.end(), [](const auto& left, const auto& right) { return left.hub < right.hub; });
    std::vector<Solo> prior;
    std::optional<Witness> limit;
    for (const auto& drive : drives) {
        auto alone = g::evaluate(local, {drive});
        if (!alone.accepted()) {
            if (!limit) {
                auto failed = witness;
                failed.kind = Kind::counterfactual_limit;
                failed.source = drive.hub;
                failed.counterfactual_error = alone.error;
                limit = std::move(failed);
            }
            continue;
        }
        if (std::any_of(alone.components.begin(), alone.components.end(),
                [](const auto& entry) { return entry.state == g::MotionState::stalled; })) {
            witness.kind = Kind::single_source_stall;
            witness.source = drive.hub;
            return witness;
        }
        for (const auto& previous : prior) {
            const auto first = previous.result.motion.at(drive.hub).rate;
            const auto second = alone.motion.at(drive.hub).rate;
            if (first == second) continue;
            witness.kind = Kind::incompatible_sources;
            witness.source = previous.source;
            witness.other_source = drive.hub;
            witness.hub = drive.hub;
            witness.first_rate = first;
            witness.second_rate = second;
            return witness;
        }
        prior.push_back({drive.hub, std::move(alone)});
    }
    return limit ? std::move(*limit) : witness;
}
}  // namespace

Report inspect(const std::vector<g::Part>& parts, const std::vector<g::Drive>& sources) {
    Report report{g::evaluate(parts, sources), {}};
    if (!report.current.accepted()) return report;
    for (const auto& component : report.current.components)
        if (component.state == g::MotionState::stalled) report.witnesses.push_back(explain(component, parts, sources));
    return report;
}
}  // namespace factory::drive_diagnostics
