#include "factory/assembly.hpp"

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
}  // namespace

int main() {
    try {
        west_face_and_alternate_routes();
        raised_rotated_face_and_missing_parts();
        malformed_and_ambiguous_input();
        std::cout << "assembly_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "assembly_test: " << error.what() << '\n';
        return 1;
    }
}
