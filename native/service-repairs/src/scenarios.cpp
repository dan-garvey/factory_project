#include "factory/service_scenarios.hpp"

#include <array>
#include <string>

namespace factory::service_scenarios {
namespace r = repair_scenarios;
namespace s = stationary;
namespace {
constexpr std::array<mechanics::Point, 2> collector_sites{{{-4, 0, 12}, {4, 0, 12}}};
constexpr std::array<mechanics::Point, 2> belt_sites{{{0, 0, 12}, {8, 0, 12}}};
constexpr std::array<mechanics::Point, 2> press_sites{{{4, 0, 12}, {12, 0, 12}}};
constexpr std::array<r::Definition, 3> definitions{{
    {"service-collector", "Move the stocked collector",
     "Rebuild the collector at a service site and retrieve four plates from the original stock.",
     "Recover its raw blank before removal. Reuse the returned machine, reconnect its material route and reinsert the blank."},
    {"service-belt", "Rebuild the blocked handoff",
     "Rebuild the belt at a service site and retrieve four plates without losing its held blank.",
     "The rebuilt belt gets a fresh name. Reconnect both handoffs to that current belt before returning its blank."},
    {"service-press", "Carry the finished billet through a rebuild",
     "Rebuild the press at a service site and retrieve four plates while retaining its original ready work.",
     "Recover the full press before removal. The carried whole lot keeps its identity and progress; insert it into the rebuilt press."},
}};
constexpr std::array<Goal, 3> goals{{
    {"collector", s::Role::collector, collector_sites},
    {"belt", s::Role::belt, belt_sites},
    {"processor", s::Role::processor, press_sites},
}};
}  // namespace

std::span<const r::Definition> catalogue() noexcept { return definitions; }

const Goal* goal(std::string_view id) noexcept {
    for (std::size_t index = 0; index < definitions.size(); ++index)
        if (definitions[index].id == id) return &goals[index];
    return nullptr;
}

std::optional<r::Scenario> make(std::string_view id) {
    for (std::size_t index = 0; index < definitions.size(); ++index) {
        if (definitions[index].id != id) continue;
        // Reuse authored startup content before creating a World. This is not
        // a failed-import fallback or a reset of a running service operation.
        auto result = r::make(id == "service-press" ? "outlet" : "link");
        if (!result) return std::nullopt;
        result->definition = &definitions[index];
        // Each service site has its own finite, already installed drive.
        // The replacement machine touches its site's shaft without sharing a
        // tile with it. Both handoff endpoints remain within fixture reach.
        result->profile.build_reach = 10;
        for (std::size_t site = 0; site < goals[index].sites.size(); ++site) {
            const auto x = goals[index].sites[site][0];
            const auto wheel = "service-wheel-" + std::to_string(site);
            const auto shaft = "service-shaft-" + std::to_string(site);
            result->seed.topology.parts.push_back({{wheel, mechanics::Kind::hub, {x, 0, 20}, mechanics::Axis::z, 0, 0}, 1, s::Role::waterwheel});
            result->seed.topology.parts.push_back({{shaft, mechanics::Kind::shaft, {x, 0, 16}, mechanics::Axis::z, 0, 2}, 1, s::Role::shaft});
            result->seed.topology.sources.push_back({wheel, result->profile.waterwheel_rate});
            result->seed.issued_entities.emplace(wheel, 1);
            result->seed.issued_entities.emplace(shaft, 1);
            ++result->profile.finite_parts[{s::Role::waterwheel, 0, 0}];
            ++result->profile.finite_parts[{s::Role::shaft, 0, 2}];
        }
        if (id == "service-collector") {
            result->seed.material.stock = {15, 1, 0, 0, 0};
            result->seed.topology.material_links = {{{"collector", 1}, {"belt", 1}}, {{"belt", 1}, {"processor", 1}}};
        } else if (id == "service-belt") {
            result->seed.material.stock = {14, 1, 1, 0, 0};
        }
        return result;
    }
    return std::nullopt;
}

bool relocated(const Goal& goal, const world::State& state) noexcept {
    const s::PlacedPart* replacement = nullptr;
    for (const auto& part : state.topology.parts) {
        if (std::string_view(part.geometry.id) == goal.original) return false;
        if (part.role != goal.role) continue;
        if (replacement) return false;
        replacement = &part;
    }
    if (!replacement) return false;
    for (const auto& site : goal.sites) if (replacement->geometry.center == site) return true;
    return false;
}

bool ready(const Goal& goal, const world::State& state) {
    if (!relocated(goal, state)) return false;
    const auto path = world::material_path(state.topology);
    if (!path.collector_to_belt || !path.belt_to_processor) return false;
    const auto power = world::machine_power(state.topology);
    return power.collector && power.belt && power.processor;
}
}  // namespace factory::service_scenarios
