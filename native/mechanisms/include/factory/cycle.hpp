#pragma once

#include <cstdint>

// Experimental stationary machinery. The caller owns phase, power, collision
// observations and admission. This component never ticks or stores a live world.
namespace factory::mechanisms {

using Tooth = std::uint64_t;

// One tooth is one fixed simulation step, not a wall-clock timer. A complete
// revolution is dock + travel + work + travel. Both endpoints have finite dwell.
struct Slide {
    Tooth dock{6};
    Tooth travel{4};
    Tooth work{6};
    bool operator==(const Slide&) const = default;
};

struct Phase {
    Tooth tooth{};
    bool operator==(const Phase&) const = default;
};

enum class Stage { dock, outward, work, homeward };

// Exact normalized displacement from dock toward work. No world units, float
// integration or repeated rounding are needed. Stage describes the NEXT interval:
// outward starts at displacement zero; homeward starts at full displacement.
struct Pose {
    Stage stage{Stage::dock};
    Tooth numerator{};
    Tooth denominator{1};
    bool operator==(const Pose&) const = default;
};

// An immutable lobe on the same cycle shaft. The active arc is [start, start +
// width), wrapping at the cycle boundary. Width zero disables a follower.
struct Cam {
    Tooth start{};
    Tooth width{};
    bool operator==(const Cam&) const = default;
};

enum class Error { none, invalid_slide, invalid_phase, invalid_cam, obstructed };

[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] const char* stage_name(Stage) noexcept;

// All read outputs and phase remain unchanged on refusal. A stopped shaft is a
// successful no-op after validation. Travel obstruction holds the whole cycle
// shaft only when the proposed step changes carriage position; dwell continues.
[[nodiscard]] Error cycle_length(const Slide&, Tooth& result) noexcept;
[[nodiscard]] Error sample(const Slide&, Phase, Pose& result) noexcept;
[[nodiscard]] Error cam_active(const Slide&, Phase, Cam, bool& result) noexcept;
[[nodiscard]] Error advance(const Slide&, Phase&, bool powered,
                            bool travel_obstructed = false) noexcept;

}  // namespace factory::mechanisms
