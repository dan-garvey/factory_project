#include "factory/stationary.hpp"

#include <algorithm>
#include <iostream>
#include <limits>
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

s::PlacedPart hub(std::string id, s::Role role, m::Point center) {
    return {{std::move(id), m::Kind::hub, center, m::Axis::z, 0, 0}, 1, role};
}

s::PlacedPart shaft(std::string id, m::Point center, m::Integer half_span = 2) {
    return {{std::move(id), m::Kind::shaft, center, m::Axis::z, 0, half_span},
            1, s::Role::shaft};
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
        shaft("shaft-A", {0, 0, 2}),
        hub("collector-1", s::Role::collector, {0, 0, 4}),
        hub("wheel-B", s::Role::waterwheel, {10, 0, 0}),
        shaft("shaft-B", {10, 0, 2}),
        hub("belt-1", s::Role::belt, {10, 0, 4}),
        hub("processor-1", s::Role::processor, {20, 0, 4}),
    };
    f.topology.material_links = {
        {{"collector-1", 1}, {"belt-1", 1}},
        {{"belt-1", 1}, {"processor-1", 1}},
    };
    f.topology.sources = {{"wheel-A", {1, 1}}, {"wheel-B", {2, 1}}};
    f.topology.drive_enabled = true;
    f.kit = {{{s::Role::collector, 0, 0}, 0},
             {{s::Role::shaft, 0, 2}, 0},
             {{s::Role::gear, 16, 0}, 3}};
    f.state.initial_units = 16;
    f.state.stock.source = 16;
    f.state.cargo = {{"P", {}}, {"Q", {}}};
    return f;
}

s::RemovalPlan remove(const Fixture& f, const char* id, std::int64_t generation = 1) {
    return s::prepare_removal(f.topology, f.kit, f.state, {{id, generation}});
}

material::Quantity carried(const s::Kit& kit, s::PartSpec spec) {
    const auto found = kit.find(spec);
    return found == kit.end() ? 0 : found->second;
}

void refusal(const s::RemovalPlan& plan, s::RemovalError reason) {
    check(std::holds_alternative<s::RemovalRefusal>(plan),
          "A refusal publishes no topology or kit candidate.");
    check(std::get<s::RemovalRefusal>(plan).reason == reason,
          "The refusal identifies its exact reason.");
}

void motion(const s::PowerView& view, const char* id, m::MotionState state,
            m::Rate rate) {
    check(view.mechanical.accepted(), "The shared mechanical derivation must succeed.");
    check(view.mechanical.motion.at(id) == m::Motion{state, rate},
          "The independently specified component motion must match.");
}

void enabled_local_removal() {
    const auto f = fixture();
    const auto before = s::power_view(f.topology);
    motion(before, "collector-1", m::MotionState::rotating, {1, 1});
    motion(before, "belt-1", m::MotionState::rotating, {2, 1});

    const auto result = remove(f, "shaft-A");
    check(std::holds_alternative<s::PreparedRemoval>(result),
          "A running stationary shaft can be removed without a drive-off request.");
    const auto& plan = std::get<s::PreparedRemoval>(result);
    check(plan.candidate.drive_enabled && plan.power.drive_enabled,
          "Removal preserves the explicit drive setting.");
    check(plan.candidate.parts.size() == 6 && plan.candidate.sources == f.topology.sources,
          "Only the selected physical part is removed.");
    check(plan.candidate.material_links == f.topology.material_links,
          "Removing a transmission shaft does not delete material links.");
    check(carried(plan.candidate_kit, {s::Role::shaft, 0, 2}) == 1,
          "Exactly the selected shaft length returns to the kit.");
    check(plan.facts.target == material::EntityRef{"shaft-A", 1} &&
          plan.facts.interaction_point == m::Point{0, 0, 2},
          "The receipt retains the pre-edit identity and interaction point.");
    motion(plan.power, "collector-1", m::MotionState::unpowered, {0, 1});
    motion(plan.power, "belt-1", m::MotionState::rotating, {2, 1});
    motion(plan.power, "wheel-B", m::MotionState::rotating, {2, 1});
    check(f.topology == fixture().topology && f.kit == fixture().kit &&
          f.state == fixture().state, "Planning preserves every original caller value.");
}

void exact_part_and_link_refunds() {
    auto f = fixture();
    const auto original_material = f.state;
    const auto result = remove(f, "collector-1");
    const auto& plan = std::get<s::PreparedRemoval>(result);
    check(carried(plan.candidate_kit, {s::Role::collector, 0, 0}) == 1,
          "Empty machine removal returns exactly one complete machine.");
    check(carried(plan.candidate_kit, {s::Role::shaft, 0, 2}) == 0,
          "A lost derived engagement never refunds an imaginary shaft.");
    check(plan.candidate.material_links ==
              std::vector<s::MaterialLink>{{{"belt-1", 1}, {"processor-1", 1}}},
          "Only incident material links disappear.");
    check(plan.facts.removed_material_links ==
              std::vector<s::MaterialLink>{{{"collector-1", 1}, {"belt-1", 1}}},
          "The receipt names only the removed incident material link.");
    check(f.state == original_material, "Removal planning does not write material.");

    f.topology.parts.push_back({{"gear-8", m::Kind::gear, {100, 0, 0}, m::Axis::z, 8, 0},
                                7, s::Role::gear});
    const auto gear_result = remove(f, "gear-8", 7);
    const auto& gear_plan = std::get<s::PreparedRemoval>(gear_result);
    check(carried(gear_plan.candidate_kit, {s::Role::gear, 8, 0}) == 1 &&
          carried(gear_plan.candidate_kit, {s::Role::gear, 16, 0}) == 3,
          "A gear refund preserves tooth count instead of converting part types.");
    check(gear_plan.candidate.parts == fixture().topology.parts,
          "A disconnected gear removal preserves every original machine and shaft.");

    f = fixture();
    f.topology.parts.push_back(shaft("shaft-5", {200, 0, 0}, 5));
    const auto shaft_result = remove(f, "shaft-5");
    const auto& shaft_plan = std::get<s::PreparedRemoval>(shaft_result);
    check(carried(shaft_plan.candidate_kit, {s::Role::shaft, 0, 5}) == 1 &&
          carried(shaft_plan.candidate_kit, {s::Role::shaft, 0, 2}) == 0,
          "A different shaft span returns its own exact specification.");
}

void occupied_and_carried_custody() {
    for (const auto role : {s::Role::collector, s::Role::belt, s::Role::processor}) {
        auto f = fixture();
        f.state.stock.source = 15;
        const char* id = "processor-1";
        if (role == s::Role::collector) {
            f.state.stock.collector = 1;
            id = "collector-1";
        } else if (role == s::Role::belt) {
            f.state.stock.belt = 1;
            id = "belt-1";
        } else f.state.stock.input = 1;
        const auto snapshot = f;
        refusal(remove(f, id), s::RemovalError::occupied_target);
        check(f.topology == snapshot.topology && f.kit == snapshot.kit &&
              f.state == snapshot.state, "Occupied refusal preserves all custody and parts.");
    }

    for (const auto ticks : {0, 1}) {
        auto f = fixture();
        f.state.stock.source = 15;
        f.state.processing = material::WorkLot{1, {1, 2}, ticks};
        f.state.next_work_id = 2;
        const auto snapshot = f.state;
        refusal(remove(f, "processor-1"), s::RemovalError::occupied_target);
        check(f.state == snapshot,
              "Ready or partially processed work keeps its identity, recipe and progress.");
    }
    auto output = fixture();
    output.state.stock.source = 15;
    output.state.stock.output = 1;
    refusal(remove(output, "processor-1"), s::RemovalError::occupied_target);

    auto carried_work = fixture();
    carried_work.state.stock.source = 14;
    carried_work.state.cargo.at("P").raw_units = 1;
    carried_work.state.cargo.at("P").work_lots = {{1, {1, 2}, 0}};
    carried_work.state.next_work_id = 2;
    const auto snapshot = carried_work.state;
    check(std::holds_alternative<s::PreparedRemoval>(remove(carried_work, "processor-1")),
          "Actor Cargo is not occupied-machine custody.");
    check(carried_work.state == snapshot, "Carried raw and whole work remain untouched.");
}

void source_and_disabled_view() {
    const auto f = fixture();
    const auto result = remove(f, "wheel-A");
    const auto& plan = std::get<s::PreparedRemoval>(result);
    check(plan.facts.removed_source && plan.candidate.sources ==
              std::vector<m::Drive>{{"wheel-B", {2, 1}}},
          "Removing one source unregisters only that source.");
    check(plan.candidate.drive_enabled, "Source removal does not disable the global drive.");
    motion(plan.power, "collector-1", m::MotionState::unpowered, {0, 1});
    motion(plan.power, "belt-1", m::MotionState::rotating, {2, 1});

    auto off = fixture();
    off.topology.drive_enabled = false;
    const auto before = off.topology;
    const auto view = s::power_view(off.topology);
    motion(view, "collector-1", m::MotionState::stopped, {0, 1});
    motion(view, "belt-1", m::MotionState::stopped, {0, 1});
    check(!view.drive_enabled && off.topology == before,
          "Read-only disabled power never overwrites configured source rates.");
}

void malformed_and_overflow() {
    auto f = fixture();
    refusal(remove(f, "collector-1", 2), s::RemovalError::stale_generation);
    refusal(remove(f, "missing"), s::RemovalError::unknown_target);

    f.kit[{s::Role::collector, 0, 0}] = std::numeric_limits<material::Quantity>::max();
    const auto before = f.kit;
    refusal(remove(f, "collector-1"), s::RemovalError::quantity_overflow);
    check(f.kit == before, "Refund overflow preserves the original finite kit.");

    f = fixture();
    f.kit[{s::Role::collector, 0, 0}] = -1;
    refusal(remove(f, "collector-1"), s::RemovalError::invalid_kit);
    f = fixture();
    f.topology.parts.push_back(f.topology.parts.front());
    refusal(remove(f, "collector-1"), s::RemovalError::invalid_topology);
    f = fixture();
    f.topology.material_links.front().from.generation = 9;
    refusal(remove(f, "collector-1"), s::RemovalError::invalid_topology);
    f = fixture();
    f.topology.sources.push_back(f.topology.sources.front());
    refusal(remove(f, "collector-1"), s::RemovalError::invalid_topology);
    f = fixture();
    f.topology.sources.front().hub = "collector-1";
    refusal(remove(f, "collector-1"), s::RemovalError::invalid_topology);
    f = fixture();
    f.topology.sources.front().rate.denominator = 0;
    f.topology.drive_enabled = false;
    refusal(remove(f, "collector-1"), s::RemovalError::invalid_topology);
    f = fixture();
    f.topology.parts.front().geometry.id = std::string(1024 * 1024, 'x');
    refusal(remove(f, "collector-1"), s::RemovalError::invalid_topology);
    f = fixture();
    f.topology.parts[2].geometry.kind = m::Kind::gear;
    refusal(remove(f, "collector-1"), s::RemovalError::invalid_topology);
    f = fixture();
    f.topology.parts.resize(m::maximum_parts + 1, f.topology.parts.front());
    refusal(remove(f, "collector-1"), s::RemovalError::invalid_topology);
    f = fixture();
    f.kit[{s::Role::gear, m::maximum_dimension + 1, 0}] = 1;
    refusal(remove(f, "collector-1"), s::RemovalError::invalid_kit);

    f = fixture();
    std::erase_if(f.topology.parts, [](const auto& part) {
        return part.role == s::Role::processor;
    });
    f.topology.material_links.pop_back();
    f.state.stock.source = 15;
    f.state.stock.output = 1;
    refusal(remove(f, "collector-1"), s::RemovalError::invalid_material_state);

    f = fixture();
    f.topology.parts.front().geometry.center[0] = m::maximum_coordinate + 1;
    refusal(remove(f, "collector-1"), s::RemovalError::invalid_mechanics);
}

}  // namespace

int main() {
    try {
        enabled_local_removal();
        exact_part_and_link_refunds();
        occupied_and_carried_custody();
        source_and_disabled_view();
        malformed_and_overflow();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"invented_stationary_removal\","
                     "\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "stationary_test: " << error.what() << '\n';
        return 1;
    }
}
