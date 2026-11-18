#include "assembly_projection.hpp"

#include "factory/assembly.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace factory::godot_world::assembly_projection {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;

const char* collector_status_name(assembly::Status status) {
    switch (status) {
        case assembly::Status::ready: return "ready";
        case assembly::Status::invalid_input: return "invalid_input";
        case assembly::Status::missing_frame: return "missing_frame";
        case assembly::Status::missing_mount: return "missing_mount";
        case assembly::Status::missing_edge: return "missing_edge";
        case assembly::Status::missing_receiver: return "missing_receiver";
        case assembly::Status::ambiguous: return "ambiguous";
    }
    return "invalid_input";
}

const char* press_status_name(assembly::PressStatus status) {
    switch (status) {
        case assembly::PressStatus::ready: return "ready";
        case assembly::PressStatus::invalid_input: return "invalid_input";
        case assembly::PressStatus::missing_anvil: return "missing_anvil";
        case assembly::PressStatus::missing_flat_head: return "missing_flat_head";
        case assembly::PressStatus::missing_slide: return "missing_slide";
        case assembly::PressStatus::blocked_feed: return "blocked_feed";
    }
    return "invalid_input";
}

const stationary::PlacedPart* find(const world::State& state, const std::string& id) {
    const auto found = std::find_if(state.topology.parts.begin(), state.topology.parts.end(),
        [&](const auto& part) { return part.geometry.id == id; });
    return found == state.topology.parts.end() ? nullptr : &*found;
}
}  // namespace

Object fields(const world::Profile& profile, const world::State& state,
              const world::DrivePower& power) {
    Object projection;
    if (!state.landing_pod) return projection;
    std::vector<assembly::Part> parts;
    parts.reserve(state.placed_components.size());
    for (const auto& [id, component] : state.placed_components)
        parts.push_back({id, component.kind, component.center, component.generation});
    Array collectors;
    for (const auto& face : profile.collector_faces) {
        if (profile.excavation) break;
        const auto inspection = assembly::inspect_collector(parts, face);
        Object entry{{"center", Value(Array{Value(face.machine_center[0]),
            Value(face.machine_center[1]), Value(face.machine_center[2])})},
            {"toward_ore", Value(Array{Value(face.toward_ore[0]),
                Value(face.toward_ore[1]), Value(face.toward_ore[2])})},
            {"status", Value(collector_status_name(inspection.status))}};
        if (inspection.collector) {
            const auto& assembled = *inspection.collector;
            entry.emplace("parts", Value(Object{{"frame", Value(assembled.frame)},
                {"mount", Value(assembled.mount)}, {"edge", Value(assembled.edge)},
                {"receiver", Value(assembled.receiver)}, {"shaft", Value(assembled.shaft)}}));
            entry.emplace("cutting_height", Value(assembled.cutting_height));
        }
        collectors.emplace_back(std::move(entry));
    }
    projection.emplace("collector_assemblies", Value(std::move(collectors)));
    Array sliding_presses;
    std::set<mechanics::Point> belt_tiles;
    std::map<mechanics::Point, std::pair<int, int>> mouth_roles;
    // World accepts press handoff only at a full-tile belt endpoint.
    // Index all lanes once so each workbed reads only its two X mouths.
    for (const auto& span : state.topology.belt_spans) {
        const auto* first = find(state, span.geometry.first_shaft);
        const auto* last = find(state, span.geometry.last_shaft);
        if (!first || !last) continue;
        const auto path = mechanics::belt_path(first->geometry, last->geometry);
        if (!path) continue;
        belt_tiles.insert(path->tiles.begin(), path->tiles.end());
        const auto motion = power.mechanical.motion.find(span.geometry.first_shaft);
        if (motion == power.mechanical.motion.end() ||
            motion->second.state != mechanics::MotionState::rotating) continue;
        const auto direction = mechanics::belt_cargo_direction(first->geometry,
            last->geometry, motion->second.rate);
        if (!direction || *direction == 0) continue;
        for (const bool at_last : {false, true}) {
            const auto& mouth = at_last ? path->tiles.back() : path->tiles.front();
            auto& [inbound, outbound] = mouth_roles[mouth];
            if (at_last == (*direction > 0)) ++inbound;
            else ++outbound;
        }
    }
    for (const auto& anvil : parts) {
        if (anvil.kind != materials::Component::anvil) continue;
        const auto inspection = assembly::inspect_sliding_press(parts, anvil.center);
        const mechanics::Point west_mouth{anvil.center[0] - 4, anvil.center[1], anvil.center[2]};
        const mechanics::Point east_mouth{anvil.center[0] + 4, anvil.center[1], anvil.center[2]};
        const bool mouth_has_belt = belt_tiles.contains(west_mouth) || belt_tiles.contains(east_mouth);
        const bool manual_auto_route = profile.landing_pod_center.has_value();
        Object entry{{"anvil", Value(anvil.id)},
            {"center", Value(Array{Value(anvil.center[0]), Value(anvil.center[1]),
                Value(anvil.center[2])})},
            {"status", Value(press_status_name(inspection.status))}};
        if (manual_auto_route && (inspection.status == assembly::PressStatus::ready ||
                inspection.status == assembly::PressStatus::blocked_feed))
            entry.emplace("auto_route", Value(true));
        if (inspection.press) {
            const auto& press = *inspection.press;
            entry.emplace("parts", Value(Object{{"anvil", Value(press.anvil)},
                {"head", Value(press.head)}, {"slide", Value(press.slide)}}));
            entry.emplace("work_center", Value(Array{Value(press.work_center[0]),
                Value(press.work_center[1]), Value(press.work_center[2])}));
            entry.emplace("slide_center", Value(Array{Value(press.slide_center[0]),
                Value(press.slide_center[1]), Value(press.slide_center[2])}));
            if (const auto selected = state.slide_press_routes.find(press.work_center);
                selected != state.slide_press_routes.end())
                entry.emplace("selected_exit", Value(Array{Value(selected->second[0]),
                    Value(selected->second[1]), Value(selected->second[2])}));
            Array feeds;
            const auto selected = state.slide_press_routes.find(press.work_center);
            const auto route_score = [&](const assembly::PressFeed& feed) {
                const auto entry_mouth = feed.entry[0] < press.work_center[0] ? west_mouth : east_mouth;
                const auto exit_mouth = feed.exit[0] < press.work_center[0] ? west_mouth : east_mouth;
                const auto [input_in, input_out] = mouth_roles[entry_mouth];
                const auto [output_in, output_out] = mouth_roles[exit_mouth];
                return input_out || output_in ? 0 : input_in + output_out;
            };
            int candidate_count = 0;
            mechanics::Point inferred_exit{};
            if (manual_auto_route && mouth_has_belt && selected == state.slide_press_routes.end())
                for (const auto& feed : press.open_feeds)
                    if (route_score(feed) > 0) { ++candidate_count; inferred_exit = feed.exit; }
            for (const auto& feed : press.open_feeds) {
                Object route{{"entry", Value(Array{Value(feed.entry[0]),
                    Value(feed.entry[1]), Value(feed.entry[2])})},
                    {"exit", Value(Array{Value(feed.exit[0]), Value(feed.exit[1]),
                        Value(feed.exit[2])})}};
                // Retained work keeps its native outlet. A tray on one
                // side leaves a single physically open through-feed;
                // only two open manual routes need the east default.
                // A connected lane supplies a role only when exactly one
                // route agrees with its actual cargo motion.
                if (manual_auto_route && (selected != state.slide_press_routes.end() ?
                        feed.exit == selected->second :
                        mouth_has_belt ? candidate_count == 1 && feed.exit == inferred_exit :
                        (press.open_feeds.size() == 1 ||
                            feed.exit == mechanics::Point{press.work_center[0] + 1,
                                press.work_center[1], press.work_center[2]})))
                    entry.emplace("auto_feed", Value(route));
                feeds.emplace_back(std::move(route));
            }
            entry.emplace("open_feeds", Value(std::move(feeds)));
        }
        sliding_presses.emplace_back(std::move(entry));
    }
    projection.emplace("sliding_press_assemblies", Value(std::move(sliding_presses)));
    Array broad_presses;
    const auto grid_value = [](const mechanics::Point& center) {
        return Value(Array{Value(center[0]), Value(center[1]), Value(center[2])});
    };
    const assembly::Layout sized_layout(parts);
    for (const auto& part : parts) {
        if (part.kind != materials::Component::broad_anvil) continue;
        const auto sized = sized_layout.inspect_broad_sliding_press(part.center);
        Object entry{{"origin", grid_value(part.center)},
            {"geometry_status", Value(press_status_name(sized.status))},
            {"status", Value(press_status_name(sized.status))}};
        if (sized.press) {
            const auto& press = *sized.press;
            Array work_centers;
            for (const auto& center : press.work_centers)
                work_centers.emplace_back(grid_value(center));
            entry.emplace("work_centers", Value(std::move(work_centers)));
            entry.emplace("parts", Value(Object{
                {"anvils", Value(Array{Value(press.anvil)})},
                {"heads", Value(Array{Value(press.head)})},
                {"slide", Value(press.slide)}}));
            const auto motion = power.mechanical.motion.find(press.slide);
            const bool overloaded = power.load.contains(press.slide) &&
                power.load.at(press.slide).overloaded;
            if (motion == power.mechanical.motion.end() ||
                motion->second.state == mechanics::MotionState::unpowered)
                entry["status"] = Value("unpowered");
            else if (overloaded || motion->second.state == mechanics::MotionState::stalled)
                entry["status"] = Value("stalled");
            else if (motion->second.state != mechanics::MotionState::rotating ||
                motion->second.rate.numerator == 0)
                entry["status"] = Value("stopped");
            else {
                entry["status"] = Value("ready");
                entry.emplace("stroke_rate", Value(Array{
                    Value(std::abs(motion->second.rate.numerator)),
                    Value(motion->second.rate.denominator)}));
            }
        }
        broad_presses.emplace_back(std::move(entry));
    }
    projection.emplace("broad_press_assemblies", Value(std::move(broad_presses)));
    return projection;
}

}  // namespace factory::godot_world::assembly_projection
