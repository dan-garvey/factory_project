#pragma once

#include "factory/materials.hpp"

#include <array>
#include <cstdint>

namespace factory::indexing {
enum class Axis : std::uint8_t { x, y, z };
enum class Face : std::uint8_t { positive_x, negative_x, positive_y, negative_y, positive_z, negative_z };
using FaceMask = std::uint8_t;
inline constexpr FaceMask all_faces = 0x3f;

// Images of the local positive x/y/z axes in world space. Only the 24 proper
// indexed cube orientations are representable; this is not a physics pose or
// an interpolation rule. Imported reflections/duplicate axes are refused.
struct Orientation {
    std::array<Face, 3> positive_axes{{Face::positive_x, Face::positive_y, Face::positive_z}};
    bool operator==(const Orientation&) const = default;
};

// Optional future per-work metadata, not another item owner. The caller owns
// the original work identity and immutable required face mask. Bits follow Face.
struct Job {
    materials::WorkId id{};
    Orientation orientation;
    FaceMask required{};
    FaceMask marked{};
    bool operator==(const Job&) const = default;
};

enum class Error {
    none, invalid_orientation, invalid_axis, invalid_direction, invalid_face,
    invalid_job, unrequested_face, already_marked, unfinished, not_home,
};

[[nodiscard]] const char* face_name(Face) noexcept;
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] const char* explanation(Error) noexcept;
[[nodiscard]] Error validate(const Orientation&) noexcept;
[[nodiscard]] Error validate(const Job&) noexcept;

// Signed right-hand quarter turn around a WORLD axis; direction is +1 or -1.
// All output values remain unchanged on refusal.
[[nodiscard]] Error rotate(const Orientation&, Axis, int direction, Orientation&) noexcept;
[[nodiscard]] Error world_face(const Orientation&, Face local, Face& output) noexcept;
[[nodiscard]] Error local_face(const Orientation&, Face world, Face& output) noexcept;

// Read-only metadata proposals. World must own actual motion/contact, power,
// obstruction, request replay, quantities and the single atomic live commit.
// A plan never allocates work, changes recipe requirements or clears marks.
[[nodiscard]] Error plan_turn(const Job&, Axis, int direction, Job&) noexcept;
[[nodiscard]] Error plan_stamp(const Job&, Face world_contact_normal, Job&) noexcept;
// Home is an immutable holder/profile fact supplied by the caller. Identity is
// the revisable default used by these original puzzles, not a global game rule.
[[nodiscard]] Error release_ready(const Job&, const Orientation& home = {}) noexcept;
}  // namespace factory::indexing
