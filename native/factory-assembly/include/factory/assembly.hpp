#pragma once

#include "factory/materials.hpp"
#include "factory/mechanics.hpp"

#include <optional>
#include <string>
#include <vector>

namespace factory::assembly {

// A read-only projection of World's placed-component records. This package
// owns neither item custody nor a second mutable machine state.
struct Part {
    std::string id;
    materials::Component kind{};
    mechanics::Point center{};
    mechanics::Integer generation{};
    bool operator==(const Part&) const = default;
};

// Supplied by trusted geology/site geometry. toward_ore is one horizontal
// quarter-grid step; machine_center is an ordinary four-step workcell center.
struct OreFace {
    mechanics::Point machine_center{};
    mechanics::Point toward_ore{};
    bool operator==(const OreFace&) const = default;
};

struct Collector {
    std::string frame;
    std::string mount;
    std::string edge;
    std::string receiver;
    std::string shaft;
    mechanics::Point machine_center{};
    mechanics::Point toward_ore{};
    mechanics::Point receiver_center{};
    mechanics::Point shaft_center{};
    mechanics::Integer cutting_height{}; // 0 or 1 quarter-grid step above frame.
    materials::Component shaft_material{};
    bool operator==(const Collector&) const = default;
};

enum class Status {
    ready,
    invalid_input,
    missing_frame,
    missing_mount,
    missing_edge,
    missing_receiver,
    missing_shaft,
    ambiguous,
};

struct Inspection {
    Status status{Status::invalid_input};
    std::optional<Collector> collector;
};

// Derive a single unambiguous collector arrangement. A receiver may sit on
// either side of the frame; the shaft may enter opposite the cutter or from
// the unused side. The head may sit at frame height or one height step above.
// Extra placed items remain ordinary world items and do not act as recipe
// tokens. Ambiguous complete arrangements require an explicit later selection.
[[nodiscard]] Inspection inspect_collector(const std::vector<Part>& placed,
                                           const OreFace& face);

}  // namespace factory::assembly
