#pragma once

#include "factory/geared_cycle.hpp"

#include <array>
#include <optional>
#include <span>

namespace factory::planetary {
using Fraction = mechanics::Rate;
enum class Port { sun, carrier, ring, planet };
struct Profile {
    mechanics::Integer sun{24}, planet{24}, ring{72};  // Same-pitch tooth counts.
    bool operator==(const Profile&) const = default;
};
struct Constraint {
    Port port;  // Only sun, carrier and ring are external prescribed ports.
    Fraction rate;
};
enum class Outcome { solved, stalled };
struct Evaluation {
    Outcome outcome;
    // Sun, carrier, ring, planet. ALL are absolute rates about the same axis;
    // planet is its axial spin, not spin relative to the moving carrier.
    std::array<mechanics::Motion, 4> motion;
    std::array<std::optional<Fraction>, 3> prescribed;
    bool operator==(const Evaluation&) const = default;
};
enum class Error { invalid_profile, too_many_constraints, invalid_port, duplicate_port, invalid_rate, underdetermined, unsupported_result };
struct Refusal {
    Error reason;
    Port subject{Port::carrier};
    std::optional<geared_cycle::Error> rate_error;
    bool operator==(const Refusal&) const = default;
};
using Result = std::variant<Refusal, Evaluation>;
[[nodiscard]] const char* port_name(Port) noexcept;
[[nodiscard]] const char* error_name(Error) noexcept;

// Ideal same-pitch coaxial sun/ONE-planet/internal-ring pattern. Validate tooth
// counts against existing native dimension bounds and R=S+2P before arithmetic.
// The two carrier-relative pitch meshes give (S+R)*c=S*s+R*r; the planet's
// absolute spin is c-(S/P)*(s-c). Two prescribed external rates determine all
// four; one source with two free ports is underdetermined, NOT a hidden brake.
// Explicit zero means locked. Incompatible triples propose a whole-component
// stall and retain normalized prescriptions, never a partial motion map.
//
// Reuse exact native clock rate limits as representation bounds, not physical
// speed targets. Refuse unsupported inferred external OR planet rates without
// rounding. No input/output phases, source registry, clock or live state exist.
//
// Tooth-count closure is NOT complete tooth engagement/admission: tooth phase,
// involute/internal interference, carrier/housing clearance and multiple-planet
// packing remain unmodeled. This predicts no torque, efficiency, loaded free
// port or strength. The authority owns actual topology, constraints, source
// stalls, atomic adoption, World, quantities and persistence.
[[nodiscard]] Result evaluate(const Profile&, std::span<const Constraint>);
}  // namespace factory::planetary
