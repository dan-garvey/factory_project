#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <variant>

namespace factory::metering {
using Port = std::uint32_t;
using Capacity = std::int64_t;

// Bounded prototype representation, not permanent game-scale limits.
inline constexpr std::size_t maximum_ports = 32;
inline constexpr std::size_t maximum_pockets = 256;

struct Wheel {
    std::span<const Port> pattern;  // Physical receiver visits in stroke order.
    std::size_t ports{};
};

struct Phase {
    std::uint64_t pocket{};  // Next stroke; only the World may persist/commit it.
    bool operator==(const Phase&) const = default;
};

struct Observation {
    bool powered{};
    bool item_available{};
    std::span<const Capacity> free_slots;
};

enum class Error { none, invalid_wheel, invalid_phase, invalid_receivers, invalid_output };
enum class Stop { unpowered, empty_source, blocked_receiver };

struct Hold {
    Stop reason;
    Port destination;
    Phase phase;
    bool operator==(const Hold&) const = default;
};

struct Dispatch {
    Port destination;
    Phase next;
    bool operator==(const Dispatch&) const = default;
};

using Plan = std::variant<Error, Hold, Dispatch>;
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] const char* stop_name(Stop) noexcept;

// Read-only one-item handoff proposal. A full indexed port holds the wheel even
// if other receivers are free. Power loss and empty feed preserve the same index.
// Validate all observations before returning any hold/dispatch result.
//
// A future World adapter must resolve admission/replay, revalidate both holders,
// and atomically commit the actual one-item transfer AND Dispatch::next. This
// component stores no items, phase, requests, live clock, save or fallback world.
[[nodiscard]] Plan prepare(const Wheel&, Phase, const Observation&) noexcept;

// Count strokes per complete revolution. Refusal preserves every output field.
[[nodiscard]] Error histogram(const Wheel&, std::span<std::uint32_t>) noexcept;
}  // namespace factory::metering
