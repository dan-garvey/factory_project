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

void one_tile_large_cogs() {
    for (const auto axis : {Axis::x, Axis::y, Axis::z}) {
        const auto axial = static_cast<std::size_t>(axis);
        const auto radial = (axial + 1) % 3;
        Point source{0, 0, 0}, first{0, 0, 0}, second{0, 0, 0};
        source[axial] = -4;
        second[radial] = 4;
        std::vector<Part> parts{{"source", Kind::hub, source, axis, 0, 0},
            {"first", Kind::gear, first, axis, 4, 0}, {"second", Kind::gear, second, axis, 4, 0}};
        motion(mechanical::evaluate(parts, {{"source", {1, 1}}}),
               "second", MotionState::rotating, {-1, 1});
        part(parts, "second").center[radial] = 8;
        motion(mechanical::evaluate(parts, {{"source", {1, 1}}}),
               "second", MotionState::unpowered, {0, 1});
    }
}

void belt_path_geometry() {
    using mechanical::BeltPathKind;
    for (const auto axle : {Axis::x, Axis::z}) {
        const auto travel = axle == Axis::x ? std::size_t{2} : std::size_t{0};
        Part a{"a", Kind::shaft, {0, 0, 0}, axle, 0, 2};
        Part b{"b", Kind::shaft, {0, 0, 0}, axle, 0, 2};
        for (const auto vertical : {-1, 0, 1}) for (const auto horizontal : {-1, 0, 1}) {
            if (vertical == 0 && horizontal == 0) continue;
            b.center = {}; b.center[1] = 8 * vertical; b.center[travel] = 8 * horizontal;
            const auto path = mechanical::belt_path(a, b);
            const auto kind = vertical == 0 ? BeltPathKind::horizontal :
                (horizontal == 0 ? BeltPathKind::vertical : BeltPathKind::inclined);
            check(path && path->kind == kind && path->tiles.size() == 3 &&
                  path->tiles.front() == a.center && path->tiles.back() == b.center,
                  "A straight or 45-degree belt has ordered global tile centers.");
            const auto reverse = mechanical::belt_path(b, a);
            auto expected = path->tiles; std::reverse(expected.begin(), expected.end());
            check(reverse && reverse->kind == kind && reverse->tiles == expected,
                  "Reversing endpoints reverses the path without changing its geometry.");
        }
        b.center = {}; b.center[1] = 4; b.center[travel] = 8;
        check(!mechanical::belt_path(a, b), "Unequal diagonal steps are refused.");
        b.center = {}; b.center[static_cast<std::size_t>(axle)] = 4;
        check(!mechanical::belt_path(a, b), "A path cannot run along its shaft axis.");
        b.center = {}; b.center[travel] = 76;
        check(mechanical::belt_path(a, b)->tiles.size() == 20, "Twenty tile centers are admitted.");
        b.center[travel] = 80;
        check(!mechanical::belt_path(a, b), "More than twenty tiles are refused.");
        b.center[travel] = 5;
        check(!mechanical::belt_path(a, b), "Off-grid endpoints are refused.");
        b.center = a.center;
        check(!mechanical::belt_path(a, b), "Coincident endpoints are refused.");
    }
    Part a{"a", Kind::shaft, {0, 0, 0}, Axis::y, 0, 2};
    Part b{"b", Kind::shaft, {0, 0, 8}, Axis::y, 0, 2};
    check(mechanical::belt_path(a, b)->kind == BeltPathKind::sideways,
          "Vertical shafts allow a straight sideways belt.");
    b.center = {8, 0, 8};
    check(!mechanical::belt_path(a, b), "Vertical shafts cannot form a diagonal sideways path.");
    b.center = {8, 0, 0}; b.axis = Axis::x;
    check(!mechanical::belt_path(a, b), "Endpoint shaft axes must match.");
    b.axis = Axis::y; b.center = {1000004, 0, 0};
    check(!mechanical::belt_path(a, b), "Out-of-bounds coordinates are refused before subtraction.");
}

void nonhorizontal_belt_power() {
    for (const auto axle : {Axis::x, Axis::y, Axis::z}) {
        const auto axial = static_cast<std::size_t>(axle);
        for (const Point end : {Point{0, 8, 0}, Point{8, 0, 0}, Point{0, 0, 8},
                                Point{8, 8, 0}, Point{-8, 8, 0}, Point{0, 8, 8}, Point{0, 8, -8}}) {
            Part a{"a", Kind::shaft, {0, 0, 0}, axle, 0, 2};
            Part c{"c", Kind::shaft, end, axle, 0, 2};
            const auto path = mechanical::belt_path(a, c);
            if (!path || path->kind == mechanical::BeltPathKind::horizontal) continue;
            auto source = a.center; source[axial] -= 4;
            auto sink = c.center; sink[axial] += 4;
            std::vector<Part> parts{a, {"b", Kind::shaft, path->tiles[1], axle, 0, 2}, c,
                {"source", Kind::hub, source, axle, 0, 0}, {"sink", Kind::hub, sink, axle, 0, 0}};
            const std::vector<mechanical::BeltSpan> belt{{"belt", "a", "c"}};
            const auto forward = mechanical::evaluate(parts, {{"source", {3, 2}}}, belt);
            motion(forward, "b", MotionState::rotating, {3, 2});
            motion(forward, "sink", MotionState::rotating, {3, 2});
            motion(mechanical::evaluate(parts, {{"sink", {-2, 3}}}, belt), "a", MotionState::rotating, {-2, 3});
            motion(mechanical::evaluate(parts, {{"source", {1, 1}}, {"sink", {-1, 1}}}, belt),
                   "b", MotionState::stalled, {0, 1});
            std::reverse(parts.begin(), parts.end());
            check(mechanical::evaluate(parts, {{"source", {3, 2}}}, {{"belt", "c", "a"}}) == forward,
                  "Nonhorizontal pulley engagements are stable under endpoint and input reversal.");
            part(parts, "b").axis = axle == Axis::x ? Axis::z : Axis::x;
            check(mechanical::evaluate(parts, {}, belt).error == Error::invalid_belt,
                  "A misaligned intermediate pulley obstructs a nonhorizontal belt.");
        }
    }
}

void horizontal_belt_spans() {
    for (const auto axle : {Axis::x, Axis::z}) {
        const auto travel = axle == Axis::x ? std::size_t{2} : std::size_t{0};
        const auto axial = static_cast<std::size_t>(axle);
        Point start{}, middle{}, end{}, source{}, sink{};
        middle[travel] = 8; end[travel] = 16;
        source[axial] = -4; sink = end; sink[axial] = 4;
        std::vector<Part> parts{{"a", Kind::shaft, start, axle, 0, 2},
            {"b", Kind::shaft, middle, axle, 0, 2}, {"c", Kind::shaft, end, axle, 0, 2},
            {"source", Kind::hub, source, axle, 0, 0}, {"sink", Kind::hub, sink, axle, 0, 0}};
        const std::vector<mechanical::BeltSpan> belt{{"belt", "a", "c"}};
        motion(mechanical::evaluate(parts, {{"source", {3, 2}}}), "c", MotionState::unpowered, {0, 1});
        const auto driven = mechanical::evaluate(parts, {{"source", {3, 2}}}, belt);
        motion(driven, "b", MotionState::rotating, {3, 2});
        motion(driven, "sink", MotionState::rotating, {3, 2});
        motion(mechanical::evaluate(parts, {{"sink", {-2, 3}}}, belt), "a", MotionState::rotating, {-2, 3});
        motion(mechanical::evaluate(parts, {{"source", {0, 1}}}, belt), "c", MotionState::stopped, {0, 1});
        motion(mechanical::evaluate(parts, {{"source", {1, 1}}, {"sink", {-1, 1}}}, belt),
               "b", MotionState::stalled, {0, 1});
        auto reversed_parts = parts;
        std::reverse(reversed_parts.begin(), reversed_parts.end());
        check(mechanical::evaluate(reversed_parts, {{"source", {3, 2}}}, {{"belt", "c", "a"}}) == driven,
              "Belt engagement and exact motion are independent of input and endpoint order.");
        auto without_middle = parts;
        without_middle.erase(std::find_if(without_middle.begin(), without_middle.end(),
            [](const Part& item) { return item.id == "b"; }));
        motion(mechanical::evaluate(without_middle, {{"source", {1, 1}}}, belt), "c", MotionState::rotating, {1, 1});
        auto blocked = parts; part(blocked, "b").kind = Kind::hub; part(blocked, "b").half_span = 0;
        const auto refusal = mechanical::evaluate(blocked, {{"source", {1, 1}}}, belt);
        check(refusal.error == Error::invalid_belt && refusal.motion.empty() && refusal.engagements.empty(),
              "An obstructed span is refused without partial motion.");
        blocked = parts; part(blocked, "b").axis = axle == Axis::x ? Axis::z : Axis::x;
        check(mechanical::evaluate(blocked, {}, belt).error == Error::invalid_belt,
              "A misaligned intermediate shaft obstructs the belt.");
        blocked = parts; part(blocked, "c").center[1] += 4;
        check(mechanical::evaluate(blocked, {}, belt).error == Error::invalid_belt,
              "An unequal slope is refused.");
        blocked = parts; part(blocked, "c").center[travel] = 80;
        check(mechanical::evaluate(blocked, {}, belt).error == Error::invalid_belt,
              "The bounded profile refuses more than twenty tiles.");
        part(blocked, "c").center[travel] = 76;
        part(blocked, "sink").center[travel] = 76;
        motion(mechanical::evaluate(blocked, {{"source", {1, 1}}}, belt), "sink", MotionState::rotating, {1, 1});
        blocked = parts; part(blocked, "c").center[travel] += 1;
        check(mechanical::evaluate(blocked, {}, belt).error == Error::invalid_belt,
              "A shaft endpoint between common tile centers is refused.");
        blocked = parts; part(blocked, "c").kind = Kind::hub; part(blocked, "c").half_span = 0;
        check(mechanical::evaluate(blocked, {}, belt).error == Error::invalid_belt,
              "A machine hub cannot impersonate an endpoint shaft tile.");
        check(mechanical::evaluate(parts, {}, {{"belt", "a", "c"}, {"second", "a", "b"}}).error == Error::invalid_belt,
              "Two spans cannot occupy the same belt tile.");
        check(mechanical::evaluate(parts, {}, {{"belt", "a", "missing"}}).error == Error::invalid_belt,
              "A span requires both real shaft identities.");
    }
}

}  // namespace

int main() {
    try {
        direction_and_geometry();
        shafts_and_sources();
        one_tile_shaft_faces();
        one_tile_large_cogs();
        belt_path_geometry();
        nonhorizontal_belt_power();
        horizontal_belt_spans();
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
