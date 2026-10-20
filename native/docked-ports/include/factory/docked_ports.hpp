#pragma once

#include "factory/mechanics.hpp"
#include "factory/recovery.hpp"

#include <cstdint>
#include <optional>
#include <variant>

namespace factory::docked_ports {
using Tick = std::uint64_t;

struct Reference {
    materials::EntityRef entity;
    std::uint32_t port{};
    bool operator==(const Reference&) const = default;
};

enum class Mode : std::uint8_t { fixed, dwell, moving };

struct Port {
    Reference reference;
    mechanics::Point anchor{};
    mechanics::Axis normal_axis{mechanics::Axis::x};
    int normal_sign{1};
    Mode mode{Mode::fixed};
    // Canonical form: fixed/moving use zero; dwell has a positive known window.
    Tick remaining{};
    bool gate_open{};
};

struct Observation {
    bool powered{};
    bool source_ready{};
    bool receiver_room{};
    Tick stroke_ticks{};
};

enum class Error { invalid_request, invalid_reference, invalid_geometry, invalid_phase, identity_conflict, same_port };
enum class Stop { unpowered, moving, misaligned, wrong_facing, closed_gate, short_dwell, empty_source, full_receiver };

struct Hold {
    Stop reason;
    Reference sender, receiver;
    bool operator==(const Hold&) const = default;
};

struct Stroke {
    Reference sender, receiver;
    Tick duration{};
    // No finite deadline is asserted when both ports are fixed.
    std::optional<Tick> available{};
    bool operator==(const Stroke&) const = default;
};

using Plan = std::variant<Error, Hold, Stroke>;
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] const char* stop_name(Stop) noexcept;

// Optional stop-and-dock profile for an indexed stationary cell. A zero-velocity
// instant during a moving phase is not a finite dwell. This does not replace the
// separate in-motion transfer experiment or impose docking on all game transport.
//
// Input identities, indexed poses, phase windows and stock flags must be current
// trusted World observations. This query does no body lookup, contact sensing,
// command admission, clock advance, allocation of work or material movement.
// Returned references are owned values, not admission/replay receipts. World must
// bind/revalidate producers and generations, enforce the whole stroke window and
// atomically commit actual typed cargo once; interruption retains its original
// owner/work identity. Repeated planning never reserves or consumes anything.
[[nodiscard]] Plan prepare(const Port& sender, const Port& receiver, const Observation&);
}  // namespace factory::docked_ports
