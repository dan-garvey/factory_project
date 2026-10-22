#include "factory/assembly.hpp"

#include <map>
#include <set>

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

Inspection inspect_collector(const std::vector<Part>& placed, const OreFace& face) {
    if (!valid_face(face) || placed.size() > 4096) return {Status::invalid_input, std::nullopt};
    std::map<Point, const Part*> by_center;
    std::set<std::string> ids;
    for (const auto& part : placed)
        if (!valid_part(part) || !ids.insert(part.id).second ||
            !by_center.emplace(part.center, &part).second)
            return {Status::invalid_input, std::nullopt};

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

}  // namespace factory::assembly
