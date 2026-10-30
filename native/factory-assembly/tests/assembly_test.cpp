#include "factory/assembly.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>

namespace a = factory::assembly;
namespace m = factory::materials;
namespace g = factory::mechanics;

namespace {
int checks{};
void check(bool condition, const char* reason) {
    ++checks;
    if (!condition) throw std::runtime_error(reason);
}

a::Part part(const char* id, m::Component kind, g::Point center) {
    return {id, kind, center, 1};
}

void west_face_and_alternate_routes() {
    const a::OreFace face{{0, 0, 0}, {-1, 0, 0}};
    std::vector<a::Part> placed{
        part("frame", m::Component::wooden_frame, {0, 0, 0}),
        part("mount", m::Component::tool_mount, {-1, 0, 0}),
        part("edge", m::Component::cutting_edge, {-2, 0, 0}),
        part("tray", m::Component::receiver_tray, {0, 0, 1}),
        part("spare-cog", m::Component::wooden_cog, {8, 0, 8}),
    };
    const auto first = a::inspect_collector(placed, face);
    check(first.status == a::Status::ready && first.collector &&
          first.collector->frame == "frame" && first.collector->mount == "mount" &&
          first.collector->edge == "edge" && first.collector->receiver == "tray" &&
          first.collector->shaft == "mount" &&
          first.collector->shaft_center == g::Point{-1, 0, 0} &&
          first.collector->cutting_height == 0 &&
          first.collector->shaft_material == m::Component::wooden_shaft,
          "A cutter, mount and receiver expose the mount's embodied input spindle.");
    placed[3].center = {0, 0, -1};
    const auto mirrored = a::inspect_collector(placed, face);
    check(mirrored.status == a::Status::ready && mirrored.collector &&
          mirrored.collector->receiver_center == g::Point{0, 0, -1} &&
          mirrored.collector->shaft_center == g::Point{-1, 0, 0} &&
          mirrored.collector->shaft_material == m::Component::wooden_shaft,
          "Mirroring the receiver keeps the same finite driven mount and input port.");
    placed.push_back(part("second-tray", m::Component::receiver_tray, {0, 0, 1}));
    check(a::inspect_collector(placed, face).status == a::Status::ambiguous,
          "Two supported receiver routes require an explicit choice instead of a hidden winner.");
    placed.back().center = {0, 0, -1};
    check(a::inspect_collector(placed, face).status == a::Status::invalid_input,
          "Two components cannot claim the same world-grid location.");
}

void half_u_face_keeps_collector_parts_apart() {
    const a::OreFace face{{0, 0, 0}, {-2, 0, 0}};
    std::vector<a::Part> placed{
        part("frame", m::Component::wooden_frame, {0, 0, 0}),
        part("mount", m::Component::tool_mount, {-2, 0, 0}),
        part("edge", m::Component::cutting_edge, {-4, 0, 0}),
        part("tray", m::Component::receiver_tray, {0, 0, 2}),
    };
    const auto widened = a::inspect_collector(placed, face);
    check(widened.status == a::Status::ready && widened.collector &&
          widened.collector->shaft_center == g::Point{-2, 0, 0} &&
          widened.collector->receiver_center == g::Point{0, 0, 2},
          "The half-U face keeps the existing collector spacing at two fine-grid steps.");
    placed[3].center = {0, 0, -2};
    const auto mirrored = a::inspect_collector(placed, face);
    check(mirrored.status == a::Status::ready && mirrored.collector &&
          mirrored.collector->receiver_center == g::Point{0, 0, -2},
          "The widened face still admits the mirrored discharge side.");
    check(a::inspect_collector(placed, {{0, 0, 0}, {-3, 0, 0}}).status == a::Status::invalid_input,
          "An arbitrary wider direction cannot become a trusted collector face.");
}

void raised_rotated_face_and_missing_parts() {
    const a::OreFace face{{4, 4, 8}, {0, 0, 1}};
    std::vector<a::Part> placed{
        part("frame", m::Component::wooden_frame, {4, 4, 8}),
        part("mount", m::Component::tool_mount, {4, 5, 9}),
        part("edge", m::Component::cutting_edge, {4, 5, 10}),
        part("tray", m::Component::receiver_tray, {5, 4, 8}),
        part("shaft", m::Component::wooden_shaft, {3, 4, 8}),
    };
    const auto raised = a::inspect_collector(placed, face);
    check(raised.status == a::Status::ready && raised.collector &&
          raised.collector->machine_center == face.machine_center &&
          raised.collector->toward_ore == face.toward_ore &&
          raised.collector->cutting_height == 1,
          "The same arrangement rotates onto a different ore face and raised foundation level.");
    placed[2].center = {4, 4, 10};
    check(a::inspect_collector(placed, face).status == a::Status::missing_edge,
          "An off-height blade cannot silently cut from a raised mount.");
    placed[2].center = {5, 5, 10};
    check(a::inspect_collector(placed, face).status == a::Status::missing_edge,
          "A blade beside the ore axis cannot count as contact with the mounted head.");
    placed[2].center = {4, 5, 10};
    placed[2].kind = m::Component::anvil;
    check(a::inspect_collector(placed, face).status == a::Status::missing_edge,
          "A press anvil cannot substitute for the metal cutting edge.");
    placed[2].kind = m::Component::cutting_edge;
    placed[4].center = {12, 4, 8};
    check(a::inspect_collector(placed, face).status == a::Status::ready,
          "A distant independent shaft is optional routing, not a collector recipe token.");
    placed.pop_back();
    placed.pop_back();
    check(a::inspect_collector(placed, face).status == a::Status::missing_receiver,
          "The cutter cannot work without a receiver on an admitted discharge side.");
    placed.pop_back();
    check(a::inspect_collector(placed, face).status == a::Status::missing_edge,
          "The receiver is not a substitute for a cutting head.");
    placed.pop_back();
    check(a::inspect_collector(placed, face).status == a::Status::missing_mount,
          "A loose frame is not a tool assembly.");
    placed.pop_back();
    check(a::inspect_collector(placed, face).status == a::Status::missing_frame,
          "An empty workcell cannot claim a collector.");
}

void malformed_and_ambiguous_input() {
    const a::OreFace face{{0, 0, 0}, {-1, 0, 0}};
    const auto base = part("frame", m::Component::wooden_frame, {0, 0, 0});
    check(a::inspect_collector({base}, {{1, 0, 0}, {-1, 0, 0}}).status == a::Status::invalid_input &&
          a::inspect_collector({base}, {{0, 0, 0}, {1, 0, 1}}).status == a::Status::invalid_input &&
          a::inspect_collector({base}, {{0, 0, 0}, {0, 1, 0}}).status == a::Status::invalid_input,
          "The ore face must use the common four-step workcell and one horizontal cardinal direction.");
    auto duplicate = base;
    duplicate.center = {4, 0, 0};
    check(a::inspect_collector({base, duplicate}, face).status == a::Status::invalid_input,
          "Duplicate identities are not two usable frames.");
    duplicate.id = "other";
    duplicate.generation = 0;
    check(a::inspect_collector({base, duplicate}, face).status == a::Status::invalid_input,
          "Unissued component generations are rejected before geometry recognition.");
    duplicate.generation = 1;
    duplicate.kind = static_cast<m::Component>(999);
    check(a::inspect_collector({base, duplicate}, face).status == a::Status::invalid_input,
          "An unknown component kind cannot enter the assembly projection.");
}

void sliding_press_contact_geometry() {
    const g::Point work{8, 4, 12};
    std::vector<a::Part> placed{
        part("anvil", m::Component::anvil, work),
        part("head", m::Component::flat_head, {8, 5, 12}),
        part("slide", m::Component::wooden_slide, {8, 6, 12}),
    };
    const a::Layout layout(placed);
    const auto ready = layout.inspect_sliding_press(work);
    check(ready.status == a::PressStatus::ready && ready.press &&
          ready.press->anvil == "anvil" && ready.press->head == "head" &&
          ready.press->slide == "slide" && ready.press->slide_center == g::Point{8, 6, 12} &&
          ready.press->open_feeds.size() == 2,
          "A separate head mates to the slide immediately above a supported work point.");
    placed[2].kind = m::Component::copper_slide;
    check(a::inspect_sliding_press(placed, work).press->slide_material ==
              m::Component::copper_slide,
          "The same contact geometry accepts a stronger slide without replacing the head.");
    placed.push_back(part("tray", m::Component::receiver_tray, {7, 4, 12}));
    check(a::inspect_sliding_press(placed, work).press->open_feeds.size() == 1,
          "A fitted plate tray may occupy the exit, but not the entry.");
    placed[3].kind = m::Component::wooden_frame;
    check(a::inspect_sliding_press(placed, work).status == a::PressStatus::blocked_feed,
          "A solid obstruction cannot be treated as an outlet.");
    placed.pop_back();
    placed[2].center[1] += 1;
    check(a::inspect_sliding_press(placed, work).status == a::PressStatus::missing_slide,
          "A slide one step too high cannot contact the head.");
    placed[2].center[1] -= 1;
    placed[1].kind = m::Component::cutting_edge;
    check(a::inspect_sliding_press(placed, work).status == a::PressStatus::missing_flat_head,
          "A cutting edge is not an interchangeable flat head.");
    check(a::inspect_sliding_press(placed, {8, 5, 12}).status ==
              a::PressStatus::invalid_input,
          "Work support uses the common full-tile grid.");
}

void receiver_snapshot_lookup() {
    const g::Point work{8, 4, 12};
    const g::Point exit{7, 4, 12};
    const std::vector<a::Part> bare{
        part("anvil", m::Component::anvil, work),
        part("head", m::Component::flat_head, {8, 5, 12}),
        part("slide", m::Component::wooden_slide, {8, 6, 12}),
    };
    const a::Layout absent(bare);
    check(absent.valid() && !absent.has_component(exit, m::Component::receiver_tray),
          "An open selected exit has no receiver in its immutable placement snapshot.");
    auto with_tray = bare;
    with_tray.push_back(part("outlet", m::Component::receiver_tray, exit));
    const a::Layout tray(with_tray);
    const auto inspected = tray.inspect_sliding_press(work);
    check(tray.valid() && tray.has_component(exit, m::Component::receiver_tray) &&
          inspected.status == a::PressStatus::ready && inspected.press &&
          inspected.press->open_feeds.size() == 1,
          "The indexed selected exit finds its actual receiver tray.");
    auto occupied = with_tray;
    occupied.back().kind = m::Component::wooden_frame;
    const a::Layout blocker(occupied);
    check(blocker.valid() && !blocker.has_component(exit, m::Component::receiver_tray) &&
          blocker.inspect_sliding_press(work).status == a::PressStatus::blocked_feed,
          "A solid outlet obstruction is not a receiver or a valid through-feed.");
    auto removed = with_tray;
    removed.pop_back();
    const a::Layout after_removal(removed);
    check(after_removal.valid() && !after_removal.has_component(exit, m::Component::receiver_tray),
          "A new placement snapshot drops the removed tray without stale receiver state.");
    occupied.back().kind = m::Component::receiver_tray;
    const a::Layout replacement(occupied);
    check(replacement.valid() && replacement.has_component(exit, m::Component::receiver_tray),
          "A replacement tray is recognized by a fresh placement snapshot.");
    occupied.push_back(part("duplicate", m::Component::receiver_tray, exit));
    const a::Layout invalid(occupied);
    check(!invalid.valid() && !invalid.has_component(exit, m::Component::receiver_tray),
          "An invalid duplicate outlet cannot expose a cached receiver.");
}

void indexed_independent_assemblies() {
    std::vector<a::Part> placed;
    placed.reserve(1700);
    std::vector<a::OreFace> faces;
    for (int index = 0; index < 200; ++index) {
        const g::Integer x = index * 8;
        const auto name = "collector-" + std::to_string(index);
        faces.push_back({{x, 0, 0}, {-1, 0, 0}});
        placed.push_back({name + "-frame", m::Component::wooden_frame, {x, 0, 0}, 1});
        placed.push_back({name + "-mount", m::Component::tool_mount, {x - 1, 0, 0}, 1});
        placed.push_back({name + "-edge", m::Component::cutting_edge, {x - 2, 0, 0}, 1});
        placed.push_back({name + "-tray", m::Component::receiver_tray, {x, 0, 1}, 1});
        placed.push_back({name + "-shaft", m::Component::wooden_shaft, {x + 1, 0, 0}, 1});
    }
    for (int index = 0; index < 100; ++index) {
        const g::Integer x = index * 8;
        const auto name = "press-" + std::to_string(index);
        placed.push_back({name + "-anvil", m::Component::anvil, {x, 8, 16}, 1});
        placed.push_back({name + "-head", m::Component::flat_head, {x, 9, 16}, 1});
        placed.push_back({name + "-slide", m::Component::wooden_slide, {x, 10, 16}, 1});
    }
    const a::Layout indexed(placed);
    check(indexed.valid(), "Three hundred disjoint assemblies have unique component identities and centers.");
    for (int index = 0; index < 200; ++index) {
        const auto current = indexed.inspect_collector(faces[index]);
        const auto direct = a::inspect_collector(placed, faces[index]);
        check(current.status == a::Status::ready && current.collector && direct.collector &&
              current.status == direct.status &&
              current.collector == direct.collector && current.collector->frame ==
                  "collector-" + std::to_string(index) + "-frame",
              "The shared index identifies each independent collector exactly as direct inspection does.");
    }
    for (int index = 0; index < 100; ++index) {
        const g::Point center{index * 8, 8, 16};
        const auto current = indexed.inspect_sliding_press(center);
        const auto direct = a::inspect_sliding_press(placed, center);
        check(current.status == a::PressStatus::ready && current.press && direct.press &&
              current.status == direct.status &&
              current.press == direct.press && current.press->anvil ==
                  "press-" + std::to_string(index) + "-anvil",
              "The shared index keeps each press drive, work point and feed routes separate.");
    }
    std::array<double, 20> direct_ms{}, indexed_ms{};
    for (std::size_t sample = 0; sample < direct_ms.size(); ++sample) {
        std::size_t direct_count = 0, indexed_count = 0;
        const auto direct_start = std::chrono::steady_clock::now();
        for (const auto& face : faces)
            direct_count += a::inspect_collector(placed, face).status == a::Status::ready;
        for (int index = 0; index < 100; ++index)
            direct_count += a::inspect_sliding_press(placed, {index * 8, 8, 16}).status == a::PressStatus::ready;
        const auto indexed_start = std::chrono::steady_clock::now();
        const a::Layout snapshot(placed);
        for (const auto& face : faces)
            indexed_count += snapshot.inspect_collector(face).status == a::Status::ready;
        for (int index = 0; index < 100; ++index)
            indexed_count += snapshot.inspect_sliding_press({index * 8, 8, 16}).status == a::PressStatus::ready;
        const auto end = std::chrono::steady_clock::now();
        check(direct_count == 300 && indexed_count == direct_count,
              "Repeated direct and indexed cuts find the same complete assemblies.");
        direct_ms[sample] = std::chrono::duration<double, std::milli>(indexed_start - direct_start).count();
        indexed_ms[sample] = std::chrono::duration<double, std::milli>(end - indexed_start).count();
    }
    std::sort(direct_ms.begin(), direct_ms.end());
    std::sort(indexed_ms.begin(), indexed_ms.end());
    std::cout << "{\"evidence\":\"synthetic_assembly_inspection\",\"parts\":1700,"
              << "\"collectors\":200,\"presses\":100,\"samples\":20,"
              << "\"direct_median_ms\":" << direct_ms[10]
              << ",\"direct_p95_ms\":" << direct_ms[19]
              << ",\"indexed_median_ms\":" << indexed_ms[10]
              << ",\"indexed_p95_ms\":" << indexed_ms[19] << "}\n";
    std::vector<g::Point> slide_exits;
    slide_exits.reserve(80);
    for (int index = 0; index < 80; ++index) {
        const g::Integer x = 2400 + index * 8;
        const auto name = "slide-" + std::to_string(index);
        placed.push_back({name + "-anvil", m::Component::anvil, {x, 4, 32}, 1});
        placed.push_back({name + "-head", m::Component::flat_head, {x, 5, 32}, 1});
        placed.push_back({name + "-body", m::Component::wooden_slide, {x, 6, 32}, 1});
        slide_exits.push_back({x - 1, 4, 32});
        if (index % 2 == 0)
            placed.push_back({name + "-tray", m::Component::receiver_tray,
                slide_exits.back(), 1});
    }
    const a::Layout slide_snapshot(placed);
    check(slide_snapshot.valid(), "Eighty independent slide outlets share one valid placement index.");
    std::map<std::string, a::Part> placed_by_id;
    for (const auto& item : placed) placed_by_id.emplace(item.id, item);
    std::array<double, 20> receiver_scan_ms{}, receiver_indexed_ms{};
    for (std::size_t sample = 0; sample < receiver_scan_ms.size(); ++sample) {
        int scan_hits = 0, indexed_hits = 0;
        const auto scan_start = std::chrono::steady_clock::now();
        for (int repeat = 0; repeat < 20; ++repeat)
            for (const auto& exit : slide_exits)
                scan_hits += std::any_of(placed_by_id.begin(), placed_by_id.end(),
                    [&](const auto& entry) {
                        return entry.second.kind == m::Component::receiver_tray &&
                            entry.second.center == exit;
                    });
        const auto indexed_start = std::chrono::steady_clock::now();
        for (int repeat = 0; repeat < 20; ++repeat)
            for (const auto& exit : slide_exits)
                indexed_hits += slide_snapshot.has_component(exit, m::Component::receiver_tray);
        const auto end = std::chrono::steady_clock::now();
        check(scan_hits == 800 && indexed_hits == scan_hits,
              "Eighty slide outlets agree across repeated map scans and indexed queries.");
        receiver_scan_ms[sample] =
            std::chrono::duration<double, std::milli>(indexed_start - scan_start).count();
        receiver_indexed_ms[sample] =
            std::chrono::duration<double, std::milli>(end - indexed_start).count();
    }
    std::sort(receiver_scan_ms.begin(), receiver_scan_ms.end());
    std::sort(receiver_indexed_ms.begin(), receiver_indexed_ms.end());
    std::cout << "{\"evidence\":\"synthetic_slide_receiver_lookup\",\"parts\":"
              << placed.size() << ",\"slides\":80,\"queries_per_sample\":1600,\"samples\":20,"
              << "\"scan_median_ms\":" << receiver_scan_ms[10]
              << ",\"scan_p95_ms\":" << receiver_scan_ms[19]
              << ",\"indexed_median_ms\":" << receiver_indexed_ms[10]
              << ",\"indexed_p95_ms\":" << receiver_indexed_ms[19] << "}\n";
    placed.back().id = placed.front().id;
    const a::Layout invalid(placed);
    check(!invalid.valid() && invalid.inspect_collector(faces.front()).status == a::Status::invalid_input &&
          invalid.inspect_sliding_press({0, 8, 16}).status == a::PressStatus::invalid_input,
          "One duplicate identity invalidates the complete shared layout before either inspection.");
}
}  // namespace

int main() {
    try {
        west_face_and_alternate_routes();
        half_u_face_keeps_collector_parts_apart();
        raised_rotated_face_and_missing_parts();
        malformed_and_ambiguous_input();
        sliding_press_contact_geometry();
        receiver_snapshot_lookup();
        indexed_independent_assemblies();
        std::cout << "assembly_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "assembly_test: " << error.what() << '\n';
        return 1;
    }
}
