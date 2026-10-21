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
     "Connect the two shaft tiles with your carried belt to restore the material handoff."},
    {"outlet", "The second plate is already made",
     "Free the output and retrieve four plates without discarding the waiting work.",
     "The ready billet is retained behind a full output. Collect the finished plate first."},
}};

void branch(Scenario& scenario, const std::string& machine, s::Role role, g::Integer x) {
    auto& topology = scenario.seed.topology;
    const std::string wheel = "wheel-" + machine;
    topology.parts.push_back({{wheel, g::Kind::hub, {x, 0, 0}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel});
    topology.parts.push_back({{"shaft-" + machine, g::Kind::shaft, {x, 0, 4}, g::Axis::z, 0, 2}, 1, s::Role::shaft});
    if (role == s::Role::shaft)
        topology.parts.push_back({{"pulley-first", g::Kind::shaft, {x, 0, 8}, g::Axis::z, 0, 2}, 1, role});
    else topology.parts.push_back({{machine, g::Kind::hub, {x, 0, 8}, g::Axis::z, 0, 0}, 1, role});
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
    // These authored repair fixtures use a forward-running belt.
    result.profile.waterwheel_rate = {-1, 1};
    result.profile.initial_units = 16;
    result.profile.actors = {"P", "Q"};
    result.profile.meters_per_grid_unit = 1.0;
    result.profile.build_reach = 4.0;
    result.profile.finite_parts = {
        {{s::Role::waterwheel, 0, 0}, 3}, {{s::Role::shaft, 0, 2}, 5},
        {{s::Role::collector, 0, 0}, 1}, {{s::Role::belt, 0, 0}, 1}, {{s::Role::processor, 0, 0}, 1},
    };
    result.seed.material.initial_units = 16;
    result.seed.material.stock.source = 16;
    result.seed.material.cargo = {{"P", {}}, {"Q", {}}};
    result.seed.kits = {{"P", {}}, {"Q", {}}};
    result.seed.topology.drive_enabled = true;
    branch(result, "collector", s::Role::collector, 0);
    branch(result, "belt", s::Role::shaft, 4);
    branch(result, "processor", s::Role::processor, 12);
    result.seed.topology.parts.push_back({{"pulley-last", g::Kind::shaft, {8, 0, 8}, g::Axis::z, 0, 2}, 1, s::Role::shaft});
    result.seed.topology.belt_spans = {{{"belt", "pulley-first", "pulley-last"}, 1}};
    result.seed.material.belt_lanes = {{"belt", materials::BeltLane{{std::nullopt, std::nullopt}, 0}}};
    result.seed.issued_entities.emplace("belt", 1);
    if (id == "coupling") {
        std::erase_if(result.seed.topology.parts,
            [](const auto& part) { return part.geometry.id == "shaft-collector"; });
        result.seed.kits.at("P").emplace(s::PartSpec{s::Role::shaft, 0, 2}, 1);
    } else if (id == "link") {
        result.seed.topology.belt_spans.clear();
        result.seed.material.belt_lanes.clear();
        result.seed.issued_entities.erase("belt");
        result.seed.kits.at("P").emplace(s::PartSpec{s::Role::belt, 0, 0}, 1);
    } else {
        result.seed.material.stock = {11, 1, 0, 1, 1};
        result.seed.material.belt_lanes.at("belt").slots.front() = materials::Cargo{1, 0, {}};
        result.seed.material.processing = materials::WorkLot{7, {1, 2}, 0};
        result.seed.material.next_work_id = 8;
    }
    for (const auto& part : result.seed.topology.parts) {
        result.seed.issued_entities.emplace(part.geometry.id, part.generation);
    }
    return result;
}
}  // namespace factory::repair_scenarios
