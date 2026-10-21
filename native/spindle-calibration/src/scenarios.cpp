#include "factory/spindle_scenarios.hpp"

#include <algorithm>
#include <array>

namespace factory::spindle_scenarios {
namespace r = repair_scenarios;
namespace s = stationary;
namespace g = mechanics;
namespace {
constexpr std::array<r::Definition, 1> definitions{{
    {"spindle", "The line runs, but the spindle is wrong",
     "Retrieve four plates with the connected line's spindle calibrated to signed rate +2/1.",
     "A coaxial shortcut and small-cog mesh reverse the line at the wrong speed. Bridge the two axial planes with a diagonal small-to-large mesh and one-tile shaft to reach the signed target. The target and recipe duration are fixture specifications; gearing changes processing speed, not yield."},
}};
void add(r::Scenario& scenario, const std::string& id, s::Role role, g::Point center, g::Integer teeth = 0, g::Integer span = 0) {
    const auto kind = role == s::Role::gear ? g::Kind::gear : role == s::Role::shaft ? g::Kind::shaft : g::Kind::hub;
    scenario.seed.topology.parts.push_back({{id, kind, center, g::Axis::z, teeth, span}, 1, role});
}
}  // namespace

const r::Definition& definition() noexcept { return definitions.front(); }
std::span<const r::Definition> catalogue() noexcept { return definitions; }

std::optional<r::Scenario> make(std::string_view id) {
    if (id != definition().id) return std::nullopt;
    auto result = r::make("link");
    if (!result) return std::nullopt;
    result->definition = &definition();
    result->profile.waterwheel_rate = {1, 1};
    // At the required double-speed spindle, a four-unit recipe retains a
    // genuine partial-work cut for the continuation and recovery challenge.
    result->profile.material.cycle_ticks = 4;
    auto& topology = result->seed.topology;
    topology.parts.clear(); topology.sources.clear();
    add(*result, "wheel", s::Role::waterwheel, {0, 0, -12});
    add(*result, "gear-input", s::Role::gear, {0, 0, -8}, 4);
    add(*result, "shaft-output", s::Role::shaft, {4, 0, -4}, 0, 2);
    add(*result, "gear-output", s::Role::gear, {4, 0, 0}, 2);
    add(*result, "collector", s::Role::collector, {4, 0, 4});
    add(*result, "gear-belt", s::Role::gear, {8, 0, 0}, 2);
    add(*result, "gear-press", s::Role::gear, {12, 0, 0}, 2);
    add(*result, "belt", s::Role::belt, {8, 0, 4});
    add(*result, "processor", s::Role::processor, {12, 0, 4});
    topology.sources = {{"wheel", result->profile.waterwheel_rate}};
    topology.material_links = {{{"collector", 1}, {"belt", 1}}, {{"belt", 1}, {"processor", 1}}};
    auto& kit = result->seed.kits.at("P");
    kit.clear();
    kit.emplace(s::PartSpec{s::Role::gear, 2, 0}, 2);
    kit.emplace(s::PartSpec{s::Role::shaft, 0, 2}, 1);
    result->profile.finite_parts.clear(); result->seed.issued_entities.clear();
    for (const auto& part : topology.parts) {
        ++result->profile.finite_parts[{part.role, part.geometry.teeth, part.geometry.half_span}];
        result->seed.issued_entities.emplace(part.geometry.id, part.generation);
    }
    for (const auto& [actor, carried] : result->seed.kits) {
        (void)actor;
        for (const auto& [spec, count] : carried) result->profile.finite_parts[spec] += count;
    }
    return result;
}

const char* mode_name(Mode mode) noexcept {
    switch (mode) {
        case Mode::invalid: return "invalid";
        case Mode::drive_off: return "drive_off";
        case Mode::incomplete_line: return "incomplete_line";
        case Mode::wrong_rate: return "wrong_rate";
        case Mode::calibrated: return "calibrated";
    }
    return "invalid";
}

Progress inspect(const world::State& state, const std::string& actor) {
    Progress result;
    if (const auto cargo = state.material.cargo.find(actor); cargo != state.material.cargo.end()) {
        result.known_actor = true; result.products = cargo->second.products;
    }
    const auto power = s::power_view(state.topology);
    if (!power.mechanical.accepted()) return result;
    if (!state.topology.drive_enabled) { result.mode = Mode::drive_off; return result; }
    const auto processor = std::find_if(state.topology.parts.begin(), state.topology.parts.end(),
        [](const auto& part) { return part.role == s::Role::processor; });
    if (processor != state.topology.parts.end()) {
        const auto motion = power.mechanical.motion.find(processor->geometry.id);
        if (motion != power.mechanical.motion.end()) result.rate = motion->second.rate;
    }
    const auto machines = world::machine_power(state.topology);
    const auto path = world::material_path(state.topology);
    if (!machines.collector || !machines.belt || !machines.processor || !path.collector_to_belt || !path.belt_to_processor) {
        result.mode = Mode::incomplete_line; return result;
    }
    result.mode = result.rate == required_rate ? Mode::calibrated : Mode::wrong_rate;
    return result;
}
}  // namespace factory::spindle_scenarios
