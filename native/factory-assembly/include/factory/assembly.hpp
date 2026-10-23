#pragma once

#include "factory/materials.hpp"
#include "factory/mechanics.hpp"

#include <array>
#include <map>
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

// One open lower feed face and its opposite exit. These are candidate routes,
// not a selected recipe or a second mutable input/output buffer.
struct PressFeed {
    mechanics::Point entry{};
    mechanics::Point exit{};
    bool operator==(const PressFeed&) const = default;
};

struct Press {
    std::string frame;
    std::string anvil;
    std::string ram;
    std::string guide;
    std::string mount;
    std::string shaft;
    std::string drive_cog;
    mechanics::Point frame_center{};
    mechanics::Point work_center{};
    mechanics::Point shaft_center{};
    mechanics::Point cog_center{};
    materials::Component shaft_material{};
    materials::Component cog_material{};
    std::vector<PressFeed> open_feeds;
    bool operator==(const Press&) const = default;
};

enum class PressStatus {
    ready,
    invalid_input,
    missing_frame,
    missing_anvil,
    missing_ram,
    missing_guide,
    missing_mount,
    missing_shaft,
    missing_cog,
    blocked_stroke,
    blocked_feed,
    ambiguous,
};

struct PressInspection {
    PressStatus status{PressStatus::invalid_input};
    std::optional<Press> press;
};

// A guided press head is located by its placed anvil. The guide constrains the
// ram stroke; no frame or structural mount is part of this working geometry.
struct GuidedPress {
    std::string anvil;
    std::string ram;
    std::string guide;
    std::string shaft;
    std::string drive_cog;
    mechanics::Point work_center{};
    mechanics::Point shaft_center{};
    mechanics::Point cog_center{};
    materials::Component shaft_material{};
    materials::Component cog_material{};
    std::vector<PressFeed> open_feeds;
    bool operator==(const GuidedPress&) const = default;
};

struct GuidedPressInspection {
    PressStatus status{PressStatus::invalid_input};
    std::optional<GuidedPress> press;
};

[[nodiscard]] GuidedPressInspection inspect_guided_press(
    const std::vector<Part>& placed, const mechanics::Point& anvil_center);

// A four-cell work face is one broad stroke, not four separate 1x1 presses.
// Cells are ordered by z row, then x column, from the lowest x/z anvil.
// Each separate ram has an exterior shaft/cog pair. Readiness here covers
// placed geometry; World must still verify common signed motion, workpiece
// support and custody before forming one broad sheet.
struct BroadPress {
    mechanics::Point origin{};
    std::array<mechanics::Point, 4> work_centers{};
    std::array<std::string, 4> anvils{};
    std::array<std::string, 4> rams{};
    std::array<std::string, 4> guides{};
    std::array<std::string, 4> shafts{};
    std::array<std::string, 4> drive_cogs{};
    std::array<mechanics::Point, 4> shaft_centers{};
    std::array<mechanics::Point, 4> cog_centers{};
    std::array<materials::Component, 4> shaft_materials{};
    std::array<materials::Component, 4> cog_materials{};
    bool operator==(const BroadPress&) const = default;
};

enum class BroadPressStatus {
    ready, invalid_input, missing_anvil, missing_ram, missing_guide,
    blocked_stroke, missing_shaft, missing_cog, ambiguous,
};

struct BroadPressInspection {
    BroadPressStatus status{BroadPressStatus::invalid_input};
    std::optional<BroadPress> press;
};

[[nodiscard]] BroadPressInspection inspect_broad_press(
    const std::vector<Part>& placed, const mechanics::Point& lowest_anvil_center);

// Recognize a press at any common-grid frame center. Anvil, ram, guide and
// mount stack at distinct quarter-grid heights; a shaft and cog approach from
// one horizontal side. Both opposed lower feed paths are inspected for actual
// placed-part clearance. Work, power and item custody are separate authority.
[[nodiscard]] PressInspection inspect_press(const std::vector<Part>& placed,
                                            const mechanics::Point& frame_center);

// Validate/index one caller-owned immutable component snapshot. The vector
// must outlive the layout. World can inspect many collector faces and press
// frames against the same cut without rebuilding the map for each machine.
class Layout final {
public:
    explicit Layout(const std::vector<Part>& placed);
    Layout(std::vector<Part>&&) = delete;
    Layout(const Layout&) = delete;
    Layout& operator=(const Layout&) = delete;
    Layout(Layout&&) = delete;
    Layout& operator=(Layout&&) = delete;

    [[nodiscard]] bool valid() const noexcept { return valid_; }
    [[nodiscard]] Inspection inspect_collector(const OreFace& face) const;
    [[nodiscard]] PressInspection inspect_press(const mechanics::Point& frame_center) const;
    [[nodiscard]] GuidedPressInspection inspect_guided_press(
        const mechanics::Point& anvil_center) const;
    [[nodiscard]] BroadPressInspection inspect_broad_press(
        const mechanics::Point& lowest_anvil_center) const;

private:
    std::map<mechanics::Point, const Part*> by_center_;
    bool valid_{};
};

}  // namespace factory::assembly
