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

void guided_press_without_structure() {
    const auto parts_at = [](g::Point center, g::Point drive) {
        return std::vector<a::Part>{
            part("anvil", m::Component::anvil, center),
            part("ram", m::Component::ram_face,
                 {center[0], center[1] + 1, center[2]}),
            part("guide", m::Component::sliding_guide,
                 {center[0], center[1] + 3, center[2]}),
            part("shaft", m::Component::wooden_shaft,
                 {center[0] + drive[0], center[1] + 4, center[2] + drive[2]}),
            part("cog", m::Component::wooden_cog,
                 {center[0] + 2 * drive[0], center[1] + 4, center[2] + 2 * drive[2]}),
        };
    };
    const g::Point ground{0, 0, 0};
    auto placed = parts_at(ground, {1, 0, 0});
    const auto first = a::inspect_guided_press(placed, ground);
    check(first.status == a::PressStatus::ready && first.press &&
          first.press->anvil == "anvil" && first.press->ram == "ram" &&
          first.press->guide == "guide" && first.press->shaft == "shaft" &&
          first.press->drive_cog == "cog" && first.press->open_feeds.size() == 4,
          "Five independently placed working parts form a press without a frame or mount.");
    placed.push_back(part("offcut-tray", m::Component::receiver_tray, {0, 0, 1}));
    const auto with_tray = a::inspect_guided_press(placed, ground);
    check(with_tray.status == a::PressStatus::ready && with_tray.press &&
          with_tray.press->offcut_receiver == g::Point{0, 0, 1} &&
          with_tray.press->open_feeds.size() == 2,
          "One side tray catches the shear outlet while the opposite feed remains open.");
    placed.push_back(part("second-offcut-tray", m::Component::receiver_tray, {0, 0, -1}));
    const auto ambiguous_trays = a::inspect_guided_press(placed, ground);
    check(ambiguous_trays.status == a::PressStatus::ready && ambiguous_trays.press &&
          !ambiguous_trays.press->offcut_receiver,
          "Two side trays cannot silently select one offcut destination.");
    const g::Point raised{8, 4, 12};
    placed = parts_at(raised, {0, 0, -1});
    placed[3].kind = m::Component::softmetal_shaft;
    placed[4].kind = m::Component::softmetal_cog;
    const a::Layout layout(placed);
    const auto elevated = layout.inspect_guided_press(raised);
    check(elevated.status == a::PressStatus::ready && elevated.press &&
          elevated.press->work_center == raised &&
          elevated.press->shaft_center == g::Point{8, 8, 11} &&
          elevated.press->cog_material == m::Component::softmetal_cog,
          "The same anvil-centered rule admits raised, rotated and metal drive geometry.");
    placed.push_back(part("stroke-obstacle", m::Component::receiver_tray, {8, 6, 12}));
    check(a::inspect_guided_press(placed, raised).status == a::PressStatus::blocked_stroke,
          "A placed part between the raised ram and guide blocks their real stroke.");
    placed.pop_back();
    placed[1].center[1] += 2;
    check(a::inspect_guided_press(placed, raised).status == a::PressStatus::invalid_input,
          "A ram cannot occupy the guide's grid position.");
    placed[1].center = {8, 6, 12};
    check(a::inspect_guided_press(placed, raised).status == a::PressStatus::missing_ram,
          "A misaligned ram cannot claim workpiece contact.");
    placed[1].center = {8, 5, 12};
    placed.erase(placed.begin() + 2);
    check(a::inspect_guided_press(placed, raised).status == a::PressStatus::missing_guide,
          "A free ram requires a placed stroke guide.");
    placed = parts_at(ground, {1, 0, 0});
    placed.push_back(part("west-shaft", m::Component::wooden_shaft, {-1, 4, 0}));
    placed.push_back(part("west-cog", m::Component::wooden_cog, {-2, 4, 0}));
    check(a::inspect_guided_press(placed, ground).status == a::PressStatus::ambiguous,
          "Two complete drives require an explicit selection.");
    placed.pop_back(); placed.pop_back();
    for (const auto& direction : std::array<g::Point, 4>{{{1, 0, 0}, {-1, 0, 0},
                                                         {0, 0, 1}, {0, 0, -1}}}) {
        const auto axis = direction[0] != 0 ? "x" : "z";
        const auto sign = direction[0] + direction[2] > 0 ? "plus" : "minus";
        placed.push_back({std::string(axis) + sign, m::Component::receiver_tray,
                          {direction[0], 0, direction[2]}, 1});
    }
    check(a::inspect_guided_press(placed, ground).status == a::PressStatus::blocked_feed,
          "Obstructed opposing feed and exit faces cannot be used.");
    placed = parts_at(ground, {1, 0, 0});
    placed.erase(placed.begin());
    check(a::inspect_guided_press(placed, ground).status == a::PressStatus::missing_anvil,
          "A guided ram cannot form stock without an anvil.");
    check(a::inspect_guided_press(parts_at(ground, {1, 0, 0}), {0, 1, 0}).status ==
          a::PressStatus::invalid_input,
          "The work center follows the shared four-step world height grid.");
}

void broad_press_from_repeated_work_faces() {
    const auto parts_at = [](g::Point origin, bool drive_from_x_edges) {
        std::vector<a::Part> placed;
        for (std::size_t index = 0; index < 4; ++index) {
            const g::Point cell{origin[0] + static_cast<g::Integer>(index % 2) * 4,
                origin[1], origin[2] + static_cast<g::Integer>(index / 2) * 4};
            placed.push_back({"anvil" + std::to_string(index), m::Component::anvil, cell, 1});
            placed.push_back({"ram" + std::to_string(index), m::Component::ram_face,
                {cell[0], cell[1] + 1, cell[2]}, 1});
            placed.push_back({"guide" + std::to_string(index), m::Component::sliding_guide,
                {cell[0], cell[1] + 3, cell[2]}, 1});
        }
        for (std::size_t index = 0; index < 4; ++index) {
            const auto& cell = placed[index * 3].center;
            const g::Point outward = drive_from_x_edges ?
                g::Point{index % 2 == 0 ? -1 : 1, 0, 0} :
                g::Point{0, 0, index / 2 == 0 ? -1 : 1};
            placed.push_back({"shaft" + std::to_string(index), m::Component::wooden_shaft,
                {cell[0] + outward[0], cell[1] + 4, cell[2] + outward[2]}, 1});
            placed.push_back({"cog" + std::to_string(index), m::Component::wooden_cog,
                {cell[0] + 2 * outward[0], cell[1] + 4, cell[2] + 2 * outward[2]}, 1});
        }
        return placed;
    };
    const g::Point ground{0, 0, 0};
    auto placed = parts_at(ground, true);
    const auto first = a::inspect_broad_press(placed, ground);
    check(first.status == a::BroadPressStatus::ready && first.press &&
          first.press->origin == ground &&
          first.press->work_centers == std::array<g::Point, 4>{{{0, 0, 0}, {4, 0, 0},
              {0, 0, 4}, {4, 0, 4}}},
          "Four repeated anvil and ram cells form one frame-free broad work area.");
    for (std::size_t index = 0; index < 4; ++index)
        check(first.press->anvils[index] == "anvil" + std::to_string(index) &&
              first.press->rams[index] == "ram" + std::to_string(index) &&
              first.press->guides[index] == "guide" + std::to_string(index) &&
              first.press->shafts[index] == "shaft" + std::to_string(index) &&
              first.press->drive_cogs[index] == "cog" + std::to_string(index),
              "Every broad work face retains its own placed contacts and exterior drive.");

    const g::Point raised{8, 4, 12};
    placed = parts_at(raised, false);
    placed[18].kind = m::Component::softmetal_shaft;
    placed[19].kind = m::Component::softmetal_cog;
    const a::Layout layout(placed);
    const auto alternate = layout.inspect_broad_press(raised);
    check(alternate.status == a::BroadPressStatus::ready && alternate.press &&
          alternate.press->shaft_centers[3] == g::Point{12, 8, 17} &&
          alternate.press->cog_centers[3] == g::Point{12, 8, 18} &&
          alternate.press->shaft_materials[3] == m::Component::softmetal_shaft,
          "Raised north/south edge drives use the same world grid and accept metal parts.");
    check(a::inspect_broad_press(placed, {9, 4, 12}).status ==
          a::BroadPressStatus::invalid_input,
          "A broad area cannot invent a shifted local grid origin.");
    placed.erase(placed.begin() + 9);
    check(a::inspect_broad_press(placed, raised).status == a::BroadPressStatus::missing_anvil,
          "Missing one support tile refuses the entire broad workpiece face.");
    placed = parts_at(raised, false);
    placed[10].center[0] += 1;
    check(a::inspect_broad_press(placed, raised).status == a::BroadPressStatus::missing_ram,
          "One shifted ram cannot claim matching broad contact.");
    placed = parts_at(raised, false);
    placed.erase(placed.begin() + 11);
    check(a::inspect_broad_press(placed, raised).status == a::BroadPressStatus::missing_guide,
          "Every floating ram needs its own stroke guide.");
    placed = parts_at(raised, false);
    placed.push_back(part("stroke-obstacle", m::Component::receiver_tray, {12, 6, 16}));
    check(a::inspect_broad_press(placed, raised).status == a::BroadPressStatus::blocked_stroke,
          "A component in any swept cell blocks the shared stroke.");
    placed = parts_at(ground, true);
    placed.pop_back();
    check(a::inspect_broad_press(placed, ground).status == a::BroadPressStatus::missing_cog,
          "Each separate ram needs a complete shaft and cog drive.");
    placed = parts_at(ground, true);
    placed.erase(placed.begin() + 14);
    placed.erase(placed.begin() + 14);
    check(a::inspect_broad_press(placed, ground).status == a::BroadPressStatus::missing_shaft,
          "Reclaiming one pad's drive makes the broad area incomplete without altering other parts.");
    placed = parts_at(ground, true);
    placed.push_back(part("other-shaft", m::Component::wooden_shaft, {0, 4, -1}));
    placed.push_back(part("other-cog", m::Component::wooden_cog, {0, 4, -2}));
    check(a::inspect_broad_press(placed, ground).status == a::BroadPressStatus::ambiguous,
          "Two complete edge drives at one pad require an explicit selection.");
    placed = parts_at(ground, true);
    placed.resize(12);
    placed.push_back(part("inner-shaft", m::Component::wooden_shaft, {1, 4, 0}));
    placed.push_back(part("inner-cog", m::Component::wooden_cog, {2, 4, 0}));
    check(a::inspect_broad_press(placed, ground).status == a::BroadPressStatus::missing_shaft,
          "An interior drive attachment cannot replace four exterior connections.");
    placed = parts_at(ground, true);
    placed[1].id = placed.front().id;
    check(a::inspect_broad_press(placed, ground).status == a::BroadPressStatus::invalid_input,
          "Repeated parts still need distinct issued identities.");
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
        guided_press_without_structure();
        broad_press_from_repeated_work_faces();
        indexed_independent_assemblies();
        std::cout << "assembly_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "assembly_test: " << error.what() << '\n';
        return 1;
    }
}
