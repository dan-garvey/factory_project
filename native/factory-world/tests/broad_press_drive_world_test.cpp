#include "factory/world.hpp"

#include <array>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
namespace a = factory::assembly;
namespace g = factory::mechanics;
namespace m = factory::materials;
namespace s = factory::stationary;
namespace w = factory::world;

int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

std::vector<a::Part> parts_at(g::Point origin, bool z_edges = false,
        bool mixed_edges = false) {
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
        const bool z = z_edges || (mixed_edges && index == 3);
        const g::Point outward = z ?
            g::Point{0, 0, index / 2 == 0 ? -1 : 1} :
            g::Point{index % 2 == 0 ? -1 : 1, 0, 0};
        placed.push_back({"shaft" + std::to_string(index), m::Component::wooden_shaft,
            {cell[0] + outward[0], cell[1] + 4, cell[2] + outward[2]}, 1});
        placed.push_back({"cog" + std::to_string(index), m::Component::wooden_cog,
            {cell[0] + 2 * outward[0], cell[1] + 4, cell[2] + 2 * outward[2]}, 1});
    }
    return placed;
}

a::BroadPress press_at(g::Point origin, bool z_edges = false,
        bool mixed_edges = false) {
    const auto inspected = a::inspect_broad_press(parts_at(origin, z_edges, mixed_edges), origin);
    check(inspected.status == a::BroadPressStatus::ready && inspected.press.has_value(),
        "The repeated physical parts must provide one four-cell geometry candidate.");
    return *inspected.press;
}

w::DrivePower power_for(const a::BroadPress& press, g::Rate rate = {2, 1}) {
    w::DrivePower power;
    g::Component coupled;
    coupled.state = g::MotionState::rotating;
    for (std::size_t index = 0; index < press.shafts.size(); ++index) {
        const auto& id = press.shafts[index];
        const bool x_axis = press.shaft_centers[index][0] != press.cog_centers[index][0];
        const int winding = (x_axis ? index / 2 : index % 2) == 0 ? 1 : -1;
        coupled.parts.push_back(id);
        power.mechanical.motion.emplace(id, g::Motion{g::MotionState::rotating,
            {rate.numerator * winding, rate.denominator}});
    }
    power.mechanical.components.push_back(std::move(coupled));
    return power;
}

void signed_coupled_drive() {
    const auto ground = press_at({0, 0, 0});
    auto power = power_for(ground);
    const auto ready = w::BroadPressDriveIndex(power).inspect(ground);
    check(ready.status == w::BroadPressDriveStatus::ready &&
          ready.stroke_rate == g::Rate{2, 1} &&
          ready.pad_winding == std::array<int, 4>{1, 1, -1, -1},
        "Four mirrored same-axis cams in one component have one signed broad stroke rate.");
    power.mechanical.motion.at(ground.shafts[3]).rate = {-4, 2};
    check(w::BroadPressDriveIndex(power).inspect(ground).status ==
          w::BroadPressDriveStatus::ready,
        "Equivalent rational shaft rates remain synchronized without rounded floats.");
    power.mechanical.motion.at(ground.shafts[3]).rate = {2, 1};
    check(w::BroadPressDriveIndex(power).inspect(ground).status ==
          w::BroadPressDriveStatus::mismatched_rate,
        "A reversed pad cannot tear one broad sheet with an opposite signed stroke.");
    power.mechanical.motion.at(ground.shafts[3]).rate = {-3, 1};
    check(w::BroadPressDriveIndex(power).inspect(ground).status ==
          w::BroadPressDriveStatus::mismatched_rate,
        "A faster pad cannot complete the same broad stroke at a different rate.");
    power.mechanical.motion.at(ground.shafts[3]).rate = {-2, 1};
    power.mechanical.components.front().parts.pop_back();
    power.mechanical.components.push_back({{ground.shafts[3]}, g::MotionState::rotating});
    check(w::BroadPressDriveIndex(power).inspect(ground).status ==
          w::BroadPressDriveStatus::disconnected,
        "Four independent equal-speed drives do not certify one constrained crosshead.");
}

void stopped_or_incompatible_drive() {
    const auto raised = press_at({8, 4, 12}, true);
    auto power = power_for(raised, {-1, 1});
    const auto raised_drive = w::BroadPressDriveIndex(power).inspect(raised);
    check(raised_drive.status == w::BroadPressDriveStatus::ready &&
          raised_drive.stroke_rate == g::Rate{-1, 1} &&
          raised_drive.pad_winding == std::array<int, 4>{1, -1, 1, -1},
        "A raised north-south arrangement uses the common grid and signed rate.");
    power.mechanical.motion.at(raised.shafts[2]) = {g::MotionState::stopped, {0, 1}};
    check(w::BroadPressDriveIndex(power).inspect(raised).status ==
          w::BroadPressDriveStatus::stopped,
        "One stopped pad blocks the whole broad stroke.");
    power.mechanical.motion.at(raised.shafts[2]) = {g::MotionState::rotating, {-1, 1}};
    power.load.emplace(raised.shafts[1], w::NetworkLoad{8, 12, true, raised.shafts[1]});
    check(w::BroadPressDriveIndex(power).inspect(raised).status ==
          w::BroadPressDriveStatus::stalled,
        "An overloaded pad cannot present a ready broad press.");
    power.load.clear();
    power.mechanical.motion.erase(raised.shafts[0]);
    check(w::BroadPressDriveIndex(power).inspect(raised).status ==
          w::BroadPressDriveStatus::unpowered,
        "A missing live shaft motion cannot be inferred from the other three.");
    const auto mixed = press_at({0, 0, 0}, false, true);
    power = power_for(mixed);
    check(w::BroadPressDriveIndex(power).inspect(mixed).status ==
          w::BroadPressDriveStatus::incompatible_axis,
        "Orthogonal cam axes need an explicit keyed conversion before one stroke.");
}

void actual_unpowered_topology() {
    const auto parts = parts_at({0, 0, 0});
    const auto press = press_at({0, 0, 0});
    w::Profile profile;
    w::State state;
    for (const auto& part : parts)
        state.placed_components.emplace(part.id,
            w::PlacedComponent{part.kind, part.center, part.generation});
    const auto observed = w::drive_power(profile, state);
    check(observed.mechanical.accepted() &&
          w::BroadPressDriveIndex(observed).inspect(press).status ==
              w::BroadPressDriveStatus::unpowered,
        "Real World power derivation refuses a complete but unpowered four-pad geometry.");
}

void actual_powered_world_topology() {
    auto parts = parts_at({0, 0, 0});
    for (auto& part : parts)
        if (part.kind == m::Component::wooden_cog)
            part.kind = m::Component::softmetal_cog;
        else if (part.kind == m::Component::wooden_shaft)
            part.kind = m::Component::softmetal_shaft;
    const auto inspected = a::inspect_broad_press(parts, {0, 0, 0});
    check(inspected.press.has_value(),
        "Four softmetal exterior cogs preserve the native broad geometry.");
    const auto& press = *inspected.press;
    w::Profile profile;
    w::State state;
    for (const auto& part : parts)
        state.placed_components.emplace(part.id,
            w::PlacedComponent{part.kind, part.center, part.generation});
    state.topology.drive_enabled = true;
    state.topology.parts = {
        {{"broad-wheel", g::Kind::hub, {-4, 4, 0}, g::Axis::x, 0, 0},
            1, s::Role::waterwheel},
        {{"front-cross-shaft", g::Kind::shaft, {2, 4, 0}, g::Axis::x, 0, 2},
            1, s::Role::shaft},
    };
    state.topology.sources = {{"broad-wheel", {1, 2}}};
    const auto power = w::drive_power(profile, state);
    check(power.mechanical.accepted(),
        "The World mechanical graph accepts the complete powered four-pad topology.");
    const auto observed = w::BroadPressDriveIndex(power).inspect(press);
    check(observed.status == w::BroadPressDriveStatus::ready &&
          observed.stroke_rate == g::Rate{1, 2} &&
          !power.load.at(press.shafts[0]).overloaded,
        "The actual World source, material ratings and four guided heads produce one signed stroke.");
    state.topology.sources.front().rate = {-1, 2};
    const auto reversed = w::BroadPressDriveIndex(w::drive_power(profile, state)).inspect(press);
    check(reversed.status == w::BroadPressDriveStatus::ready &&
          reversed.stroke_rate == g::Rate{-1, 2},
        "Reversing the actual source reverses the common stroke without breaking pad coupling.");
    state.topology.sources.front().rate = {1, 2};
    state.placed_components.at(press.shafts[0]).kind = m::Component::wooden_shaft;
    const auto overloaded = w::BroadPressDriveIndex(w::drive_power(profile, state)).inspect(press);
    check(overloaded.status == w::BroadPressDriveStatus::stalled,
        "One real wooden shaft rating stalls the otherwise complete four-head load.");
    state.placed_components.at(press.shafts[0]).kind = m::Component::softmetal_shaft;
    state.topology.drive_enabled = false;
    check(w::BroadPressDriveIndex(w::drive_power(profile, state)).inspect(press).status ==
          w::BroadPressDriveStatus::stopped,
        "Disabling the real source stops the assembled broad head without changing its parts.");
}

void coupled_native_mechanical_graph() {
    const auto press = press_at({0, 0, 0});
    std::vector<g::Part> graph;
    for (std::size_t index = 0; index < press.shafts.size(); ++index) {
        const auto& work = press.work_centers[index];
        graph.push_back({press.anvils[index], g::Kind::hub,
            {work[0], work[1] + 4, work[2]}, g::Axis::x, 0, 0});
        graph.push_back({press.shafts[index], g::Kind::shaft,
            press.shaft_centers[index], g::Axis::x, 0, 1});
        graph.push_back({press.drive_cogs[index], g::Kind::gear,
            press.cog_centers[index], g::Axis::x, 2, 0});
    }
    // One actual shaft bridges the two front exterior drives. The paired
    // starter cogs mesh across each column and reverse the back-row rates.
    graph.push_back({"front-cross-shaft", g::Kind::shaft, {2, 4, 0}, g::Axis::x, 0, 2});
    const std::vector<g::Drive> source{{press.anvils[0], {2, 1}}};
    w::DrivePower power;
    power.mechanical = g::evaluate(graph, source, {}, g::SourcePolicy::overpower);
    check(power.mechanical.accepted(),
        "The actual mechanical solver accepts one connected four-pad gear train.");
    const auto observed = w::BroadPressDriveIndex(power).inspect(press);
    check(observed.status == w::BroadPressDriveStatus::ready &&
          observed.stroke_rate == g::Rate{2, 1} &&
          power.mechanical.motion.at(press.shafts[2]).rate == g::Rate{-2, 1},
        "The real meshing graph has reversed back-row rotations but one keyed stroke.");
    power.mechanical = g::evaluate(graph,
        {source.front(), {press.anvils[1], {-2, 1}}}, {}, g::SourcePolicy::prescribed);
    check(power.mechanical.accepted() &&
          w::BroadPressDriveIndex(power).inspect(press).status ==
              w::BroadPressDriveStatus::stalled,
        "Conflicting prescribed signed sources stall the entire coupled broad head.");
}
}  // namespace

int main() {
    try {
        signed_coupled_drive();
        stopped_or_incompatible_drive();
        actual_unpowered_topology();
        actual_powered_world_topology();
        coupled_native_mechanical_graph();
        std::cout << "broad_press_drive_world_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "broad_press_drive_world_test: " << error.what() << '\n';
        return 1;
    }
}
