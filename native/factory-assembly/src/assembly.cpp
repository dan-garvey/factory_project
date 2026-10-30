#include "factory/assembly.hpp"

#include <array>
#include <map>
#include <set>
#include <utility>

namespace factory::assembly {
namespace {

using Integer = mechanics::Integer;
using Point = mechanics::Point;

Point offset(Point center, const Point& horizontal, Integer steps, Integer height = 0) {
    for (std::size_t axis = 0; axis < center.size(); ++axis)
        center[axis] += horizontal[axis] * steps;
    center[1] += height;
    return center;
}

const Part* at(const std::map<Point, const Part*>& by_center, const Point& center,
               materials::Component kind) {
    const auto found = by_center.find(center);
    return found != by_center.end() && found->second->kind == kind ? found->second : nullptr;
}

bool valid_face(const OreFace& face) {
    const auto& center = face.machine_center;
    const auto& toward = face.toward_ore;
    if (center[0] % 4 || center[1] % 4 || center[2] % 4 || toward[1] != 0 ||
        (toward[0] == 0) == (toward[2] == 0) ||
        (toward[0] != 0 && toward[0] != 1 && toward[0] != -1 && toward[0] != 2 && toward[0] != -2) ||
        (toward[2] != 0 && toward[2] != 1 && toward[2] != -1 && toward[2] != 2 && toward[2] != -2)) return false;
    for (const auto coordinate : center)
        if (coordinate < -mechanics::maximum_coordinate + 3 ||
            coordinate > mechanics::maximum_coordinate - 3) return false;
    return true;
}

bool valid_part(const Part& part) {
    if (part.id.empty() || part.id.size() > 128 || part.id.find('\0') != std::string::npos ||
        part.generation <= 0 || !materials::component_cost(part.kind)) return false;
    for (const auto coordinate : part.center)
        if (coordinate < -mechanics::maximum_coordinate ||
            coordinate > mechanics::maximum_coordinate) return false;
    return true;
}

}  // namespace

Layout::Layout(const std::vector<Part>& placed) {
    if (placed.size() > 4096) return;
    std::set<std::string> ids;
    for (const auto& part : placed)
        if (!valid_part(part) || !ids.insert(part.id).second ||
            !by_center_.emplace(part.center, &part).second) {
            by_center_.clear();
            return;
        }
    valid_ = true;
}

bool Layout::has_component(const Point& center, materials::Component kind) const {
    return valid_ && at(by_center_, center, kind) != nullptr;
}

Inspection Layout::inspect_collector(const OreFace& face) const {
    if (!valid_ || !valid_face(face)) return {Status::invalid_input, std::nullopt};
    const auto& by_center = by_center_;

    const auto* frame = at(by_center, face.machine_center, materials::Component::wooden_frame);
    if (!frame) return {Status::missing_frame, std::nullopt};
    // The two normals are fixed by a trusted ore face, not a hidden build-order
    // flag. Swapping the signs mirrors the receiver and drive positions.
    const Point side{-face.toward_ore[2], 0, face.toward_ore[0]};
    bool have_mount = false, have_edge = false, have_receiver = false;
    std::vector<Collector> candidates;
    for (Integer height : {Integer{0}, Integer{1}}) {
        const auto* mount = at(by_center, offset(face.machine_center, face.toward_ore, 1, height),
                               materials::Component::tool_mount);
        if (!mount) continue;
        have_mount = true;
        const auto* edge = at(by_center, offset(face.machine_center, face.toward_ore, 2, height),
                              materials::Component::cutting_edge);
        if (!edge) continue;
        have_edge = true;
        for (Integer sign : {Integer{-1}, Integer{1}}) {
            const auto receiver_center = offset(face.machine_center, side, sign);
            const auto* receiver = at(by_center, receiver_center, materials::Component::receiver_tray);
            if (!receiver) continue;
            have_receiver = true;
            // The mount owns its input spindle. Its shaft is an embodied part
            // of the mount recipe; independent shafts route power to it.
            candidates.push_back({frame->id, mount->id, edge->id, receiver->id, mount->id,
                face.machine_center, face.toward_ore, receiver_center, mount->center,
                height, materials::Component::wooden_shaft});
        }
    }
    if (candidates.size() == 1) return {Status::ready, candidates.front()};
    if (candidates.size() > 1) return {Status::ambiguous, std::nullopt};
    if (!have_mount) return {Status::missing_mount, std::nullopt};
    if (!have_edge) return {Status::missing_edge, std::nullopt};
    if (!have_receiver) return {Status::missing_receiver, std::nullopt};
    return {Status::invalid_input, std::nullopt};
}

SlidingPressInspection Layout::inspect_sliding_press(const Point& center) const {
    for (const auto coordinate : center)
        if (coordinate % 4 != 0 || coordinate < -mechanics::maximum_coordinate + 4 ||
            coordinate > mechanics::maximum_coordinate - 4)
            return {PressStatus::invalid_input, std::nullopt};
    if (!valid_) return {PressStatus::invalid_input, std::nullopt};
    const auto* anvil = at(by_center_, center, materials::Component::anvil);
    if (!anvil) return {PressStatus::missing_anvil, std::nullopt};
    const Point head_center{center[0], center[1] + 1, center[2]};
    const auto* head = at(by_center_, head_center, materials::Component::flat_head);
    if (!head) return {PressStatus::missing_flat_head, std::nullopt};
    const Point slide_center{center[0], center[1] + 2, center[2]};
    const auto found = by_center_.find(slide_center);
    const auto* slide = found != by_center_.end() &&
        (found->second->kind == materials::Component::wooden_slide ||
         found->second->kind == materials::Component::copper_slide) ? found->second : nullptr;
    if (!slide) return {PressStatus::missing_slide, std::nullopt};
    SlidingPress press{anvil->id, head->id, slide->id, center, slide_center,
        slide->kind, {}};
    // The slide's integral input is X-axis. The two opposed X faces remain
    // physical feed/outlet candidates; a tray may receive a finished plate.
    for (const Integer sign : {-1, 1}) {
        const Point entry{center[0] + sign, center[1], center[2]};
        const Point exit{center[0] - sign, center[1], center[2]};
        const Point entry_neighbor{center[0] + 4 * sign, center[1], center[2]};
        const Point exit_neighbor{center[0] - 4 * sign, center[1], center[2]};
        // The quarter-step work points are inside the full-U workbed. A
        // separate neighboring cell must also leave each outside mouth clear.
        if (!by_center_.contains(entry) &&
            !by_center_.contains(entry_neighbor) &&
            !by_center_.contains(exit_neighbor) &&
            (!by_center_.contains(exit) ||
             at(by_center_, exit, materials::Component::receiver_tray)))
            press.open_feeds.push_back({entry, exit});
    }
    if (press.open_feeds.empty()) return {PressStatus::blocked_feed, std::nullopt};
    return {PressStatus::ready, std::move(press)};
}

BroadSlidingPressInspection Layout::inspect_broad_sliding_press(const Point& origin) const {
    constexpr Integer limit = mechanics::maximum_coordinate;
    if (!valid_ || origin[0] % 4 || origin[1] % 4 || origin[2] % 4 ||
        origin[0] < -limit + 4 || origin[0] > limit - 4 ||
        origin[1] < -limit || origin[1] > limit - 4 ||
        origin[2] < -limit + 4 || origin[2] > limit - 4)
        return {PressStatus::invalid_input, std::nullopt};
    const auto* anvil = at(by_center_, origin, materials::Component::broad_anvil);
    if (!anvil) return {PressStatus::missing_anvil, std::nullopt};
    const auto* head = at(by_center_, {origin[0], origin[1] + 1, origin[2]},
        materials::Component::broad_flat_head);
    if (!head) return {PressStatus::missing_flat_head, std::nullopt};
    const Point slide_center{origin[0], origin[1] + 4, origin[2]};
    const auto* slide = at(by_center_, slide_center,
        materials::Component::broad_copper_slide);
    if (!slide) return {PressStatus::missing_slide, std::nullopt};
    BroadSlidingPress press{anvil->id, head->id, slide->id, origin, slide_center,
        slide->kind, {}};
    for (std::size_t index = 0; index < press.work_centers.size(); ++index)
        press.work_centers[index] = {origin[0] + static_cast<Integer>(index % 2) * 4,
            origin[1], origin[2] + static_cast<Integer>(index / 2) * 4};
    return {PressStatus::ready, std::move(press)};
}

Inspection inspect_collector(const std::vector<Part>& placed, const OreFace& face) {
    return Layout(placed).inspect_collector(face);
}

SlidingPressInspection inspect_sliding_press(const std::vector<Part>& placed, const Point& center) {
    return Layout(placed).inspect_sliding_press(center);
}

}  // namespace factory::assembly
