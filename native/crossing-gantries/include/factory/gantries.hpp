#pragma once

#include "factory/clearance.hpp"
#include "factory/cycle.hpp"

#include <optional>
#include <span>
#include <string_view>

namespace factory::gantries {
enum class Puzzle { bridge, crossing, freight };

struct Track {
    mechanisms::Slide slide;
    clearance::Point dock, work;
};

struct Definition {
    Puzzle puzzle;
    std::string_view id, title, hint;
    Track first, second;
    bool phase_adjustable{};
    clearance::Coordinate maximum_height{2};
};

struct Settings {
    mechanisms::Tooth offset{};
    clearance::Coordinate height{};
    bool operator==(const Settings&) const = default;
};

enum class Error { none, invalid_puzzle, invalid_settings, invalid_geometry };

struct Conflict {
    mechanisms::Tooth interval{};
    clearance::Fraction contact;
    bool initially_overlapping{};
    bool operator==(const Conflict&) const = default;
};

struct Report {
    Error error{Error::none};
    mechanisms::Tooth period{};
    std::optional<Conflict> conflict;
    [[nodiscard]] bool clear() const noexcept { return error == Error::none && !conflict; }
    bool operator==(const Report&) const = default;
};

[[nodiscard]] std::span<const Definition> catalogue() noexcept;
[[nodiscard]] const Definition* find(std::string_view) noexcept;
[[nodiscard]] const char* error_name(Error) noexcept;

// A configuration query over immutable tracks and two 2x2x2 translation-only
// boxes. Height raises the second track; offset keys its fixed cycle. Evaluate
// the entire common period, including the last interval returning to its start.
// Strict interior overlap blocks; exact grazing follows the clearance policy.
// Both bodies move continuously and linearly within each prescribed interval.
// This owns no body, phase, work, quantity or clock. It is not actual collision,
// drivetrain response, startup placement/motion or World admission evidence.
[[nodiscard]] Report evaluate(Puzzle, Settings) noexcept;
}  // namespace factory::gantries
