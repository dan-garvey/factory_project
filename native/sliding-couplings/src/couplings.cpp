#include "factory/sliding_couplings.hpp"

#include <algorithm>
#include <set>
#include <string_view>
#include <utility>

namespace factory::sliding_couplings {
const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_scene: return "invalid_scene";
        case Error::too_many_shifts: return "too_many_shifts";
        case Error::invalid_identity: return "invalid_identity";
        case Error::duplicate_shift: return "duplicate_shift";
        case Error::unknown_shaft: return "unknown_shaft";
        case Error::not_a_shaft: return "not_a_shaft";
        case Error::off_axis: return "off_axis";
        case Error::invalid_candidate: return "invalid_candidate";
    }
    return "unknown";
}

Plan prepare(const std::vector<mechanics::Part>& parts,
             const std::vector<mechanics::Drive>& sources,
             std::span<const Shift> shifts) {
    const auto original = mechanics::evaluate(parts, sources);
    if (!original.accepted()) return Refusal{Error::invalid_scene, original.error};
    if (shifts.size() > mechanics::maximum_parts) return Refusal{Error::too_many_shifts};
    std::set<std::string_view> seen;
    for (const auto& shift : shifts) {
        if (shift.shaft.empty() || shift.shaft.size() > 128 ||
            shift.shaft.find('\0') != std::string::npos)
            return Refusal{Error::invalid_identity};
        if (!seen.emplace(shift.shaft).second) return Refusal{Error::duplicate_shift};
        const auto found = std::find_if(parts.begin(), parts.end(),
            [&](const auto& part) { return part.id == shift.shaft; });
        if (found == parts.end()) return Refusal{Error::unknown_shaft};
        if (found->kind != mechanics::Kind::shaft) return Refusal{Error::not_a_shaft};
        const auto axial = static_cast<std::size_t>(found->axis);
        for (std::size_t axis = 0; axis < shift.destination.size(); ++axis)
            if (axis != axial && shift.destination[axis] != found->center[axis])
                return Refusal{Error::off_axis};
    }
    auto candidate = parts;
    for (const auto& shift : shifts)
        for (auto& part : candidate)
            if (part.id == shift.shaft) part.center = shift.destination;
    auto motion = mechanics::evaluate(candidate, sources);
    if (!motion.accepted()) return Refusal{Error::invalid_candidate, motion.error};
    return Prepared{std::move(candidate), std::move(motion)};
}
}  // namespace factory::sliding_couplings
