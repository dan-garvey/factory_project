#include "factory/stationary.hpp"

#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>

namespace {
namespace s = factory::stationary;
namespace m = factory::mechanics;
namespace material = factory::materials;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

s::PlacedPart hub(std::string id, s::Role role, m::Point center,
                  std::int64_t generation = 1) {
    return {{std::move(id), m::Kind::hub, center, m::Axis::z, 0, 0}, generation, role};
}

s::PlacedPart shaft(std::string id, std::int64_t generation = 1) {
    return {{std::move(id), m::Kind::shaft, {0, 0, 2}, m::Axis::z, 0, 2},
            generation, s::Role::shaft};
}

struct Fixture {
    s::Topology topology;
    s::Kit kit;
    material::State state;
};

Fixture fixture() {
    Fixture f;
    f.topology.parts = {
        hub("wheel-A", s::Role::waterwheel, {0, 0, 0}),
        shaft("shaft-A"),
        hub("collector-1", s::Role::collector, {0, 0, 4}),
        hub("wheel-B", s::Role::waterwheel, {10, 0, 0}),
        {{"shaft-B", m::Kind::shaft, {10, 0, 2}, m::Axis::z, 0, 2}, 1, s::Role::shaft},
        hub("belt-1", s::Role::belt, {10, 0, 4}),
        hub("processor-1", s::Role::processor, {20, 0, 4}),
    };
    f.topology.sources = {{"wheel-A", {1, 1}}, {"wheel-B", {2, 1}}};
    f.topology.drive_enabled = true;
    f.state.initial_units = 16;
    f.state.stock.source = 16;
    f.state.cargo = {{"P", {}}, {"Q", {}}};
    return f;
}

s::PlacementPlan place(const s::Topology& topology, const s::Kit& kit,
                       const material::State& state, const s::PlacedPart& part,
                       std::optional<m::Drive> drive = std::nullopt) {
    return s::prepare_placement(topology, kit, state, {part, drive});
}

void refusal(const s::PlacementPlan& plan, s::PlacementError reason) {
    check(std::holds_alternative<s::PlacementRefusal>(plan),
          "Placement refusal publishes no partial topology or kit.");
    check(std::get<s::PlacementRefusal>(plan).reason == reason,
          "Placement refusal retains its exact reason.");
}

void motion(const s::PowerView& power, const char* id, m::Rate rate) {
    check(power.mechanical.accepted(), "The mechanical candidate is valid.");
    check(power.mechanical.motion.at(id) == m::Motion{m::MotionState::rotating, rate},
          "The literal branch rate is retained or restored through actual geometry.");
}

void rebuild_returned_shaft() {
    const auto f = fixture();
    const auto removed = s::prepare_removal(f.topology, f.kit, f.state, {{"shaft-A", 1}});
    check(std::holds_alternative<s::PreparedRemoval>(removed),
          "The initial enabled removal must return the exact physical shaft.");
    const auto& old = std::get<s::PreparedRemoval>(removed);
    check(old.power.mechanical.motion.at("collector-1").state == m::MotionState::unpowered,
          "The removed transmission actually disconnects its branch.");

    const auto rebuilt = place(old.candidate, old.candidate_kit, f.state, shaft("shaft-A-2", 2));
    check(std::holds_alternative<s::PreparedPlacement>(rebuilt),
          "A returned shaft can rebuild its branch without a global stop.");
    const auto& plan = std::get<s::PreparedPlacement>(rebuilt);
    check(plan.candidate.drive_enabled && plan.candidate.sources == f.topology.sources,
          "Rebuilding preserves the explicit enable setting and unrelated sources.");
    check(plan.candidate_kit.at({s::Role::shaft, 0, 2}) == 0,
          "Rebuilding consumes the one returned exact shaft once.");
    check(plan.facts.target == material::EntityRef{"shaft-A-2", 2} &&
          plan.facts.consumed_part == s::PartSpec{s::Role::shaft, 0, 2},
          "The new receipt uses the fresh identity and exact physical part.");
    check(std::none_of(plan.candidate.parts.begin(), plan.candidate.parts.end(),
          [](const auto& p) { return p.geometry.id == "shaft-A"; }),
          "Rebuilding does not retarget the old removed identity.");
    motion(plan.power, "collector-1", {1, 1});
    motion(plan.power, "belt-1", {2, 1});
    check(f.state == fixture().state && old.candidate.parts.size() == 6,
          "Placement leaves material and the original removal candidate unchanged.");

    refusal(place(plan.candidate, plan.candidate_kit, f.state, shaft("shaft-A-2", 2)),
            s::PlacementError::identity_conflict);
}

void rebuild_returned_source() {
    const auto f = fixture();
    const auto removed = s::prepare_removal(f.topology, f.kit, f.state, {{"wheel-A", 1}});
    const auto& old = std::get<s::PreparedRemoval>(removed);
    const auto wheel = hub("wheel-A-2", s::Role::waterwheel, {0, 0, 0}, 2);
    refusal(place(old.candidate, old.candidate_kit, f.state, wheel),
            s::PlacementError::incompatible_source);
    refusal(place(old.candidate, old.candidate_kit, f.state, wheel, m::Drive{"wheel-A", {1, 1}}),
            s::PlacementError::incompatible_source);
    const auto rebuilt = place(old.candidate, old.candidate_kit, f.state, wheel,
                               m::Drive{"wheel-A-2", {1, 1}});
    const auto& plan = std::get<s::PreparedPlacement>(rebuilt);
    check(plan.candidate.sources == std::vector<m::Drive>{
              {"wheel-B", {2, 1}}, {"wheel-A-2", {1, 1}}},
          "Only the new source identity is registered; the surviving source remains exact.");
    check(plan.candidate_kit.at({s::Role::waterwheel, 0, 0}) == 0,
          "The returned complete waterwheel is consumed once.");
    motion(plan.power, "collector-1", {1, 1});
    motion(plan.power, "belt-1", {2, 1});
}

void exact_specification_and_refusals() {
    auto f = fixture();
    const s::PlacedPart gear{{"gear-8", m::Kind::gear, {100, 0, 0}, m::Axis::z, 8, 0},
                            1, s::Role::gear};
    refusal(place(f.topology, f.kit, f.state, gear), s::PlacementError::unavailable_part);
    f.kit[{s::Role::gear, 16, 0}] = 1;
    refusal(place(f.topology, f.kit, f.state, gear), s::PlacementError::unavailable_part);
    f.kit[{s::Role::gear, 8, 0}] = 1;
    const auto before = f;
    const auto result = place(f.topology, f.kit, f.state, gear);
    const auto& plan = std::get<s::PreparedPlacement>(result);
    check(plan.candidate_kit.at({s::Role::gear, 8, 0}) == 0 &&
          plan.candidate_kit.at({s::Role::gear, 16, 0}) == 1,
          "Placement consumes the matching tooth-count specification only.");
    check(f.topology == before.topology && f.kit == before.kit && f.state == before.state,
          "Successful planning preserves every original caller value.");

    auto invalid = gear;
    invalid.generation = 0;
    refusal(place(f.topology, f.kit, f.state, invalid), s::PlacementError::invalid_part);
    invalid = gear;
    invalid.geometry.id = std::string(1024 * 1024, 'x');
    refusal(place(f.topology, f.kit, f.state, invalid), s::PlacementError::invalid_part);
    invalid = gear;
    invalid.geometry.kind = m::Kind::hub;
    refusal(place(f.topology, f.kit, f.state, invalid), s::PlacementError::invalid_part);
    refusal(place(f.topology, f.kit, f.state, gear, m::Drive{"gear-8", {1, 1}}),
            s::PlacementError::incompatible_source);

    invalid = gear;
    invalid.geometry.center[0] = m::maximum_coordinate + 1;
    refusal(place(f.topology, f.kit, f.state, invalid), s::PlacementError::invalid_mechanics);

    f.topology.parts.push_back(gear);
    invalid = gear;
    invalid.geometry.id = "overlap";
    invalid.geometry.center[0] = 101;
    refusal(place(f.topology, f.kit, f.state, invalid), s::PlacementError::invalid_mechanics);

    f = fixture();
    f.kit[{s::Role::collector, 0, 0}] = 1;
    refusal(place(f.topology, f.kit, f.state,
                  hub("second-collector", s::Role::collector, {200, 0, 4})),
            s::PlacementError::invalid_part);

    f = fixture();
    f.kit[{s::Role::shaft, 0, 2}] = 1;
    while (f.topology.parts.size() < m::maximum_parts) {
        const auto index = static_cast<m::Integer>(f.topology.parts.size());
        f.topology.parts.push_back({
            {"bounded-gear-" + std::to_string(index), m::Kind::gear,
             {300 + 3 * index, 0, 0}, m::Axis::z, 1, 0}, 1, s::Role::gear});
    }
    refusal(place(f.topology, f.kit, f.state, shaft("one-too-many", 2)),
            s::PlacementError::part_limit);
}

}  // namespace

int main() {
    try {
        rebuild_returned_shaft();
        rebuild_returned_source();
        exact_specification_and_refusals();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"invented_stationary_rebuild\","
                     "\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "placement_test: " << error.what() << '\n';
        return 1;
    }
}
