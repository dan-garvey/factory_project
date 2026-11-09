#pragma once

#include "factory/world.hpp"

namespace factory::world::surface_drill {
// The mount's anchor is its floor. The reusable head attaches one H above it;
// its embodied vertical spindle uses the same ports as any shaft.
[[nodiscard]] bool fitting(materials::Component, const mechanics::Point&,
    materials::Component, const mechanics::Point&) noexcept;
[[nodiscard]] bool supported(const State&, const mechanics::Point& head);
// A mount reserves a centered 3U square through its structure, even though its
// open legs occupy much less. Only the centered tool is an intentional fitting.
[[nodiscard]] bool reserved(const mechanics::Point& mount, const mechanics::Point& center,
    mechanics::Integer half_width = 2, mechanics::Integer half_height = 2) noexcept;
[[nodiscard]] const char* placement_refusal(const State&, materials::Component,
    const mechanics::Point&, const std::string& ignored = {});
[[nodiscard]] bool valid(const State&);
struct Contact {
    excavation::Contact cut;
    materials::DropPoint output;
};
[[nodiscard]] std::optional<Contact> contact(const Profile&, const State&,
    const mechanics::Point& head);
// One source of tick work, shared by a paid hand crank and automatic power.
// Returns false on an invalid transaction; ordinary lost contact merely stops.
[[nodiscard]] bool advance(const Profile&, State&, const DrivePower&);
} // namespace factory::world::surface_drill
