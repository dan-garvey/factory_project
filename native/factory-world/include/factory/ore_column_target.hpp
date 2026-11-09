#pragma once

#include "factory/authority_boundary.hpp"
#include "factory/ore_columns.hpp"

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace factory::world::ore_columns {
inline constexpr std::size_t maximum_contact_columns = 128;
inline constexpr std::size_t contact_fact_count = 8;

[[nodiscard]] std::string target_id(excavation::Cell);
[[nodiscard]] std::optional<excavation::Cell> target_cell(std::string_view) noexcept;

struct ContactColumn {
    excavation::Cell cell;
    materials::Quantity remaining{};
    bool operator==(const ContactColumn&) const = default;
};
struct Target {
    excavation::Contact cutting;
    excavation::Column before;
    double floor_before{};
    authority::Point reach_point{};
    // Only the columns intersected by this reach segment, its addressed cell,
    // and the selected side's exposure neighbour. No complete field snapshot.
    std::vector<ContactColumn> columns;
};
enum class TargetError { none, invalid_state, unknown_target, exhausted,
    invalid_actor, occluded, contact_too_complex };
struct TargetResult {
    TargetError error{TargetError::none};
    std::optional<Target> target;
};

// The live planner derives contact from canonical field plus native actor
// observation. Client intent provides only the exact cell ID. It cannot supply
// a surface position, a clearance witness or an alternate depleted column.
// The segment must stay outside solid ground represented by all known columns.
// Host still admits other terrain, structures and the actual actor observation.
[[nodiscard]] TargetResult resolve_target(const Seed&, const Field&,
    const materials::State&, std::string_view, const authority::Point& actor_position);
// A read-only projection resolves several candidates against one validated
// snapshot. The returned entries retain the same refusal/contact contract.
[[nodiscard]] std::vector<TargetResult> resolve_targets(const Seed&, const Field&,
    const materials::State&, const std::vector<std::string>&,
    const authority::Point& actor_position);
[[nodiscard]] authority::Object contact_facts(const Target&);

// Validates the local immutable geometry receipt against trusted seed facts.
// Witness remaining counts must be bounded; the witness set is exactly the
// columns needed by the segment/exposure test. This does not reconstruct ticks
// or prove those historical counts independently: World also checks monotonic
// bounds and total custody. Live commands never consume these saved witnesses.
[[nodiscard]] std::optional<Target> historical_contact(const Seed&, std::string_view,
    const authority::Point& actor_position, const authority::Object& facts);
[[nodiscard]] const char* target_error_name(TargetError) noexcept;
} // namespace factory::world::ore_columns
