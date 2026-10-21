#pragma once

#include "factory/geared_cycle.hpp"

#include <array>
#include <optional>
#include <span>

namespace factory::differential {
using Fraction = mechanics::Rate;
enum class Port { left, carrier, right };
struct Constraint {
    Port port;
    Fraction rate;
};
enum class Outcome { solved, stalled };
struct Evaluation {
    Outcome outcome;
    std::array<mechanics::Motion, 3> motion;  // Left, carrier, right.
    std::array<std::optional<Fraction>, 3> prescribed;
    bool operator==(const Evaluation&) const = default;
};
enum class Error { too_many_constraints, invalid_port, duplicate_port, invalid_rate, underdetermined, unsupported_result };
struct Refusal {
    Error reason;
    Port subject{Port::carrier};
    std::optional<geared_cycle::Error> rate_error;
    bool operator==(const Refusal&) const = default;
};
using Result = std::variant<Refusal, Evaluation>;
[[nodiscard]] const char* port_name(Port) noexcept;
[[nodiscard]] const char* error_name(Error) noexcept;

// Pure symmetric kinematic proposal: 2 * carrier = left + right, with every
// signed rate measured about the same reference axis. Carrier means the planet
// carrier itself, not a driveshaft with additional crown/pinion gearing.
// Two independent prescribed rates determine the third. Missing observations
// are free ports, NEVER zero-speed brakes. An explicit zero rate is a lock.
// Three incompatible prescriptions propose a whole-component stall, retaining
// the original normalized prescriptions for diagnosis. All inputs are checked
// before any solution; unsupported exact inferred rates refuse without rounding.
//
// Native clock rate bounds constrain this fixture's exact representation. This
// is not geometry-derived bevel contact or a torque/power/load model. It cannot
// predict an unrestrained port from one source. The authority owns topology,
// obstruction and source-stall propagation, constraints, atomic adoption, phase,
// World and persistence. No source, drive, clock or mutable state is created.
[[nodiscard]] Result evaluate(std::span<const Constraint>);
}  // namespace factory::differential
