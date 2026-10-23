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

const Part* shaft_at(const std::map<Point, const Part*>& by_center, const Point& center) {
    const auto found = by_center.find(center);
    return found != by_center.end() &&
        (found->second->kind == materials::Component::wooden_shaft ||
         found->second->kind == materials::Component::softmetal_shaft) ? found->second : nullptr;
}

const Part* cog_at(const std::map<Point, const Part*>& by_center, const Point& center) {
    const auto found = by_center.find(center);
    return found != by_center.end() &&
        (found->second->kind == materials::Component::wooden_cog ||
         found->second->kind == materials::Component::softmetal_cog) ? found->second : nullptr;
}

bool valid_face(const OreFace& face) {
    const auto& center = face.machine_center;
    const auto& toward = face.toward_ore;
    if (center[0] % 4 || center[1] % 4 || center[2] % 4 || toward[1] != 0 ||
        (toward[0] == 0) == (toward[2] == 0) ||
        (toward[0] != 0 && toward[0] != 1 && toward[0] != -1) ||
        (toward[2] != 0 && toward[2] != 1 && toward[2] != -1)) return false;
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

Inspection Layout::inspect_collector(const OreFace& face) const {
    if (!valid_ || !valid_face(face)) return {Status::invalid_input, std::nullopt};
    const auto& by_center = by_center_;

    const auto* frame = at(by_center, face.machine_center, materials::Component::wooden_frame);
    if (!frame) return {Status::missing_frame, std::nullopt};
    // The two normals are fixed by a trusted ore face, not a hidden build-order
    // flag. Swapping the signs mirrors the receiver and drive positions.
    const Point side{-face.toward_ore[2], 0, face.toward_ore[0]};
    const Point back{-face.toward_ore[0], 0, -face.toward_ore[2]};
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
            for (const auto shaft_center : {offset(face.machine_center, back, 1),
                    offset(face.machine_center, side, -sign)}) {
                const auto* shaft = shaft_at(by_center, shaft_center);
                if (!shaft) continue;
                candidates.push_back({frame->id, mount->id, edge->id, receiver->id, shaft->id,
                    face.machine_center, face.toward_ore, receiver_center, shaft_center,
                    height, shaft->kind});
            }
        }
    }
    if (candidates.size() == 1) return {Status::ready, candidates.front()};
    if (candidates.size() > 1) return {Status::ambiguous, std::nullopt};
    if (!have_mount) return {Status::missing_mount, std::nullopt};
    if (!have_edge) return {Status::missing_edge, std::nullopt};
    if (!have_receiver) return {Status::missing_receiver, std::nullopt};
    return {Status::missing_shaft, std::nullopt};
}

PressInspection Layout::inspect_press(const Point& center) const {
    for (const auto coordinate : center)
        if (coordinate % 4 != 0 || coordinate < -mechanics::maximum_coordinate + 4 ||
            coordinate > mechanics::maximum_coordinate - 4)
            return {PressStatus::invalid_input, std::nullopt};
    if (!valid_) return {PressStatus::invalid_input, std::nullopt};
    const auto& by_center = by_center_;
    const auto raised = [&](Integer height) { return Point{center[0], center[1] + height, center[2]}; };
    const auto* frame = at(by_center, center, materials::Component::wooden_frame);
    if (!frame) return {PressStatus::missing_frame, std::nullopt};
    const auto* anvil = at(by_center, raised(1), materials::Component::anvil);
    if (!anvil) return {PressStatus::missing_anvil, std::nullopt};
    const auto* ram = at(by_center, raised(2), materials::Component::ram_face);
    if (!ram) return {PressStatus::missing_ram, std::nullopt};
    const auto* guide = at(by_center, raised(3), materials::Component::sliding_guide);
    if (!guide) return {PressStatus::missing_guide, std::nullopt};
    const auto* mount = at(by_center, raised(4), materials::Component::tool_mount);
    if (!mount) return {PressStatus::missing_mount, std::nullopt};

    constexpr std::array<Point, 4> directions{{{1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}}};
    bool shaft_seen = false;
    std::vector<Press> candidates;
    for (const auto& direction : directions) {
        const Point shaft_center{center[0] + direction[0], center[1] + 4,
                                 center[2] + direction[2]};
        const auto* shaft = shaft_at(by_center, shaft_center);
        if (!shaft) continue;
        shaft_seen = true;
        const Point cog_center{center[0] + 2 * direction[0], center[1] + 4,
                               center[2] + 2 * direction[2]};
        const auto* cog = cog_at(by_center, cog_center);
        if (!cog) continue;
        candidates.push_back({frame->id, anvil->id, ram->id, guide->id, mount->id,
            shaft->id, cog->id, center, raised(1), shaft_center, cog_center,
            shaft->kind, cog->kind, {}});
    }
    if (candidates.empty()) return {shaft_seen ? PressStatus::missing_cog : PressStatus::missing_shaft,
                                    std::nullopt};
    if (candidates.size() > 1) return {PressStatus::ambiguous, std::nullopt};
    auto& press = candidates.front();
    for (const auto& direction : directions) {
        const Point entry{press.work_center[0] + direction[0], press.work_center[1],
                          press.work_center[2] + direction[2]};
        const Point exit{press.work_center[0] - direction[0], press.work_center[1],
                         press.work_center[2] - direction[2]};
        if (!by_center.contains(entry) && !by_center.contains(exit))
            press.open_feeds.push_back({entry, exit});
    }
    if (press.open_feeds.empty()) return {PressStatus::blocked_feed, std::nullopt};
    return {PressStatus::ready, std::move(press)};
}

GuidedPressInspection Layout::inspect_guided_press(const Point& center) const {
    for (const auto coordinate : center)
        if (coordinate % 4 != 0 || coordinate < -mechanics::maximum_coordinate + 4 ||
            coordinate > mechanics::maximum_coordinate - 4)
            return {PressStatus::invalid_input, std::nullopt};
    if (!valid_) return {PressStatus::invalid_input, std::nullopt};
    const auto& by_center = by_center_;
    const auto raised = [&](Integer height) { return Point{center[0], center[1] + height, center[2]}; };
    const auto* anvil = at(by_center, center, materials::Component::anvil);
    if (!anvil) return {PressStatus::missing_anvil, std::nullopt};
    const auto* ram = at(by_center, raised(1), materials::Component::ram_face);
    if (!ram) return {PressStatus::missing_ram, std::nullopt};
    const auto* guide = at(by_center, raised(3), materials::Component::sliding_guide);
    if (!guide) return {PressStatus::missing_guide, std::nullopt};
    if (by_center.contains(raised(2))) return {PressStatus::blocked_stroke, std::nullopt};

    constexpr std::array<Point, 4> directions{{{1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}}};
    bool shaft_seen = false;
    std::vector<GuidedPress> candidates;
    for (const auto& direction : directions) {
        const Point shaft_center{center[0] + direction[0], center[1] + 4,
                                 center[2] + direction[2]};
        const auto* shaft = shaft_at(by_center, shaft_center);
        if (!shaft) continue;
        shaft_seen = true;
        const Point cog_center{center[0] + 2 * direction[0], center[1] + 4,
                               center[2] + 2 * direction[2]};
        const auto* cog = cog_at(by_center, cog_center);
        if (!cog) continue;
        candidates.push_back({anvil->id, ram->id, guide->id, shaft->id, cog->id,
            center, shaft_center, cog_center, shaft->kind, cog->kind, {}});
    }
    if (candidates.empty()) return {shaft_seen ? PressStatus::missing_cog : PressStatus::missing_shaft,
                                    std::nullopt};
    if (candidates.size() > 1) return {PressStatus::ambiguous, std::nullopt};
    auto& press = candidates.front();
    for (const auto& direction : directions) {
        const Point entry{center[0] + direction[0], center[1], center[2] + direction[2]};
        const Point exit{center[0] - direction[0], center[1], center[2] - direction[2]};
        if (!by_center.contains(entry) && !by_center.contains(exit))
            press.open_feeds.push_back({entry, exit});
    }
    if (press.open_feeds.empty()) return {PressStatus::blocked_feed, std::nullopt};
    return {PressStatus::ready, std::move(press)};
}

BroadPressInspection Layout::inspect_broad_press(const Point& origin) const {
    constexpr Integer limit = mechanics::maximum_coordinate;
    if (!valid_ || origin[0] % 4 || origin[1] % 4 || origin[2] % 4 ||
        origin[0] < -limit + 2 || origin[0] > limit - 6 ||
        origin[1] < -limit || origin[1] > limit - 4 ||
        origin[2] < -limit + 2 || origin[2] > limit - 6)
        return {BroadPressStatus::invalid_input, std::nullopt};

    BroadPress base;
    base.origin = origin;
    for (std::size_t index = 0; index < base.work_centers.size(); ++index) {
        const Point cell{origin[0] + static_cast<Integer>(index % 2) * 4,
            origin[1], origin[2] + static_cast<Integer>(index / 2) * 4};
        base.work_centers[index] = cell;
        const auto* anvil = at(by_center_, cell, materials::Component::anvil);
        if (!anvil) return {BroadPressStatus::missing_anvil, std::nullopt};
        base.anvils[index] = anvil->id;
        const auto* ram = at(by_center_, {cell[0], cell[1] + 1, cell[2]},
            materials::Component::ram_face);
        if (!ram) return {BroadPressStatus::missing_ram, std::nullopt};
        base.rams[index] = ram->id;
        const auto* guide = at(by_center_, {cell[0], cell[1] + 3, cell[2]},
            materials::Component::sliding_guide);
        if (!guide) return {BroadPressStatus::missing_guide, std::nullopt};
        base.guides[index] = guide->id;
        if (by_center_.contains({cell[0], cell[1] + 2, cell[2]}))
            return {BroadPressStatus::blocked_stroke, std::nullopt};
    }

    for (std::size_t index = 0; index < base.work_centers.size(); ++index) {
        const auto& cell = base.work_centers[index];
        constexpr std::array<Point, 4> directions{{{1, 0, 0}, {-1, 0, 0},
            {0, 0, 1}, {0, 0, -1}}};
        bool shaft_seen = false;
        const Part* chosen_shaft = nullptr;
        const Part* chosen_cog = nullptr;
        Point chosen_shaft_center{}, chosen_cog_center{};
        for (const auto& direction : directions) {
            if ((direction[0] > 0 && index % 2 == 0) ||
                (direction[0] < 0 && index % 2 == 1) ||
                (direction[2] > 0 && index / 2 == 0) ||
                (direction[2] < 0 && index / 2 == 1)) continue;
            const Point shaft_center{cell[0] + direction[0], cell[1] + 4,
                cell[2] + direction[2]};
            const auto* shaft = shaft_at(by_center_, shaft_center);
            if (!shaft) continue;
            shaft_seen = true;
            const Point cog_center{cell[0] + 2 * direction[0], cell[1] + 4,
                cell[2] + 2 * direction[2]};
            const auto* cog = cog_at(by_center_, cog_center);
            if (!cog) continue;
            if (chosen_shaft) return {BroadPressStatus::ambiguous, std::nullopt};
            chosen_shaft = shaft;
            chosen_cog = cog;
            chosen_shaft_center = shaft_center;
            chosen_cog_center = cog_center;
        }
        if (!chosen_shaft)
            return {shaft_seen ? BroadPressStatus::missing_cog : BroadPressStatus::missing_shaft,
                std::nullopt};
        base.shafts[index] = chosen_shaft->id;
        base.drive_cogs[index] = chosen_cog->id;
        base.shaft_centers[index] = chosen_shaft_center;
        base.cog_centers[index] = chosen_cog_center;
        base.shaft_materials[index] = chosen_shaft->kind;
        base.cog_materials[index] = chosen_cog->kind;
    }
    return {BroadPressStatus::ready, std::move(base)};
}

Inspection inspect_collector(const std::vector<Part>& placed, const OreFace& face) {
    return Layout(placed).inspect_collector(face);
}

PressInspection inspect_press(const std::vector<Part>& placed, const Point& center) {
    return Layout(placed).inspect_press(center);
}

GuidedPressInspection inspect_guided_press(const std::vector<Part>& placed, const Point& center) {
    return Layout(placed).inspect_guided_press(center);
}

BroadPressInspection inspect_broad_press(const std::vector<Part>& placed, const Point& center) {
    return Layout(placed).inspect_broad_press(center);
}

}  // namespace factory::assembly
