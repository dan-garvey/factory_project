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
     "Each cog has pitch radius 5. Route above or below the fixed line in the x/z plane; each mesh spans ten units."},
    {"gear-riser", "The two-level drive",
     "Join the two gear planes with the carried shaft and retrieve four plates.",
     "The lower and upper middle cogs are coaxial but not coupled. A shaft can span both heights."},
}};

void add(r::Scenario& scenario, const std::string& id, s::Role role, g::Point point, g::Axis axis,
         g::Integer teeth = 0, g::Integer span = 0) {
    const auto kind = role == s::Role::gear ? g::Kind::gear : role == s::Role::shaft ? g::Kind::shaft : g::Kind::hub;
    scenario.seed.topology.parts.push_back({{id, kind, point, axis, teeth, span}, 1, role});
}

void endpoints(r::Scenario& scenario, g::Point input, g::Point output, g::Axis axis, g::Integer teeth) {
    auto source = input;
    auto machine = output;
    --source[static_cast<unsigned>(axis)];
    ++machine[static_cast<unsigned>(axis)];
    add(scenario, "wheel-collector", s::Role::waterwheel, source, axis);
    add(scenario, "shaft-input", s::Role::shaft, input, axis, 0, 1);
    add(scenario, "gear-input", s::Role::gear, input, axis, teeth);
    add(scenario, "collector", s::Role::collector, machine, axis);
    add(scenario, "shaft-output", s::Role::shaft, output, axis, 0, 1);
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
    topology.material_links = {{{"collector", 1}, {"belt", 1}}, {{"belt", 1}, {"processor", 1}}};
    auto& kit = result->seed.kits.at("P");
    if (id == "gear-idler") {
        endpoints(*result, {0, 0, 0}, {8, 0, 0}, g::Axis::z, 2);
        kit.emplace(s::PartSpec{s::Role::gear, 2, 0}, 1);
    } else if (id == "gear-bend") {
        endpoints(*result, {-11, 0, 0}, {11, 0, 0}, g::Axis::y, 5);
        kit.emplace(s::PartSpec{s::Role::gear, 5, 0}, 2);
    } else {
        endpoints(*result, {0, 0, 0}, {8, 2, 0}, g::Axis::y, 2);
        add(*result, "gear-low", s::Role::gear, {4, 0, 0}, g::Axis::y, 2);
        add(*result, "gear-high", s::Role::gear, {4, 2, 0}, g::Axis::y, 2);
        kit.emplace(s::PartSpec{s::Role::shaft, 0, 1}, 1);
    }
    // Declare this new content's exact startup supply once. World validates
    // these finite totals thereafter; no command can rerun this initializer.
    result->profile.finite_parts.clear();
    result->seed.issued_entities.clear();
    for (const auto& part : topology.parts) {
        ++result->profile.finite_parts[{part.role, part.geometry.teeth, part.geometry.half_span}];
        result->seed.issued_entities.emplace(part.geometry.id, part.generation);
    }
    for (const auto& [actor, carried] : result->seed.kits) {
        (void)actor;
        for (const auto& [specification, amount] : carried) result->profile.finite_parts[specification] += amount;
    }
    return result;
}
}  // namespace factory::geared_scenarios
