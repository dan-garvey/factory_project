#include "factory/drive_diagnostics.hpp"
#include "factory/co_drive_scenarios.hpp"

#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <string>

namespace d = factory::drive_diagnostics;
namespace g = factory::mechanics;
namespace w = factory::world;
namespace c = factory::co_drive_scenarios;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
struct Scene {
    std::vector<g::Part> parts;
    std::vector<g::Drive> sources;
};
void wheel(Scene& scene, const std::string& prefix, g::Point at, g::Integer teeth, g::Rate rate) {
    scene.parts.push_back({prefix + "-hub", g::Kind::hub, at, g::Axis::z});
    scene.parts.push_back({prefix + "-shaft", g::Kind::shaft, at, g::Axis::z, 0, 1});
    scene.parts.push_back({prefix + "-gear", g::Kind::gear, at, g::Axis::z, teeth});
    scene.sources.push_back({prefix + "-hub", rate});
}
Scene pair(g::Integer first = 2, g::Integer second = 2, g::Rate a = {1, 1}, g::Rate b = {1, 1}) {
    Scene scene;
    wheel(scene, "a", {0, 0, 0}, first, a);
    // The opening's small/large pair meshes at diagonal cell positions.
    const g::Point offset = (first == 2 && second == 4) || (first == 4 && second == 2)
        ? g::Point{4, 4, 0} : g::Point{first + second, 0, 0};
    wheel(scene, "b", offset, second, b);
    return scene;
}
const d::Witness& one(const d::Report& report, d::Kind kind) {
    check(report.current.accepted() && report.witnesses.size() == 1 && report.witnesses.front().kind == kind,
          "One accepted stalled component has the required supported explanation class.");
    check(std::any_of(report.current.components.begin(), report.current.components.end(), [&](const auto& component) {
              return component.state == g::MotionState::stalled && report.witnesses.front().component == component.parts;
          }),
          "The owned witness names exactly the current stalled component, not another group.");
    return report.witnesses.front();
}
void source_conflicts() {
    auto scene = pair();
    const auto report = d::inspect(scene.parts, scene.sources, {});
    const auto& witness = one(report, d::Kind::incompatible_sources);
    check(witness.source == "a-hub" && witness.other_source == "b-hub" && witness.hub == "b-hub" &&
          witness.first_rate == g::Rate{-1, 1} && witness.second_rate == g::Rate{1, 1},
          "Equal cogs reverse the first source to minus one where the other source independently prescribes plus one.");
    const std::vector<std::string> names{"a-gear", "a-hub", "a-shaft", "b-gear", "b-hub", "b-shaft"};
    check(witness.component == names, "Component membership is canonical and owned.");
    std::reverse(scene.parts.begin(), scene.parts.end());
    std::reverse(scene.sources.begin(), scene.sources.end());
    check(d::inspect(scene.parts, scene.sources, {}).witnesses == report.witnesses,
          "Reversing both supplied orders cannot change source choice, rates or witness identities.");
    scene.parts.clear(); scene.sources.clear();
    check(witness.component == names && witness.source == "a-hub" && witness.second_rate == g::Rate{1, 1},
          "The report retains its strings/rates after all caller-owned inputs are destroyed.");

    const auto unequal = pair(2, 4, {3, 2}, {2, 4});
    const auto unequal_report = d::inspect(unequal.parts, unequal.sources, {});
    const auto& ratio = one(unequal_report, d::Kind::incompatible_sources);
    check(ratio.first_rate == g::Rate{-3, 4} && ratio.second_rate == g::Rate{1, 2},
          "The witness preserves literal signed three-quarters versus normalized one-half without local ratio arithmetic.");
    const auto stopped = pair(2, 2, {1, 1}, {0, 7});
    const auto stopped_report = d::inspect(stopped.parts, stopped.sources, {});
    const auto& zero = one(stopped_report, d::Kind::incompatible_sources);
    check(zero.first_rate == g::Rate{-1, 1} && zero.second_rate == g::Rate{0, 1},
          "A stopped prescribed source is distinguished from another source's negative unit rate.");
}
void ordinary_states() {
    const auto coherent = pair(2, 2, {1, 1}, {-2, 2});
    const auto normal = d::inspect(coherent.parts, coherent.sources, {});
    check(normal.current.accepted() && normal.witnesses.empty() &&
          normal.current.motion.at("a-hub").rate == g::Rate{1, 1} && normal.current.motion.at("b-hub").rate == g::Rate{-1, 1},
          "Opposite supplied rates across one mesh are coherent and receive no invented fault.");
    auto scene = pair();
    const auto unpowered = d::inspect(scene.parts, {}, {});
    check(unpowered.current.accepted() && unpowered.witnesses.empty() &&
          unpowered.current.motion.at("a-hub").state == g::MotionState::unpowered,
          "An unpowered geometry is not relabelled as a source disagreement.");
    for (auto& source : scene.sources) source.rate = {0, 1};
    const auto stopped = d::inspect(scene.parts, scene.sources, {});
    check(stopped.current.accepted() && stopped.witnesses.empty() &&
          stopped.current.motion.at("b-hub").state == g::MotionState::stopped,
          "Two stopped sources keep the existing stopped interpretation.");
    const auto empty = d::inspect({}, {}, {});
    check(empty.current.accepted() && empty.witnesses.empty(), "An empty accepted scene has no fabricated diagnosis.");
}
void loops_and_components() {
    Scene loop;
    wheel(loop, "a", {0, 0, 0}, 1, {1, 1});
    loop.parts.push_back({"b-gear", g::Kind::gear, {3, 0, 0}, g::Axis::z, 2});
    loop.parts.push_back({"c-gear", g::Kind::gear, {0, 4, 0}, g::Axis::z, 3});
    const auto report = d::inspect(loop.parts, loop.sources, {});
    const auto& witness = one(report, d::Kind::single_source_stall);
    check(witness.source == "a-hub" && witness.other_source.empty(),
          "The odd 3-4-5 gear triangle still stalls with its sole source and does not blame an absent second wheel.");
    loop.sources.front().rate = {0, 1};
    const auto halted = d::inspect(loop.parts, loop.sources, {});
    check(halted.current.accepted() && halted.witnesses.empty() &&
          halted.current.components.front().state == g::MotionState::stopped,
          "The diagnostic preserves the kernel's zero-rate interpretation of the same loop.");

    auto scene = pair();
    wheel(scene, "c", {20, 0, 0}, 2, {1, 1});
    wheel(scene, "d", {24, 0, 0}, 2, {1, 1});
    const auto both = d::inspect(scene.parts, scene.sources, {});
    check(both.current.accepted() && both.witnesses.size() == 2 &&
          both.witnesses[0].source == "a-hub" && both.witnesses[0].other_source == "b-hub" &&
          both.witnesses[1].source == "c-hub" && both.witnesses[1].other_source == "d-hub",
          "Independent components retain their own exact source disagreement instead of borrowing a remote wheel.");
    std::reverse(scene.parts.begin(), scene.parts.end()); std::reverse(scene.sources.begin(), scene.sources.end());
    check(d::inspect(scene.parts, scene.sources, {}).witnesses == both.witnesses,
          "Multiple component ordering and witnesses remain deterministic under input reversal.");
    for (const auto axis : {g::Axis::x, g::Axis::y}) {
        auto rotated = pair();
        for (auto& part : rotated.parts) {
            const auto old = part.center;
            part.axis = axis;
            part.center = axis == g::Axis::x ? g::Point{old[2], old[0], old[1]} : g::Point{old[1], old[2], old[0]};
        }
        const auto actual = d::inspect(rotated.parts, rotated.sources, {});
        check(actual.witnesses == d::inspect(pair().parts, pair().sources, {}).witnesses,
              "Both other gear-plane axes preserve the literal equal-cog disagreement.");
    }
}
void limits_and_invalid_inputs() {
    constexpr g::Integer large = g::Integer{1} << 62;
    auto scene = pair(1, 3, {0, 1}, {large, 1});
    const auto limited = d::inspect(scene.parts, scene.sources, {});
    const auto& witness = one(limited, d::Kind::counterfactual_limit);
    check(witness.source == "b-hub" && witness.counterfactual_error == g::Error::rate_overflow &&
          witness.other_source.empty(),
          "An accepted zero-root stall can exceed the native rate bound when another source acts alone; the report admits that limit.");
    scene.parts.push_back({"c-hub", g::Kind::hub, {0, 0, 0}, g::Axis::z});
    scene.sources.push_back({"c-hub", {1, 1}});
    const auto supported = d::inspect(scene.parts, scene.sources, {});
    const auto& pair_witness = one(supported, d::Kind::incompatible_sources);
    check(pair_witness.source == "a-hub" && pair_witness.other_source == "c-hub" &&
          pair_witness.first_rate == g::Rate{0, 1} && pair_witness.second_rate == g::Rate{1, 1},
          "A failed counterfactual does not hide a later independently supported source pair.");
    const auto expected = supported.witnesses;
    std::sort(scene.sources.begin(), scene.sources.end(), [](const auto& left, const auto& right) { return left.hub < right.hub; });
    do {
        check(d::inspect(scene.parts, scene.sources, {}).witnesses == expected,
              "All source permutations choose the same supported pair despite an overflowing counterfactual.");
    } while (std::next_permutation(scene.sources.begin(), scene.sources.end(),
                 [](const auto& left, const auto& right) { return left.hub < right.hub; }));

    auto invalid = pair();
    invalid.parts[0].id = std::string(4096, 'x');
    const auto oversized = d::inspect(invalid.parts, invalid.sources, {});
    check(!oversized.current.accepted() && oversized.current.subject.empty() && oversized.witnesses.empty(),
          "The kernel rejects an oversized identity before diagnostic copying or witness allocation.");
    invalid = pair(); invalid.sources[0].hub = std::string(4096, 'x');
    const auto bad_source = d::inspect(invalid.parts, invalid.sources, {});
    check(bad_source.current.error == g::Error::invalid_drive && bad_source.current.subject.empty() && bad_source.witnesses.empty(),
          "Oversized source metadata is not retained as a diagnostic identity.");
    invalid = pair(); invalid.parts.push_back(invalid.parts.front());
    const auto duplicate = d::inspect(invalid.parts, invalid.sources, {});
    check(duplicate.current.error == g::Error::duplicate_identity && duplicate.witnesses.empty(),
          "Malformed geometry preserves the original refusal instead of manufacturing a stall explanation.");
    const auto too_many = d::inspect(std::vector<g::Part>(g::maximum_parts + 1), {}, {});
    check(too_many.current.error == g::Error::too_many_parts && too_many.witnesses.empty(),
          "The existing part bound applies before any component query is attempted.");
}
void actual_world() {
    const auto content = c::make("co-drive");
    check(content.has_value(), "The exact accepted co-drive startup is available without substitution.");
    auto world = w::World::create("drive-diagnostic-world", content->profile, content->seed);
    check(world != nullptr, "The accepted co-drive fixture still creates its actual finite World.");
    const auto before = world->snapshot();
    std::vector<g::Part> parts;
    for (const auto& part : before.state.topology.parts) parts.push_back(part.geometry);
    std::vector<g::BeltSpan> belts;
    for (const auto& span : before.state.topology.belt_spans) belts.push_back(span.geometry);
    const auto report = d::inspect(parts, before.state.topology.sources, belts);
    check(report.current.components == factory::stationary::power_view(before.state.topology).mechanical.components,
          "The diagnostic sees exactly the World's physical belt-connected components.");
    const auto& witness = one(report, d::Kind::incompatible_sources);
    check(witness.source == "wheel-left" && witness.other_source == "wheel-right" && witness.hub == "wheel-right" &&
          witness.first_rate == g::Rate{-1, 1} && witness.second_rate == g::Rate{1, 1},
          "The real two-waterwheel puzzle exposes the exact contradictory signed rates at the registered right wheel.");
    const auto after = world->snapshot();
    check(after.state == before.state && after.revision == before.revision && after.history.order == before.history.order &&
          after.history.records.empty() && after.state.material.stock.source == 16 && w::validate(content->profile, after),
          "Counterfactual inspection issues no command, removes no wheel, advances no tick and retains all actual World custody.");
}
void belt_connected_sources() {
    const std::vector<g::Part> parts{
        {"left-wheel", g::Kind::hub, {0, 0, -4}, g::Axis::z},
        {"left-shaft", g::Kind::shaft, {0, 0, 0}, g::Axis::z, 0, 2},
        {"right-wheel", g::Kind::hub, {8, 0, -4}, g::Axis::z},
        {"right-shaft", g::Kind::shaft, {8, 0, 0}, g::Axis::z, 0, 2},
        {"remote-wheel", g::Kind::hub, {40, 0, -4}, g::Axis::z},
        {"remote-shaft", g::Kind::shaft, {40, 0, 0}, g::Axis::z, 0, 2},
    };
    const std::vector<g::Drive> sources{{"left-wheel", {1, 1}}, {"right-wheel", {-1, 1}},
                                        {"remote-wheel", {3, 1}}};
    const std::vector<g::BeltSpan> belts{{"belt", "left-shaft", "right-shaft"}};
    const auto report = d::inspect(parts, sources, belts);
    const auto& witness = one(report, d::Kind::incompatible_sources);
    check(witness.source == "left-wheel" && witness.other_source == "right-wheel" &&
          witness.first_rate == g::Rate{1, 1} && witness.second_rate == g::Rate{-1, 1} &&
          std::find(witness.component.begin(), witness.component.end(), "remote-wheel") == witness.component.end(),
          "A belt-connected source disagreement is explained using only its actual component.");
    const auto separate = d::inspect(parts, sources, {});
    check(separate.current.accepted() && separate.witnesses.empty(),
          "Removing the belt separates the independent sources and removes the stall.");
    const auto malformed = d::inspect(parts, sources, {{"bad", "left-shaft", "missing"}});
    check(malformed.current.error == g::Error::invalid_belt && malformed.witnesses.empty(),
          "An invalid physical belt remains a solver refusal rather than a fabricated diagnosis.");
}
}  // namespace

int main() {
    try {
        source_conflicts(); ordinary_states(); loops_and_components(); limits_and_invalid_inputs();
        belt_connected_sources(); actual_world();
        std::cout << checks << " native drive-diagnostic checks, 0 failures; applied_repairs=0, engine_calls=0.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n'; return 1;
    }
}
