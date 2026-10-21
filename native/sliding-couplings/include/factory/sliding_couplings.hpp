#pragma once

#include "factory/mechanics.hpp"

#include <span>
#include <variant>

namespace factory::sliding_couplings {

struct Shift {
    std::string shaft;
    mechanics::Point destination;
};

enum class Error {
    invalid_scene, too_many_shifts, invalid_identity, duplicate_shift,
    unknown_shaft, not_a_shaft, off_axis, invalid_candidate,
};

struct Refusal {
    Error reason;
    mechanics::Error kernel_error{mechanics::Error::none};
    bool operator==(const Refusal&) const = default;
};

struct Prepared {
    std::vector<mechanics::Part> parts;
    mechanics::Result motion;
};

using Plan = std::variant<Refusal, Prepared>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Pure, atomic proposal to slide existing shafts along their own axes. Keep all
// identities, kinds, spans, gears and registered drives. The canonical native
// kernel validates the original and proposed layouts and derives every contact
// and rate. A stall is an accepted mechanical result, not a command refusal.
//
// These are instantaneous endpoint queries, not swept clearance, clutch tooth
// phase, load, inertia or synchronized engagement. The authority must separately
// admit, revalidate and commit the proposal; this component stores no live World,
// clock, material, requests or persistence. Refusals publish no partial candidate.
[[nodiscard]] Plan prepare(const std::vector<mechanics::Part>&,
                           const std::vector<mechanics::Drive>&,
                           std::span<const Shift>);
}  // namespace factory::sliding_couplings
