#include "factory/co_drive_scenarios.hpp"

#include <algorithm>
#include <array>

namespace factory::co_drive_scenarios {
namespace r = repair_scenarios;
namespace s = stationary;
namespace g = mechanics;
namespace {
constexpr std::array<r::Definition, 1> definitions{{
    {"co-drive", "Two wheels, one disagreeing drive",
     "Carry four plates after resolving the source conflict and driving the belt toward the press.",
     "The adjacent large cogs reverse one equal-rate source. Retire the left wheel, or move it one tile left, fit the carried small cogs and reuse a large cog above them. Retiring the right wheel alone reverses the belt."},
}};
void add(r::Scenario& scenario, const std::string& id, s::Role role, g::Point point, g::Integer teeth = 0, g::Integer span = 0) {
    const auto kind = role == s::Role::gear ? g::Kind::gear : role == s::Role::shaft ? g::Kind::shaft : g::Kind::hub;
    scenario.seed.topology.parts.push_back({{id, kind, point, g::Axis::z, teeth, span}, 1, role});
}
}  // namespace

const r::Definition& definition() noexcept { return definitions.front(); }
std::span<const r::Definition> catalogue() noexcept { return definitions; }

std::optional<r::Scenario> make(std::string_view id) {
    if (id != definition().id) return std::nullopt;
    auto result = r::make("link");  // Authored startup data, before any World exists.
    if (!result) return std::nullopt;
    result->definition = &definition();
    auto& topology = result->seed.topology;
    topology.parts.clear(); topology.sources.clear();
    add(*result, "wheel-left", s::Role::waterwheel, {-4, 0, -4});
    add(*result, "wheel-right", s::Role::waterwheel, {0, 0, -4});
    add(*result, "gear-left", s::Role::gear, {-4, 0, 0}, 4);
    add(*result, "gear-right", s::Role::gear, {0, 0, 0}, 4);
    add(*result, "collector", s::Role::collector, {0, 0, 4});
    add(*result, "belt", s::Role::belt, {0, 0, 8});
    add(*result, "processor", s::Role::processor, {0, 0, 12});
    topology.sources = {{"wheel-left", result->profile.waterwheel_rate}, {"wheel-right", result->profile.waterwheel_rate}};
    topology.material_links = {{{"collector", 1}, {"belt", 1}}, {{"belt", 1}, {"processor", 1}}};
    result->seed.kits.at("P").clear();
    result->seed.kits.at("P").emplace(s::PartSpec{s::Role::gear, 2, 0}, 2);
    // Declare every original part once. Native World preserves these totals
    // through actual placement, refund and fresh identity allocation thereafter.
    result->profile.finite_parts.clear(); result->seed.issued_entities.clear();
    for (const auto& part : topology.parts) {
        ++result->profile.finite_parts[{part.role, part.geometry.teeth, part.geometry.half_span}];
        result->seed.issued_entities.emplace(part.geometry.id, part.generation);
    }
    for (const auto& [actor, kit] : result->seed.kits) {
        (void)actor;
        for (const auto& [spec, quantity] : kit) result->profile.finite_parts[spec] += quantity;
    }
    return result;
}

const char* mode_name(Mode mode) noexcept {
    switch (mode) {
        case Mode::invalid: return "invalid";
        case Mode::drive_off: return "drive_off";
        case Mode::stalled: return "stalled";
        case Mode::incomplete_line: return "incomplete_line";
        case Mode::choose_source: return "choose_source";
        case Mode::isolated: return "isolated";
        case Mode::co_driven: return "co_driven";
    }
    return "invalid";
}

Progress inspect(const world::State& state, const std::string& actor) {
    Progress result;
    result.sources = state.topology.sources.size();
    if (const auto cargo = state.material.cargo.find(actor); cargo != state.material.cargo.end()) {
        result.known_actor = true; result.products = cargo->second.products;
    }
    const auto power = s::power_view(state.topology);
    if (!power.mechanical.accepted()) return result;
    if (!state.topology.drive_enabled) { result.mode = Mode::drive_off; return result; }
    const auto machines = world::machine_power(state.topology);
    result.belt_forward = machines.belt && machines.belt_forward;
    if (!machines.collector || !machines.belt || !machines.processor) {
        const bool stalled = std::any_of(power.mechanical.components.begin(), power.mechanical.components.end(),
            [](const auto& component) { return component.state == g::MotionState::stalled; });
        result.mode = stalled ? Mode::stalled : Mode::incomplete_line;
        return result;
    }
    if (result.sources == 1) { result.mode = Mode::isolated; return result; }
    if (result.sources != 2) return result;
    const auto processor = std::find_if(state.topology.parts.begin(), state.topology.parts.end(),
        [](const auto& part) { return part.role == s::Role::processor; });
    if (processor == state.topology.parts.end()) return result;
    for (const auto& component : power.mechanical.components) {
        const auto contains = [&](const std::string& id) {
            return std::find(component.parts.begin(), component.parts.end(), id) != component.parts.end();
        };
        if (contains(processor->geometry.id) && contains(state.topology.sources[0].hub) && contains(state.topology.sources[1].hub)) {
            result.mode = Mode::co_driven; return result;
        }
    }
    result.mode = Mode::choose_source;
    return result;
}
}  // namespace factory::co_drive_scenarios
