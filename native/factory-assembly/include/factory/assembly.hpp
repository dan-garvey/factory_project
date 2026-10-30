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

// A small slide keeps its integral shaft at its own height, whether it stands
// alone on a U floor or fits at the half-U socket above a head. Transmission
// parts can meet that shaft on every quarter-U height layer.
[[nodiscard]] constexpr std::optional<mechanics::Point> small_slide_external_node(
        const mechanics::Point& slide, mechanics::Integer side) noexcept {
    if ((side != -1 && side != 1) || slide[0] % 4 || slide[2] % 4 ||
        slide[0] < -mechanics::maximum_coordinate + 4 ||
        slide[0] > mechanics::maximum_coordinate - 4) return std::nullopt;
    const auto phase = slide[1] % 4;
    if (phase == 0 || phase == 2 || phase == -2)
        return mechanics::Point{slide[0] + side * 4,
            slide[1], slide[2]};
    return std::nullopt;
}

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
    std::string shaft; // The mount's embodied spindle identity.
    mechanics::Point machine_center{};
    mechanics::Point toward_ore{};
    mechanics::Point receiver_center{};
    mechanics::Point shaft_center{}; // Input port at the placed mount.
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
    ambiguous,
};

struct Inspection {
    Status status{Status::invalid_input};
    std::optional<Collector> collector;
};

// Derive a single unambiguous collector arrangement. A receiver may sit on
// either side of the frame and the head may sit at frame height or one step
// above. The driven mount embodies its input shaft; independent shafts route
// power but are not required for readiness. Two receiver routes are ambiguous.
[[nodiscard]] Inspection inspect_collector(const std::vector<Part>& placed,
                                           const OreFace& face);

// One open lower feed face and its opposite exit. These are candidate routes,
// not a selected recipe or a second mutable input/output buffer.
struct PressFeed {
    mechanics::Point entry{};
    mechanics::Point exit{};
    bool operator==(const PressFeed&) const = default;
};

enum class PressStatus {
    ready,
    invalid_input,
    missing_anvil,
    missing_flat_head,
    missing_slide,
    blocked_feed,
};

// The anvil supports one blank; the separate die rides one quarter-grid step
// beneath the slide's integral input. The slide, not the anvil, owns motion.
struct SlidingPress {
    std::string anvil;
    std::string head;
    std::string slide;
    mechanics::Point work_center{};
    mechanics::Point slide_center{};
    materials::Component slide_material{};
    std::vector<PressFeed> open_feeds;
    bool operator==(const SlidingPress&) const = default;
};

struct SlidingPressInspection {
    PressStatus status{PressStatus::invalid_input};
    std::optional<SlidingPress> press;
};

[[nodiscard]] SlidingPressInspection inspect_sliding_press(
    const std::vector<Part>& placed, const mechanics::Point& anvil_center);

// One 2x2 workbed and one matching face use four ordinary parts each while a
// single reusable slide supplies the stroke. The lower-left workcell remains
// the material-custody origin for the whole twelve-mass sheet.
struct BroadSlidingPress {
    std::string anvil;
    std::string head;
    std::string slide;
    mechanics::Point origin{};
    mechanics::Point slide_center{};
    materials::Component slide_material{};
    std::array<mechanics::Point, 4> work_centers{};
    bool operator==(const BroadSlidingPress&) const = default;
};

struct BroadSlidingPressInspection {
    PressStatus status{PressStatus::invalid_input};
    std::optional<BroadSlidingPress> press;
};

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
    [[nodiscard]] bool has_component(const mechanics::Point& center,
                                     materials::Component kind) const;
    [[nodiscard]] Inspection inspect_collector(const OreFace& face) const;
    [[nodiscard]] SlidingPressInspection inspect_sliding_press(
        const mechanics::Point& anvil_center) const;
    [[nodiscard]] BroadSlidingPressInspection inspect_broad_sliding_press(
        const mechanics::Point& origin) const;


private:
    std::map<mechanics::Point, const Part*> by_center_;
    bool valid_{};
};

}  // namespace factory::assembly
