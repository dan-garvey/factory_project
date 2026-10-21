#include "factory/geared_scenarios.hpp"

#include <algorithm>
#include <array>

namespace factory::geared_scenarios {
namespace r = repair_scenarios;
namespace s = stationary;
namespace g = mechanics;
namespace {
constexpr std::array<r::Definition, 3> definitions{{
    {"gear-idler", "The missing middle cog",
     "Connect the collector's fixed cogs and retrieve four plates.",
     "Each carried or fixed cog has pitch radius 2. A mesh needs centers four grid units apart."},
    {"gear-bend", "Two cogs around the bend",
     "Route drive through both carried cogs and retrieve four plates.",
     "Route two carried cogs around either side of the corner. Adjacent cog tiles mesh."},
    {"gear-riser", "The two-level drive",
     "Join the two gear planes with the carried shaft and retrieve four plates.",
     "The lower and upper middle cogs are two tiles apart. Place the carried shaft in the tile between them."},
}};

void add(r::Scenario& scenario, const std::string& id, s::Role role, g::Point point, g::Axis axis,
         g::Integer teeth = 0, g::Integer span = 0) {
    const auto kind = role == s::Role::gear ? g::Kind::gear : role == s::Role::shaft ? g::Kind::shaft : g::Kind::hub;
    scenario.seed.topology.parts.push_back({{id, kind, point, axis, teeth, span}, 1, role});
}

void endpoints(r::Scenario& scenario, g::Point input, g::Point output, g::Axis axis, g::Integer teeth) {
    auto source = input;
    auto machine = output;
    source[static_cast<unsigned>(axis)] -= 4;
    machine[static_cast<unsigned>(axis)] += 4;
    if (axis == g::Axis::z) {
        source[2] += 8;
        machine[2] -= 8;
    }
    add(scenario, "wheel-collector", s::Role::waterwheel, source, axis);
    add(scenario, "gear-input", s::Role::gear, input, axis, teeth);
    add(scenario, "collector", s::Role::collector, machine, axis);
    add(scenario, "gear-output", s::Role::gear, output, axis, teeth);
    scenario.seed.topology.sources.push_back({"wheel-collector", scenario.profile.waterwheel_rate});
}
}  // namespace

std::span<const r::Definition> catalogue() noexcept { return definitions; }

std::optional<r::Scenario> make(std::string_view id) {
    const auto definition = std::find_if(definitions.begin(), definitions.end(),
        [id](const auto& candidate) { return candidate.id == id; });
    if (definition == definitions.end()) return std::nullopt;
    // Reuse only trusted authored startup data, before any World exists. This
    // is not a fallback after failed admission, validation, import or recovery.
    auto result = r::make("link");
    if (!result) return std::nullopt;
    result->definition = &*definition;
    auto& topology = result->seed.topology;
    std::erase_if(topology.parts, [](const auto& part) {
        return part.geometry.id == "collector" || part.geometry.id == "wheel-collector" || part.geometry.id == "shaft-collector";
    });
    std::erase_if(topology.sources, [](const auto& source) { return source.hub == "wheel-collector"; });
    topology.material_links.clear();
    auto& kit = result->seed.kits.at("P");
    if (id == "gear-idler") {
        endpoints(*result, {-8, 0, 0}, {0, 0, 0}, g::Axis::z, 2);
        kit.emplace(s::PartSpec{s::Role::gear, 2, 0}, 1);
    } else if (id == "gear-bend") {
        endpoints(*result, {-12, 0, -4}, {-8, 0, 4}, g::Axis::y, 2);
        kit.emplace(s::PartSpec{s::Role::gear, 2, 0}, 2);
    } else {
        endpoints(*result, {-8, 0, 0}, {0, 8, 0}, g::Axis::y, 2);
        add(*result, "gear-low", s::Role::gear, {-4, 0, 0}, g::Axis::y, 2);
        add(*result, "gear-high", s::Role::gear, {-4, 8, 0}, g::Axis::y, 2);
        for (auto& part : topology.parts)
            if (part.geometry.id == "wheel-collector" || part.geometry.id == "collector" ||
                part.geometry.id == "gear-input" || part.geometry.id == "gear-output" ||
                part.geometry.id == "gear-low" || part.geometry.id == "gear-high") part.geometry.center[1] -= 8;
        kit.emplace(s::PartSpec{s::Role::shaft, 0, 2}, 1);
    }
    // Move the two independent drive branches to the collector's material
    // row, replacing the former belt hub with two physical shaft pulleys.
    const auto collector = std::find_if(topology.parts.begin(), topology.parts.end(), [](const auto& part) {
        return part.geometry.id == "collector";
    });
    if (collector == topology.parts.end()) return std::nullopt;
    const auto origin = collector->geometry.center;
    for (const auto& [machine, offset] : std::array<std::pair<std::string, g::Integer>, 2>{{{"pulley-first", 4}, {"processor", 12}}}) {
        const auto found = std::find_if(topology.parts.begin(), topology.parts.end(), [&](const auto& part) {
            return part.geometry.id == machine;
        });
        if (found == topology.parts.end()) return std::nullopt;
        const g::Point delta{origin[0] + offset - found->geometry.center[0],
            origin[1] - found->geometry.center[1], origin[2] - found->geometry.center[2]};
        for (auto& part : topology.parts)
            if (part.geometry.id == machine || part.geometry.id == "wheel-" + (machine == "pulley-first" ? "belt" : machine) ||
                part.geometry.id == "shaft-" + (machine == "pulley-first" ? "belt" : machine))
                for (std::size_t coordinate = 0; coordinate < 3; ++coordinate) part.geometry.center[coordinate] += delta[coordinate];
    }
    for (auto& part : topology.parts)
        if (part.geometry.id == "pulley-last") part.geometry.center = {origin[0] + 8, origin[1], origin[2]};
    kit.erase({s::Role::belt, 0, 0});
    topology.belt_spans = {{{"belt", "pulley-first", "pulley-last"}, 1}};
    result->seed.material.belt_lanes = {{"belt", materials::BeltLane{{std::nullopt, std::nullopt}, 0}}};
    // Declare this new content's exact startup supply once. World validates
    // these finite totals thereafter; no command can rerun this initializer.
    result->profile.finite_parts.clear();
    result->seed.issued_entities.clear();
    for (const auto& part : topology.parts) {
        ++result->profile.finite_parts[{part.role, part.geometry.teeth, part.geometry.half_span}];
        result->seed.issued_entities.emplace(part.geometry.id, part.generation);
    }
    ++result->profile.finite_parts[{s::Role::belt, 0, 0}];
    result->seed.issued_entities.emplace("belt", 1);
    for (const auto& [actor, carried] : result->seed.kits) {
        (void)actor;
        for (const auto& [specification, amount] : carried) result->profile.finite_parts[specification] += amount;
    }
    return result;
}
}  // namespace factory::geared_scenarios
