#include "factory/mechanics.hpp"

#include <algorithm>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace mechanical = factory::mechanics;
using mechanical::Axis;
using mechanical::Drive;
using mechanical::Error;
using mechanical::Integer;
using mechanical::Kind;
using mechanical::MotionState;
using mechanical::Part;
using mechanical::Point;
using mechanical::Rate;
using mechanical::Result;

namespace {
int checks = 0;

void check(bool condition, const std::string& label) {
    if (!condition) throw std::runtime_error(label);
    ++checks;
}

Part gear(const std::string& id, Point center, Integer teeth, Axis axis = Axis::z) {
    return {id, Kind::gear, center, axis, teeth, 0};
}

Part shaft(const std::string& id, Point center, Integer half_span = 1) {
    return {id, Kind::shaft, center, Axis::z, 0, half_span};
}

Part hub(const std::string& id, Point center) {
    return {id, Kind::hub, center, Axis::z, 0, 0};
}

std::vector<Part> baseline() {
    return {gear("A", {0, 0, 0}, 20), gear("B", {60, 0, 0}, 40),
            shaft("input-shaft", {0, 0, 0}), shaft("output-shaft", {60, 0, 0}),
            hub("drive", {0, 0, -1}), hub("sink", {60, 0, 1})};
}

Part& part(std::vector<Part>& parts, const std::string& id) {
    const auto found = std::find_if(parts.begin(), parts.end(),
                                   [&](const Part& value) { return value.id == id; });
    if (found == parts.end()) throw std::runtime_error("The invented fixture is missing a part.");
    return *found;
}

void output_at(std::vector<Part>& parts, Integer x) {
    for (const auto& id : {"B", "output-shaft", "sink"}) part(parts, id).center[0] = x;
}

void motion(const Result& result, const std::string& id, MotionState state, Rate rate) {
    check(result.accepted(), "The geometric fixture is accepted.");
    const auto found = result.motion.find(id);
    check(found != result.motion.end(), "The literal part has a motion result.");
    check(found->second.state == state, "The literal component state matches.");
    check(found->second.rate == rate, "The exact signed rational rate matches.");
}

void refusal(const std::vector<Part>& parts, const std::vector<Drive>& drives, Error error) {
    const auto original_parts = parts;
    const auto original_drives = drives;
    const auto result = mechanical::evaluate(parts, drives);
    check(!result.accepted() && result.error == error, "The invalid fixture has its expected refusal.");
    check(result.motion.empty() && result.engagements.empty() && result.components.empty(),
          "A refusal publishes no partial motion, engagement or component result.");
    check(parts == original_parts && drives == original_drives, "Refusal preserves the input values.");
}

void direction_and_geometry() {
    const auto original = baseline();
    const std::vector<Drive> source{{"drive", {1, 1}}};
    const auto result = mechanical::evaluate(original, source);
    motion(result, "A", MotionState::rotating, {1, 1});
    motion(result, "B", MotionState::rotating, {-1, 2});
    motion(result, "sink", MotionState::rotating, {-1, 2});
    check(result.engagements.size() == 5 && result.components.size() == 1,
          "Six physical parts form exactly five engagements and one component.");
    check(original == baseline() && source == std::vector<Drive>{{"drive", {1, 1}}},
          "A successful solve preserves caller geometry and sources.");

    auto changed = original;
    part(changed, "B").teeth = 20;
    motion(mechanical::evaluate(changed, source), "sink", MotionState::unpowered, {0, 1});
    output_at(changed, 40);
    motion(mechanical::evaluate(changed, source), "sink", MotionState::rotating, {-1, 1});

    changed = original;
    output_at(changed, 100);
    changed.push_back(gear("idler", {40, 0, 0}, 20));
    motion(mechanical::evaluate(changed, source), "sink", MotionState::rotating, {1, 2});
    check(mechanical::evaluate(changed, source).engagements.size() == 6,
          "The idler adds a real second mesh rather than changing a parity option.");

    changed = original;
    part(changed, "B").axis = Axis::x;
    motion(mechanical::evaluate(changed, source), "sink", MotionState::unpowered, {0, 1});
    changed = original;
    part(changed, "B").center[2] = 1;
    motion(mechanical::evaluate(changed, source), "sink", MotionState::unpowered, {0, 1});
    changed = original;
    output_at(changed, 61);
    motion(mechanical::evaluate(changed, source), "sink", MotionState::unpowered, {0, 1});
    changed = original;
    output_at(changed, 59);
    refusal(changed, source, Error::overlapping_gears);

    // Rotate the entire literal fixture into the other two canonical planes.
    for (const auto axis : {Axis::x, Axis::y}) {
        changed = original;
        for (auto& value : changed) {
            const auto old = value.center;
            value.center = axis == Axis::x ? Point{old[2], old[0], old[1]}
                                          : Point{old[1], old[2], old[0]};
            value.axis = axis;
        }
        motion(mechanical::evaluate(changed, source), "sink", MotionState::rotating, {-1, 2});
    }

    auto reversed = original;
    std::reverse(reversed.begin(), reversed.end());
    check(mechanical::evaluate(reversed, source) == result,
          "Input order cannot change canonical geometry, engagements or motion.");
}

void shafts_and_sources() {
    const std::vector<Drive> source{{"drive", {1, 1}}};
    for (const auto axis : {Axis::x, Axis::y, Axis::z}) {
        const auto coordinate = static_cast<std::size_t>(axis);
        for (const Integer direction : {-1, 1}) {
            Point cog_center{}, sink_center{};
            cog_center[coordinate] = direction * 4;
            sink_center[coordinate] = direction * 8;
            std::vector<Part> direct{
                {"drive", Kind::hub, {0, 0, 0}, axis, 0, 0},
                gear("cog", cog_center, 2, axis),
                {"sink", Kind::hub, sink_center, axis, 0, 0}};
            motion(mechanical::evaluate(direct, source), "cog", MotionState::rotating, {1, 1});
            motion(mechanical::evaluate(direct, source), "sink", MotionState::rotating, {1, 1});
            auto gap = direct;
            gap[1].center[coordinate] += direction;
            motion(mechanical::evaluate(gap, source), "cog", MotionState::unpowered, {0, 1});
            auto offset = direct;
            offset[1].center[(coordinate + 1) % 3] = 1;
            motion(mechanical::evaluate(offset, source), "cog", MotionState::unpowered, {0, 1});
            auto misaligned = direct;
            misaligned[1].axis = static_cast<Axis>((coordinate + 1) % 3);
            motion(mechanical::evaluate(misaligned, source), "cog", MotionState::unpowered, {0, 1});
        }
    }
    auto changed = baseline();
    part(changed, "input-shaft").center[2] = 1;
    motion(mechanical::evaluate(changed, source), "A", MotionState::unpowered, {0, 1});
    changed = baseline();
    part(changed, "output-shaft").center[0] += 1;
    motion(mechanical::evaluate(changed, source), "B", MotionState::rotating, {-1, 2});
    motion(mechanical::evaluate(changed, source), "sink", MotionState::unpowered, {0, 1});

    changed = baseline();
    part(changed, "drive").center[2] = -3;
    changed.push_back(shaft("bridge", {0, 0, -2}));
    motion(mechanical::evaluate(changed, source), "sink", MotionState::rotating, {-1, 2});
    part(changed, "bridge").center[2] = -3;
    motion(mechanical::evaluate(changed, source), "sink", MotionState::unpowered, {0, 1});

    // A source hub next to otherwise meshed gears has no invisible connection.
    const std::vector<Part> no_shafts{
        gear("A", {0, 0, 0}, 20), gear("B", {60, 0, 0}, 40),
        hub("drive", {0, 0, -1}), hub("sink", {60, 0, 1})};
    motion(mechanical::evaluate(no_shafts, source), "B", MotionState::unpowered, {0, 1});
    motion(mechanical::evaluate(no_shafts, source), "sink", MotionState::unpowered, {0, 1});

    motion(mechanical::evaluate(baseline(), {}), "sink", MotionState::unpowered, {0, 1});
    motion(mechanical::evaluate(baseline(), {{"drive", {0, 17}}}),
           "sink", MotionState::stopped, {0, 1});
    motion(mechanical::evaluate(baseline(), {{"drive", {-1, 1}}}),
           "sink", MotionState::rotating, {1, 2});
    motion(mechanical::evaluate(baseline(), {{"drive", {2, 4}}}),
           "sink", MotionState::rotating, {-1, 4});

    motion(mechanical::evaluate(baseline(), {{"drive", {1, 1}}, {"sink", {-1, 2}}}),
           "B", MotionState::rotating, {-1, 2});
    motion(mechanical::evaluate(baseline(), {{"drive", {1, 1}}, {"sink", {1, 1}}}),
           "B", MotionState::stalled, {0, 1});
    motion(mechanical::evaluate(baseline(), {{"drive", {0, 1}}, {"sink", {1, 1}}}),
           "drive", MotionState::stalled, {0, 1});
}

void local_conflicts() {
    // The 30/40/50 center triangle has tangent radii 10/20/30.
    // Three external meshes cannot satisfy a nonzero source rate.
    std::vector<Part> parts{
        gear("A", {0, 0, 0}, 10), gear("B", {30, 0, 0}, 20),
        gear("C", {0, 40, 0}, 30), shaft("input-shaft", {0, 0, 0}),
        hub("drive", {0, 0, -1}),
        gear("independent-A", {1000, 0, 0}, 20),
        gear("independent-B", {1040, 0, 0}, 20),
        shaft("independent-input", {1000, 0, 0}),
        shaft("independent-output", {1040, 0, 0}),
        hub("other-drive", {1000, 0, -1}), hub("other-sink", {1040, 0, 1})};
    const std::vector<Drive> drives{{"drive", {1, 1}}, {"other-drive", {2, 1}}};
    const auto result = mechanical::evaluate(parts, drives);
    motion(result, "A", MotionState::stalled, {0, 1});
    motion(result, "C", MotionState::stalled, {0, 1});
    motion(result, "other-sink", MotionState::rotating, {-2, 1});
    check(result.components.size() == 2, "A local ratio conflict does not join unrelated machinery.");

    std::reverse(parts.begin(), parts.end());
    auto reversed_drives = drives;
    std::reverse(reversed_drives.begin(), reversed_drives.end());
    check(mechanical::evaluate(parts, reversed_drives) == result,
          "Conflicting and independent components do not depend on iteration order.");

    motion(mechanical::evaluate(parts, {{"drive", {0, 1}}}),
           "C", MotionState::stopped, {0, 1});
}

void bounded_diagnostics() {
    auto parts = baseline();
    const std::string oversized(1024 * 1024, 'x');
    part(parts, "A").id = oversized;
    const auto invalid_part = mechanical::evaluate(parts, {{"drive", {1, 1}}});
    check(invalid_part.error == Error::invalid_part && invalid_part.subject.empty(),
          "An oversized part identifier is refused without retaining a diagnostic copy.");
    check(invalid_part.motion.empty() && invalid_part.engagements.empty() && invalid_part.components.empty(),
          "The oversized identifier publishes no partial result.");
    check(parts.front().id == oversized, "Diagnostic refusal preserves the caller's oversized identifier.");

    const auto invalid_drive = mechanical::evaluate(baseline(), {{oversized, {1, 1}}});
    check(invalid_drive.error == Error::invalid_drive && invalid_drive.subject.empty(),
          "An oversized source identifier is refused before lookup or diagnostic copying.");
    const auto embedded_null = mechanical::evaluate(baseline(), {{std::string("d\0rive", 6), {1, 1}}});
    check(embedded_null.error == Error::invalid_drive && embedded_null.subject.empty(),
          "A source identifier with a null byte is not retained in a diagnostic.");
    const std::string boundary(128, 'b');
    const auto bounded = mechanical::evaluate(baseline(), {{boundary, {1, 1}}});
    check(bounded.error == Error::invalid_drive && bounded.subject == boundary,
          "A valid boundary-length missing identity remains an exact bounded diagnostic.");
    const auto missing = mechanical::evaluate(baseline(), {{"missing", {1, 1}}});
    check(missing.error == Error::invalid_drive && missing.subject == "missing",
          "Ordinary valid missing identities retain useful diagnostics.");
}

void validation_and_arithmetic() {
    const std::vector<Drive> source{{"drive", {1, 1}}};
    auto changed = baseline();
    changed.push_back(changed.front());
    refusal(changed, source, Error::duplicate_identity);
    changed = baseline();
    part(changed, "A").id.clear();
    refusal(changed, source, Error::invalid_part);
    changed = baseline();
    part(changed, "A").id = std::string("a\0b", 3);
    refusal(changed, source, Error::invalid_part);
    changed = baseline();
    part(changed, "A").id = std::string(129, 'a');
    refusal(changed, source, Error::invalid_part);

    for (const auto teeth : {Integer{0}, Integer{-1}, mechanical::maximum_dimension + 1}) {
        changed = baseline();
        part(changed, "A").teeth = teeth;
        refusal(changed, source, Error::invalid_part);
    }
    changed = baseline();
    part(changed, "A").half_span = 1;
    refusal(changed, source, Error::invalid_part);
    changed = baseline();
    part(changed, "drive").teeth = 1;
    refusal(changed, source, Error::invalid_part);
    changed = baseline();
    part(changed, "input-shaft").teeth = 1;
    refusal(changed, source, Error::invalid_part);
    for (const auto span : {Integer{0}, Integer{-1}, mechanical::maximum_dimension + 1}) {
        changed = baseline();
        part(changed, "input-shaft").half_span = span;
        refusal(changed, source, Error::invalid_part);
    }
    changed = baseline();
    part(changed, "A").center[0] = std::numeric_limits<Integer>::min();
    refusal(changed, source, Error::invalid_part);
    changed = baseline();
    part(changed, "input-shaft").center[2] = mechanical::maximum_coordinate;
    refusal(changed, source, Error::invalid_part);
    changed = baseline();
    part(changed, "A").kind = static_cast<Kind>(99);
    refusal(changed, source, Error::invalid_part);
    changed = baseline();
    part(changed, "A").axis = static_cast<Axis>(99);
    refusal(changed, source, Error::invalid_part);
    refusal(baseline(), {{"missing", {1, 1}}}, Error::invalid_drive);
    refusal(baseline(), {{"A", {1, 1}}}, Error::invalid_drive);
    refusal(baseline(), {{"drive", {1, 0}}}, Error::invalid_drive);
    refusal(baseline(), {{"drive", {1, -1}}}, Error::invalid_drive);
    refusal(baseline(), {{"drive", {1, 1}}, {"drive", {1, 1}}}, Error::invalid_drive);

    std::vector<Part> excessive;
    for (std::size_t i = 0; i <= mechanical::maximum_parts; ++i)
        excessive.push_back(hub("part-" + std::to_string(i), {0, 0, 0}));
    refusal(excessive, {}, Error::too_many_parts);

    const auto low = std::numeric_limits<Integer>::min();
    const auto high = std::numeric_limits<Integer>::max();
    motion(mechanical::evaluate(baseline(), {{"drive", {low, 1}}}),
           "B", MotionState::rotating, {Integer{4611686018427387904}, 1});
    changed = baseline();
    part(changed, "B").teeth = 20;
    output_at(changed, 40);
    refusal(changed, {{"drive", {low, 1}}}, Error::rate_overflow);
    refusal(baseline(), {{"drive", {1, high}}}, Error::rate_overflow);

    changed = baseline();
    part(changed, "A").teeth = 40;
    part(changed, "B").teeth = 60;
    output_at(changed, 100);
    motion(mechanical::evaluate(changed, {{"drive", {10, 9}}}),
           "B", MotionState::rotating, {-20, 27});

    check(mechanical::evaluate({}, {}).accepted(), "An empty mechanism has no fabricated power.");
}

void one_tile_shaft_faces() {
    for (const auto axis : {Axis::x, Axis::y, Axis::z}) {
        for (const Integer sign : {-1, 1}) {
            const auto axial = static_cast<std::size_t>(axis);
            Point source{0, 0, 0}, shaft_center{0, 0, 0}, cog_center{0, 0, 0};
            shaft_center[axial] = 4 * sign;
            cog_center[axial] = 8 * sign;
            std::vector<Part> parts{{"source", Kind::hub, source, axis, 0, 0},
                {"shaft", Kind::shaft, shaft_center, axis, 0, 2},
                {"cog", Kind::gear, cog_center, axis, 2, 0}};
            motion(mechanical::evaluate(parts, {{"source", {1, 1}}}),
                   "cog", MotionState::rotating, {1, 1});
            part(parts, "cog").center[axial] += 4 * sign;
            motion(mechanical::evaluate(parts, {{"source", {1, 1}}}),
                   "cog", MotionState::unpowered, {0, 1});
            part(parts, "cog").center[axial] -= 4 * sign;
            part(parts, "shaft").center[(axial + 1) % 3] += 4;
            motion(mechanical::evaluate(parts, {{"source", {1, 1}}}),
                   "cog", MotionState::unpowered, {0, 1});
        }
    }
}

}  // namespace

int main() {
    try {
        direction_and_geometry();
        shafts_and_sources();
        one_tile_shaft_faces();
        local_conflicts();
        bounded_diagnostics();
        validation_and_arithmetic();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"invented_geometric_kinematics\","
                  << "\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
