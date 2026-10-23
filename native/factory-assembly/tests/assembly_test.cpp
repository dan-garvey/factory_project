#include "factory/assembly.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <iostream>
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
        part("drive", m::Component::wooden_shaft, {1, 0, 0}),
        part("spare-cog", m::Component::wooden_cog, {8, 0, 8}),
    };
    const auto first = a::inspect_collector(placed, face);
    check(first.status == a::Status::ready && first.collector &&
          first.collector->frame == "frame" && first.collector->mount == "mount" &&
          first.collector->edge == "edge" && first.collector->receiver == "tray" &&
          first.collector->shaft == "drive" && first.collector->cutting_height == 0 &&
          first.collector->shaft_material == m::Component::wooden_shaft,
          "A cutter, mount, receiver and light shaft form one exact west-facing candidate.");
    placed[3].center = {0, 0, -1};
    placed[4].center = {0, 0, 1};
    placed[4].kind = m::Component::softmetal_shaft;
    const auto mirrored = a::inspect_collector(placed, face);
    check(mirrored.status == a::Status::ready && mirrored.collector &&
          mirrored.collector->receiver_center == g::Point{0, 0, -1} &&
          mirrored.collector->shaft_center == g::Point{0, 0, 1} &&
          mirrored.collector->shaft_material == m::Component::softmetal_shaft,
          "A mirrored receiver and side-fed metal shaft are also accepted.");
    placed.push_back(part("second-tray", m::Component::receiver_tray, {0, 0, 1}));
    check(a::inspect_collector(placed, face).status == a::Status::invalid_input,
          "Two components cannot claim the same world-grid location.");
    placed.back().center = {0, 0, -2};
    placed.push_back(part("back-shaft", m::Component::wooden_shaft, {1, 0, 0}));
    check(a::inspect_collector(placed, face).status == a::Status::ambiguous,
          "Two complete drive routes require an explicit choice instead of a hidden winner.");
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
    check(a::inspect_collector(placed, face).status == a::Status::missing_shaft,
          "A distant shaft does not drive a collector merely because it exists.");
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

std::vector<a::Part> press_parts(g::Point frame = {0, 0, 0}, g::Point drive = {1, 0, 0}) {
    const auto above = [&](g::Integer y) { return g::Point{frame[0], frame[1] + y, frame[2]}; };
    return {
        part("press-frame", m::Component::wooden_frame, frame),
        part("press-anvil", m::Component::anvil, above(1)),
        part("press-ram", m::Component::ram_face, above(2)),
        part("press-guide", m::Component::sliding_guide, above(3)),
        part("press-mount", m::Component::tool_mount, above(4)),
        part("press-shaft", m::Component::wooden_shaft,
             {frame[0] + drive[0], frame[1] + 4, frame[2] + drive[2]}),
        part("press-cog", m::Component::wooden_cog,
             {frame[0] + 2 * drive[0], frame[1] + 4, frame[2] + 2 * drive[2]}),
    };
}

void press_arrangements_and_clearance() {
    auto placed = press_parts();
    const auto first = a::inspect_press(placed, {0, 0, 0});
    check(first.status == a::PressStatus::ready && first.press &&
          first.press->frame == "press-frame" && first.press->anvil == "press-anvil" &&
          first.press->ram == "press-ram" && first.press->guide == "press-guide" &&
          first.press->mount == "press-mount" && first.press->shaft == "press-shaft" &&
          first.press->drive_cog == "press-cog" && first.press->work_center == g::Point{0, 1, 0} &&
          first.press->open_feeds.size() == 4,
          "Seven separately placed parts expose one press and four open lower feed directions.");
    const g::Point elevated{8, 4, 12};
    placed = press_parts(elevated, {0, 0, -1});
    placed[5].kind = m::Component::softmetal_shaft;
    placed[6].kind = m::Component::softmetal_cog;
    placed.push_back(part("feed-obstacle", m::Component::wooden_shaft, {9, 5, 12}));
    const auto alternate = a::inspect_press(placed, elevated);
    check(alternate.status == a::PressStatus::ready && alternate.press &&
          alternate.press->shaft_center == g::Point{8, 8, 11} &&
          alternate.press->cog_center == g::Point{8, 8, 10} &&
          alternate.press->shaft_material == m::Component::softmetal_shaft &&
          alternate.press->cog_material == m::Component::softmetal_cog &&
          alternate.press->open_feeds.size() == 2 &&
          alternate.press->open_feeds.front().entry == g::Point{8, 5, 13},
          "A raised metal drive on another side still admits the clear cross-axis feed pair.");
    placed.push_back(part("north-block", m::Component::receiver_tray, {8, 5, 13}));
    placed.push_back(part("south-block", m::Component::receiver_tray, {8, 5, 11}));
    check(a::inspect_press(placed, elevated).status == a::PressStatus::blocked_feed,
          "Every feed and exit pair is blocked by actual placed parts.");
    placed.pop_back(); placed.pop_back(); placed.pop_back();
    placed.push_back(part("other-shaft", m::Component::wooden_shaft, {7, 8, 12}));
    placed.push_back(part("other-cog", m::Component::wooden_cog, {6, 8, 12}));
    check(a::inspect_press(placed, elevated).status == a::PressStatus::ambiguous,
          "Two complete drive candidates cannot silently choose an output machine.");
}

void press_missing_and_invalid_parts() {
    const g::Point center{0, 0, 0};
    auto placed = press_parts();
    placed.erase(placed.begin());
    check(a::inspect_press(placed, center).status == a::PressStatus::missing_frame,
          "No nearby anvil substitutes for a load-bearing frame.");
    placed = press_parts(); placed.erase(placed.begin() + 1);
    check(a::inspect_press(placed, center).status == a::PressStatus::missing_anvil,
          "A ram without a work support cannot form a press.");
    placed = press_parts(); placed[2].center = {0, 5, 0};
    check(a::inspect_press(placed, center).status == a::PressStatus::missing_ram,
          "A face at the wrong height cannot contact the anvil.");
    placed = press_parts(); placed.erase(placed.begin() + 3);
    check(a::inspect_press(placed, center).status == a::PressStatus::missing_guide,
          "A free ram without its sliding guide is incomplete.");
    placed = press_parts(); placed.erase(placed.begin() + 4);
    check(a::inspect_press(placed, center).status == a::PressStatus::missing_mount,
          "A bare guide without its support mount is incomplete.");
    placed = press_parts(); placed.erase(placed.begin() + 5);
    check(a::inspect_press(placed, center).status == a::PressStatus::missing_shaft,
          "A drive cog without its adjacent shaft is incomplete.");
    placed = press_parts(); placed.erase(placed.begin() + 6);
    check(a::inspect_press(placed, center).status == a::PressStatus::missing_cog,
          "A shaft without a drive cog is incomplete.");
    placed = press_parts(); placed[6].id = placed[5].id;
    check(a::inspect_press(placed, center).status == a::PressStatus::invalid_input,
          "One identity cannot be both shaft and cog.");
    placed = press_parts(); placed[6].center = placed[5].center;
    check(a::inspect_press(placed, center).status == a::PressStatus::invalid_input &&
          a::inspect_press(placed, {1, 0, 0}).status == a::PressStatus::invalid_input,
          "Duplicate centers and off-grid press origins refuse before recognition.");
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
        placed.push_back({name + "-frame", m::Component::wooden_frame, {x, 8, 16}, 1});
        placed.push_back({name + "-anvil", m::Component::anvil, {x, 9, 16}, 1});
        placed.push_back({name + "-ram", m::Component::ram_face, {x, 10, 16}, 1});
        placed.push_back({name + "-guide", m::Component::sliding_guide, {x, 11, 16}, 1});
        placed.push_back({name + "-mount", m::Component::tool_mount, {x, 12, 16}, 1});
        placed.push_back({name + "-shaft", m::Component::wooden_shaft, {x + 1, 12, 16}, 1});
        placed.push_back({name + "-cog", m::Component::wooden_cog, {x + 2, 12, 16}, 1});
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
        const auto current = indexed.inspect_press(center);
        const auto direct = a::inspect_press(placed, center);
        check(current.status == a::PressStatus::ready && current.press && direct.press &&
              current.status == direct.status &&
              current.press == direct.press && current.press->frame ==
                  "press-" + std::to_string(index) + "-frame",
              "The shared index keeps each press drive, work point and feed routes separate.");
    }
    std::array<double, 20> direct_ms{}, indexed_ms{};
    for (std::size_t sample = 0; sample < direct_ms.size(); ++sample) {
        std::size_t direct_count = 0, indexed_count = 0;
        const auto direct_start = std::chrono::steady_clock::now();
        for (const auto& face : faces)
            direct_count += a::inspect_collector(placed, face).status == a::Status::ready;
        for (int index = 0; index < 100; ++index)
            direct_count += a::inspect_press(placed, {index * 8, 8, 16}).status == a::PressStatus::ready;
        const auto indexed_start = std::chrono::steady_clock::now();
        const a::Layout snapshot(placed);
        for (const auto& face : faces)
            indexed_count += snapshot.inspect_collector(face).status == a::Status::ready;
        for (int index = 0; index < 100; ++index)
            indexed_count += snapshot.inspect_press({index * 8, 8, 16}).status == a::PressStatus::ready;
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
    placed.back().id = placed.front().id;
    const a::Layout invalid(placed);
    check(!invalid.valid() && invalid.inspect_collector(faces.front()).status == a::Status::invalid_input &&
          invalid.inspect_press({0, 8, 16}).status == a::PressStatus::invalid_input,
          "One duplicate identity invalidates the complete shared layout before either inspection.");
}
}  // namespace

int main() {
    try {
        west_face_and_alternate_routes();
        raised_rotated_face_and_missing_parts();
        malformed_and_ambiguous_input();
        press_arrangements_and_clearance();
        press_missing_and_invalid_parts();
        indexed_independent_assemblies();
        std::cout << "assembly_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "assembly_test: " << error.what() << '\n';
        return 1;
    }
}
