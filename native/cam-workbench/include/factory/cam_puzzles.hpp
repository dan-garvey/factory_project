#pragma once

#include "factory/cycle.hpp"

#include <array>
#include <span>
#include <string_view>

namespace factory::cam_puzzles {
using mechanisms::Tooth;

struct Keys {
    Tooth feed{};
    Tooth ram{};
    Tooth offset{};  // Delay of the second workstation on the common shaft.
    bool operator==(const Keys&) const = default;
};

// Original revisable fixtures from the chapter dwell sketches and the local
// opus-magnum-05 research candidate. These check timing, not item production.
struct Challenge {
    std::string_view id;
    std::string_view title;
    std::string_view goal;
    mechanisms::Slide slide;
    mechanisms::Cam unload;
    Tooth feed_width{};
    Tooth ram_width{};
    bool paired{};
    Keys initial;
};

struct Lane {
    mechanisms::Phase phase;
    mechanisms::Pose carriage;
    bool unloading{};
    bool feeding{};
    bool pressing{};
    bool operator==(const Lane&) const = default;
};

struct Frame {
    std::array<Lane, 2> lanes;
    unsigned lane_count{};
    bool operator==(const Frame&) const = default;
};

enum class Error { none, unknown_challenge, invalid_key, invalid_phase, invalid_fixture };
enum class Fault { none, unload_offsite, feed_offsite, ram_offsite, dock_overlap, drive_overload };

struct Report {
    Error error{Error::none};
    Fault fault{Fault::none};
    Tooth tooth{};  // First conflicting interval on the common cycle shaft.
    unsigned lane{};  // One-based; zero denotes the shared drive.
    [[nodiscard]] bool solved() const noexcept { return error == Error::none && fault == Fault::none; }
};

[[nodiscard]] std::span<const Challenge> catalogue() noexcept;
[[nodiscard]] const Challenge* find(std::string_view id) noexcept;
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] const char* explanation(Fault) noexcept;

// Read-only projections. Invalid input leaves output unchanged. Unsafe but
// well-formed arrangements remain inspectable, so their failure is visible.
[[nodiscard]] Error snapshot(std::string_view id, Keys, mechanisms::Phase, Frame&) noexcept;
[[nodiscard]] Report inspect(std::string_view id, Keys) noexcept;
}  // namespace factory::cam_puzzles
