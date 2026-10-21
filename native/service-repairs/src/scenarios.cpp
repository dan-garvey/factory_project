#include "factory/service_scenarios.hpp"

#include <algorithm>
#include <array>
#include <string>

namespace factory::service_scenarios {
namespace r = repair_scenarios;
namespace s = stationary;
namespace {
constexpr std::array<mechanics::Point, 2> collector_sites{{{-4, 0, 12}, {4, 0, 12}}};
constexpr std::array<mechanics::Point, 2> belt_sites{{{0, 0, 12}, {8, 0, 12}}};
constexpr std::array<mechanics::Point, 2> press_sites{{{8, 0, 12}, {16, 0, 12}}};
constexpr std::array<r::Definition, 3> definitions{{
    {"service-collector", "Move the stocked collector",
     "Rebuild the collector at a service site and retrieve four plates from the original stock.",
     "Recover its raw blank before removal. Move the press into the service row, connect two shaft tiles with a belt and reinsert the blank."},
    {"service-belt", "Rebuild the blocked handoff",
     "Rebuild the belt at a service site and retrieve four plates without losing its held blank.",
     "Recover the belt slot, then build a fresh span between two shaft tiles in the service row and move the machines alongside it."},
    {"service-press", "Carry the finished billet through a rebuild",
     "Rebuild the press at a service site and retrieve four plates while retaining its original ready work.",
     "Recover the full press before removal. Move the complete line to a service row and return the same carried lot to the rebuilt press."},
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
        // Both complete service rows have finite, already installed drives.
        // Their overlapping column shares one drive; no material jumps across
        // the gap between the old and new rows.
        result->profile.build_reach = 10;
        constexpr std::array<mechanics::Integer, 6> columns{{-4, 0, 4, 8, 12, 16}};
        for (std::size_t site = 0; site < columns.size(); ++site) {
            const auto x = columns[site];
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
        // The original service line is a two-pulley span. The actor carries
        // two extra one-tile shafts for the selected replacement row.
        auto& topology = result->seed.topology;
        std::erase_if(topology.parts, [](const auto& part) { return part.geometry.id == "belt"; });
        for (auto& part : topology.parts)
            if (part.geometry.id == "processor" || part.geometry.id == "shaft-processor" ||
                part.geometry.id == "wheel-processor") part.geometry.center[0] += 4;
        topology.parts.push_back({{"pulley-first", mechanics::Kind::shaft, {4, 0, 8}, mechanics::Axis::z, 0, 2}, 1, s::Role::shaft});
        topology.parts.push_back({{"pulley-last", mechanics::Kind::shaft, {8, 0, 8}, mechanics::Axis::z, 0, 2}, 1, s::Role::shaft});
        topology.material_links.clear();
        topology.belt_spans = {{{"belt", "pulley-first", "pulley-last"}, 1}};
        result->seed.material.belt_lanes = {{"belt", materials::BeltLane{{std::nullopt, std::nullopt}, 0}}};
        result->seed.issued_entities.emplace("pulley-first", 1);
        result->seed.issued_entities.emplace("pulley-last", 1);
        result->seed.issued_entities.emplace("belt", 1);
        result->profile.finite_parts[{s::Role::shaft, 0, 2}] += 4;
        result->seed.kits.at("P")[{s::Role::shaft, 0, 2}] += 2;
        if (id == "service-collector") {
            result->seed.material.stock = {15, 1, 0, 0, 0};
        } else if (id == "service-belt") {
            result->seed.material.stock = {14, 1, 0, 0, 0};
            result->seed.material.belt_lanes.at("belt").slots.front() = materials::Cargo{1, 0, {}};
        } else {
            result->seed.material.stock.belt = 0;
            result->seed.material.belt_lanes.at("belt").slots.front() = materials::Cargo{1, 0, {}};
        }
        return result;
    }
    return std::nullopt;
}

bool relocated(const Goal& goal, const world::State& state) noexcept {
    if (goal.role == s::Role::belt) {
        if (state.topology.belt_spans.size() != 1) return false;
        const auto& span = state.topology.belt_spans.front();
        if (span.geometry.id == goal.original) return false;
        const auto first = std::find_if(state.topology.parts.begin(), state.topology.parts.end(), [&](const auto& part) {
            return part.geometry.id == span.geometry.first_shaft;
        });
        if (first == state.topology.parts.end()) return false;
        for (const auto& site : goal.sites) if (first->geometry.center == site) return true;
        return false;
    }
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
    const auto power = world::machine_power(state.topology);
    const auto motion = s::power_view(state.topology).mechanical;
    if (!power.collector || !power.processor || !motion.accepted()) return false;
    for (const auto& span : state.topology.belt_spans) {
        const auto first = std::find_if(state.topology.parts.begin(), state.topology.parts.end(),
            [&](const auto& part) { return part.geometry.id == span.geometry.first_shaft; });
        const auto last = std::find_if(state.topology.parts.begin(), state.topology.parts.end(),
            [&](const auto& part) { return part.geometry.id == span.geometry.last_shaft; });
        if (first == state.topology.parts.end() || last == state.topology.parts.end()) continue;
        const auto path = mechanics::belt_path(first->geometry, last->geometry);
        const auto speed = motion.motion.find(first->geometry.id);
        if (!path || path->kind != mechanics::BeltPathKind::horizontal || speed == motion.motion.end() ||
            speed->second.state != mechanics::MotionState::rotating) continue;
        const auto direction = mechanics::belt_cargo_direction(first->geometry, last->geometry, speed->second.rate);
        if (!direction || *direction != 1) continue;
        auto before = first->geometry.center, after = last->geometry.center;
        for (std::size_t axis = 0; axis < 3; ++axis) {
            const auto step = path->tiles[1][axis] - path->tiles[0][axis];
            before[axis] -= step; after[axis] += step;
        }
        const auto at = [&](s::Role role, const mechanics::Point& point) {
            return std::any_of(state.topology.parts.begin(), state.topology.parts.end(),
                [&](const auto& part) { return part.role == role && part.geometry.center == point; });
        };
        if (at(s::Role::collector, before) && at(s::Role::processor, after)) return true;
    }
    return false;
}
}  // namespace factory::service_scenarios
