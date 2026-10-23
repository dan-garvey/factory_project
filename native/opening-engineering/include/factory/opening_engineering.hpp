#pragma once

#include "factory/godot_world.hpp"

#include <array>
#include <string_view>

namespace factory::opening_engineering {
using Count = values::Value::Integer;

struct Definition {
    std::string_view title, brief, relocate_hint, gear_hint;
    std::array<Count, 2> wheel_cell;
    Count first_target, target;
};

enum class Phase { unavailable, first_shift, move_source, restore_drive, deliver_more, ready };

struct Progress {
    Phase phase{Phase::unavailable};
    Count products{}, placed_gears{}, placed_shafts{};
    bool source_at_target{}, machines_running{};
    bool belt_forward{};
};

[[nodiscard]] const Definition& definition() noexcept;
[[nodiscard]] const char* phase_name(Phase) noexcept;

// Optional post-first-shift content using the real opening Host and unchanged
// finite kit. Read only its current native projection; never own a second World,
// quantity store, progress flag or clock. The actor comes from the existing
// session binding. This is present eligibility, not confirmation or persistence.
// Scene mounting and readable physical explanation remain integration work.
[[nodiscard]] Progress inspect(const godot_world::Host&, const std::string& actor);
// The extension may reuse the same trusted Host projection it is returning to
// Godot. This input must come from Host, never from a client observation.
[[nodiscard]] Progress inspect(const values::Value& current_projection, const std::string& actor);

// Formatting only: the input report must come from trusted native inspection,
// never a client command. The wrapper obtains or already holds that report.
// Publish this at the existing extension/Session boundary; Host::projection()
// remains unchanged. This does not install an engine binding or scene mount.
[[nodiscard]] values::Value format_progress(const Progress&, const std::string& actor);
[[nodiscard]] values::Value projection(const godot_world::Host&, const std::string& actor);
[[nodiscard]] values::Value projection(const values::Value& current_projection, const std::string& actor);
}  // namespace factory::opening_engineering
