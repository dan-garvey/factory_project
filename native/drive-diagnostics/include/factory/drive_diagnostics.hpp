#pragma once

#include "factory/mechanics.hpp"

namespace factory::drive_diagnostics {
enum class Kind { single_source_stall, incompatible_sources, counterfactual_limit, unresolved };
struct Witness {
    Kind kind{Kind::unresolved};
    std::vector<std::string> component;
    std::string source, other_source, hub;
    // For incompatible_sources only: the canonical solver's two rates at hub,
    // each computed with just the corresponding registered source present.
    mechanics::Rate first_rate{}, second_rate{};
    mechanics::Error counterfactual_error{mechanics::Error::none};
    bool operator==(const Witness&) const = default;
};
struct Report {
    mechanics::Result current;
    std::vector<Witness> witnesses;
};

// The existing solver validates before any input identity is copied. Each
// stalled component gets its first deterministic supported explanation, or an
// explicit limit/unresolved result. All witness data is owned by the report.
// Restricted-source evaluations are counterfactual queries, not applied repairs,
// minimal fault sets, contact simulation or another mutable mechanical owner.
[[nodiscard]] Report inspect(const std::vector<mechanics::Part>&, const std::vector<mechanics::Drive>&,
                             const std::vector<mechanics::BeltSpan>&,
                             mechanics::SourcePolicy = mechanics::SourcePolicy::prescribed);
}  // namespace factory::drive_diagnostics
