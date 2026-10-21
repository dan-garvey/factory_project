#include "factory/repair_scenarios.hpp"

#include <algorithm>
#include <array>

namespace factory::repair_scenarios {
namespace s = stationary;
namespace g = mechanics;
namespace {
constexpr std::array<Definition, 3> definitions{{
    {"coupling", "The wheel turns, the cutter waits",
     "Repair the cutter's drive and retrieve four plates.",
     "Trace rotation from the cutter to its waterwheel. You carry the missing shaft."},
    {"link", "A blank with nowhere to go",
     "Restore the material path and retrieve four plates.",
     "The belt holds a blank, but the press input is empty. Inspect the missing handoff."},
    {"outlet", "The second plate is already made",
     "Free the output and retrieve four plates without discarding the waiting work.",
     "The ready billet is retained behind a full output. Collect the finished plate first."},
}};

void branch(Scenario& scenario, const std::string& machine, s::Role role, g::Integer x) {
    auto& topology = scenario.seed.topology;
    const std::string wheel = "wheel-" + machine;
    topology.parts.push_back({{wheel, g::Kind::hub, {x, 0, 0}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel});
    topology.parts.push_back({{"shaft-" + machine, g::Kind::shaft, {x, 0, 2}, g::Axis::z, 0, 2}, 1, s::Role::shaft});
    topology.parts.push_back({{machine, g::Kind::hub, {x, 0, 4}, g::Axis::z, 0, 0}, 1, role});
    topology.sources.push_back({wheel, scenario.profile.waterwheel_rate});
}
}  // namespace

std::span<const Definition> catalogue() noexcept { return definitions; }

std::optional<Scenario> make(std::string_view id) {
    const auto definition = std::find_if(definitions.begin(), definitions.end(),
        [id](const auto& item) { return item.id == id; });
    if (definition == definitions.end()) return std::nullopt;
    Scenario result;
    result.definition = &*definition;
    result.profile.material = {1, 1, 2};
    result.profile.initial_units = 16;
    result.profile.actors = {"P", "Q"};
    result.profile.meters_per_grid_unit = 1.0;
    result.profile.build_reach = 4.0;
    result.profile.finite_parts = {
        {{s::Role::waterwheel, 0, 0}, 3}, {{s::Role::shaft, 0, 2}, 3},
        {{s::Role::collector, 0, 0}, 1}, {{s::Role::belt, 0, 0}, 1}, {{s::Role::processor, 0, 0}, 1},
    };
    result.seed.material.initial_units = 16;
    result.seed.material.stock.source = 16;
    result.seed.material.cargo = {{"P", {}}, {"Q", {}}};
    result.seed.kits = {{"P", {}}, {"Q", {}}};
    result.seed.topology.drive_enabled = true;
    branch(result, "collector", s::Role::collector, 0);
    branch(result, "belt", s::Role::belt, 3);
    branch(result, "processor", s::Role::processor, 6);
    result.seed.topology.material_links = {
        {{"collector", 1}, {"belt", 1}}, {{"belt", 1}, {"processor", 1}},
    };
    if (id == "coupling") {
        for (auto& part : result.seed.topology.parts)
            if (part.geometry.id == "wheel-collector") part.geometry.center[2] = -4;
        std::erase_if(result.seed.topology.parts,
            [](const auto& part) { return part.geometry.id == "shaft-collector"; });
        result.profile.finite_parts.at({s::Role::shaft, 0, 2}) = 2;
        result.profile.finite_parts.emplace(s::PartSpec{s::Role::shaft, 0, 4}, 1);
        result.seed.kits.at("P").emplace(s::PartSpec{s::Role::shaft, 0, 4}, 1);
    } else if (id == "link") {
        result.seed.topology.material_links.pop_back();
    } else {
        result.seed.material.stock = {11, 1, 1, 1, 1};
        result.seed.material.processing = materials::WorkLot{7, {1, 2}, 0};
        result.seed.material.next_work_id = 8;
    }
    for (const auto& part : result.seed.topology.parts) {
        result.seed.issued_entities.emplace(part.geometry.id, part.generation);
    }
    return result;
}
}  // namespace factory::repair_scenarios
