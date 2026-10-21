#include "factory/slotted_clearance.hpp"
#include "factory/slotted_clearance_workbench.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>
#include <stdexcept>

namespace a = factory::slotted_clearance;
namespace b = factory::slotted_bank;
namespace c = factory::clearance;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
c::Fraction fraction(I numerator, I denominator) {
    const auto divisor = std::gcd(numerator, denominator);
    return {numerator / divisor, denominator / divisor};
}
std::vector<b::Link> links() { return {{3, {0, 4, 2, 1}}, {7, {-1, 2, 1, 2}}}; }
b::State initial() { return {0, {{3, 0}, {7, 0}}}; }
c::Box box(I x, I lane, g::Axis axis = g::Axis::x) {
    c::Box result{{x, lane, 0}, {x + 1, lane + 1, 1}};
    std::swap(result.minimum[0], result.minimum[static_cast<std::size_t>(axis)]);
    std::swap(result.maximum[0], result.maximum[static_cast<std::size_t>(axis)]);
    return result;
}
a::Rig rig(g::Axis axis = g::Axis::x) { return {axis, box(0, -3, axis), {{3, box(0, 0, axis)}, {7, box(0, 3, axis)}}}; }
a::Blocked blocked(const a::Plan& plan) {
    check(std::holds_alternative<a::Blocked>(plan), "A continuous obstruction produces an original-state-only blocked result.");
    return std::get<a::Blocked>(plan);
}
b::Advance advance(const a::Plan& plan) {
    check(std::holds_alternative<b::Advance>(plan), "A clear rig admits the exact bank advance.");
    return std::get<b::Advance>(plan);
}
void refuse(const a::Plan& plan, a::Error expected) {
    check(std::holds_alternative<a::Refusal>(plan) && std::get<a::Refusal>(plan).reason == expected,
          "Malformed inputs refuse the entire rig without a blocked or advanced partial result.");
}
void literals() {
    auto profile = links();
    auto bodies = rig();
    auto state = initial();
    std::vector<c::Obstacle> obstacles{{11, box(2, 0)}};
    const auto crossing = blocked(a::prepare(profile, state, bodies, {{32}, obstacles}));
    check(crossing.state == state && crossing.follower == b::Id{3} && crossing.hit == c::Hit{11, {1, 16}, false},
          "Follower contact includes its slack delay and blocks every original position.");
    check(c::sweep(box(3, 0), {}, obstacles).clear(), "The deliberately chosen final pose alone is clear despite the obstructed path.");
    obstacles[0].box = box(4, 0);
    const auto clear = advance(a::prepare(profile, state, bodies, {{32}, obstacles}));
    check(clear == std::get<b::Advance>(b::prepare(profile, state, {32})), "Destination-only touch admits the complete unchanged bank proposal.");
    check(advance(a::prepare(profile, clear.next, bodies, {{0}, obstacles})).next == b::State{0, {{3, 2}, {7, 1}}},
          "Withdrawing from destination tangency returns the same rig without penetration.");
    obstacles[0].box = box(2, 0);
    bodies.followers[0].at_zero = box(0, 6);
    check(advance(a::prepare(profile, state, bodies, {{32}, obstacles})).next == clear.next,
          "Raising the first guide is a geometrically distinct solution with the same mechanical motion.");
    bodies = rig(); obstacles[0].box = box(2, 1);
    check(std::holds_alternative<b::Advance>(a::prepare(profile, state, bodies, {{32}, obstacles})), "Sliding exactly along an obstacle face is clear.");
    obstacles[0].box = box(2, 0);
    const b::State reverse{4, {{3, 3}, {7, 2}}};
    check(blocked(a::prepare(profile, reverse, bodies, {{0}, obstacles})).hit == c::Hit{11, {3, 4}, false},
          "A reverse follower begins entering a touching obstacle only after its reverse slack interval.");
    check(std::holds_alternative<b::Hold>(a::prepare(profile, reverse, bodies, {{0, false}, obstacles})),
          "A paused tangent body has no positive interior overlap.");
    profile[0].slot.front = 3; profile[1].slot.front = 0; profile[1].slot.upper = 4;
    obstacles = {{29, box(1, 0)}, {11, box(2, 3)}};
    const auto ordering = blocked(a::prepare(profile, state, bodies, {{32}, obstacles}));
    check(ordering.follower == b::Id{7} && ordering.hit == c::Hit{11, {1, 32}, false},
          "An early local zero-time contact after long slack cannot outrank a genuinely earlier global contact.");
    std::reverse(profile.begin(), profile.end()); std::reverse(bodies.followers.begin(), bodies.followers.end()); std::reverse(obstacles.begin(), obstacles.end());
    check(blocked(a::prepare(profile, state, bodies, {{32}, obstacles})) == ordering, "Profile, shape and obstacle order cannot change the global contact witness.");
    profile = links(); bodies = rig();
    profile[0].slot.front = 0; profile[1].slot.front = 0;
    obstacles = {{100, box(1, 0)}, {1, box(1, 3)}, {99, box(1, 0)}};
    const auto tied = blocked(a::prepare(profile, state, bodies, {{32}, obstacles}));
    check(tied.follower == b::Id{3} && tied.hit == c::Hit{99, {0, 1}, false}, "Time ties choose follower identity before obstacle identity, then the lowest obstacle for that body.");
    obstacles.push_back({500, box(1, -3)});
    const auto pin = blocked(a::prepare(profile, state, bodies, {{32}, obstacles}));
    check(!pin.follower && pin.hit == c::Hit{500, {0, 1}, false}, "A simultaneous pin contact wins before follower contacts.");
    profile = links(); bodies = rig(); profile[0].slot.front = 3;
    obstacles = {{11, box(0, 0)}};
    for (const bool powered : {false, true}) {
        const auto overlap = blocked(a::prepare(profile, state, bodies, {{32, powered}, obstacles}));
        check(overlap.hit == c::Hit{11, {0, 1}, true} && overlap.state == state,
              "Initial penetration is time zero even when powered off or before a follower's delayed travel.");
    }
    const auto greatest = std::numeric_limits<b::Id>::max();
    profile = {{greatest, {0, 4, 2, 1}}}; bodies.followers = {{greatest, box(0, 0)}};
    state.followers = {{greatest, 0}}; obstacles = {{1, box(2, 0)}};
    check(blocked(a::prepare(profile, state, bodies, {{32}, obstacles})).follower == greatest,
          "Opaque maximum follower identities are not narrowed into pin tags or signed indices.");
    profile = {{3, {-g::maximum_coordinate + 2, g::maximum_coordinate - 2, 2, 1}}};
    bodies = rig(); bodies.followers.resize(1);
    state = {-g::maximum_coordinate, {{3, -g::maximum_coordinate + 2}}}; obstacles = {{1, box(0, 0)}};
    check(blocked(a::prepare(profile, state, bodies, {{g::maximum_coordinate - 1}, obstacles})).hit ==
          c::Hit{1, {g::maximum_coordinate, 2 * g::maximum_coordinate - 1}, false},
          "The full supported coordinate span maps a delayed contact without overflowing fraction products.");
}
bool overlap2(const c::Box& zero, g::Axis axis, I position2, const c::Box& obstacle) {
    for (std::size_t dimension = 0; dimension < 3; ++dimension) {
        const I offset = dimension == static_cast<std::size_t>(axis) ? position2 : 0;
        if (2 * zero.maximum[dimension] + offset <= 2 * obstacle.minimum[dimension] ||
            2 * zero.minimum[dimension] + offset >= 2 * obstacle.maximum[dimension]) return false;
    }
    return true;
}
void oracle() {
    std::size_t cases{};
    const auto profile = links();
    const std::array<b::State, 4> starts{{initial(), {2, {{3, 1}, {7, 0}}}, {4, {{3, 3}, {7, 2}}}, {0, {{3, 2}, {7, 1}}}}};
    for (const auto axis : {g::Axis::x, g::Axis::y, g::Axis::z}) for (const auto& state : starts)
    for (I destination = -6; destination <= 6; ++destination) for (const bool powered : {false, true})
    for (I obstruction = -2; obstruction <= 6; ++obstruction) for (const I lane : {I{-3}, I{0}, I{3}, I{1}}) {
        auto bodies = rig(axis);
        if (cases % 2 == 0) std::reverse(bodies.followers.begin(), bodies.followers.end());
        const std::array<c::Box, 3> boxes{{box(0, -3, axis), box(0, 0, axis), box(0, 3, axis)}};
        const std::array<c::Obstacle, 1> obstacles{{{17, box(obstruction, lane, axis)}}};
        const auto actual = a::prepare(profile, state, bodies, {{destination, powered}, obstacles});
        std::optional<a::Blocked> expected;
        const std::array<I, 3> start_positions{state.pin, state.followers[0].position, state.followers[1].position};
        for (std::size_t body = 0; body < boxes.size(); ++body) {
            if (overlap2(boxes[body], axis, 2 * start_positions[body], obstacles[0].box)) {
                expected = a::Blocked{state, body == 0 ? std::optional<b::Id>{} : body == 1 ? b::Id{3} : b::Id{7}, {17, {0, 1}, true}};
                break;
            }
        }
        auto walked = state;
        const I direction = destination > state.pin ? 1 : -1;
        const I count = destination > state.pin ? destination - state.pin : state.pin - destination;
        const I stop = direction > 0 ? 4 : -2;
        if (!expected && powered && count != 0 && state.pin != stop) {
            for (I step = 1; step <= count; ++step) {
                const auto previous = walked;
                walked.pin += direction;
                for (std::size_t follower = 0; follower < profile.size(); ++follower) {
                    const auto& slot = profile[follower].slot;
                    auto& position = walked.followers[follower].position;
                    if (walked.pin > position + slot.front) ++position;
                    if (walked.pin < position - slot.back) --position;
                }
                const std::array<I, 3> middle2{previous.pin + walked.pin,
                    previous.followers[0].position + walked.followers[0].position,
                    previous.followers[1].position + walked.followers[1].position};
                // Independent exact grid oracle: every contact plane is at an
                // integer input distance. Test the open half-step, including
                // slack, to find entry; this is not endpoint-only sampling.
                for (std::size_t body = 0; body < boxes.size(); ++body) {
                    if (overlap2(boxes[body], axis, middle2[body], obstacles[0].box)) {
                        expected = a::Blocked{state, body == 0 ? std::optional<b::Id>{} : body == 1 ? b::Id{3} : b::Id{7},
                                             {17, fraction(step - 1, count), false}};
                        break;
                    }
                }
                if (expected || walked.pin == stop) break;
            }
        }
        if (expected) check(blocked(actual) == *expected, "Blocked subject, original-time entry and unchanged full state match the independent half-grid path.");
        else {
            const auto parent = b::prepare(profile, state, {destination, powered});
            if (const auto* next = std::get_if<b::Advance>(&parent))
                check(advance(actual) == *next && next->next == walked, "Clear admission preserves every parent event and the independently walked final state.");
            else check(std::holds_alternative<b::Hold>(actual) && std::get<b::Hold>(actual) == std::get<b::Hold>(parent) && walked == state,
                       "A clear paused, resting or limited bank preserves the exact parent hold.");
        }
        check(state.followers.size() == 2 && state.followers[0].id == 3 && state.followers[1].id == 7,
              "Admission never replaces or reorders the original follower identities.");
        ++cases;
    }
    check(cases == 11232, "All declared axes, histories, powers, destinations, obstacle positions and lane/grazing cases were covered.");
}
void invalid() {
    auto profile = links(); auto state = initial(); auto bodies = rig();
    std::vector<c::Obstacle> obstacles{{1, box(0, 0)}};
    bodies.followers[1].at_zero.minimum[0] = std::numeric_limits<I>::min();
    const auto late = a::prepare(profile, state, bodies, {{32}, obstacles});
    refuse(late, a::Error::invalid_geometry);
    check(std::get<a::Refusal>(late).follower == b::Id{7}, "A later malformed shape is not hidden by an earlier overlapping body.");
    bodies = rig(); bodies.followers[1].at_zero = {{g::maximum_coordinate - 1, 3, 0}, {g::maximum_coordinate, 4, 1}};
    state = {4, {{3, 3}, {7, 2}}}; obstacles[0].box = box(3, 0);
    const auto escaped = a::prepare(profile, state, bodies, {{0, false}, obstacles});
    refuse(escaped, a::Error::query_refused);
    check(std::get<a::Refusal>(escaped).follower == b::Id{7}, "A later translated box outside the grid refuses even after an earlier penetration and while paused.");
    state = initial(); bodies = rig(); bodies.axis = static_cast<g::Axis>(9);
    refuse(a::prepare(profile, state, bodies, {{0}, {}}), a::Error::invalid_rig);
    bodies = rig(); bodies.followers.pop_back();
    refuse(a::prepare(profile, state, bodies, {{0}, {}}), a::Error::invalid_rig);
    bodies = rig(); bodies.followers[1].id = 3;
    refuse(a::prepare(profile, state, bodies, {{0, false}, {}}), a::Error::invalid_rig);
    bodies = rig(); bodies.followers[0].id = 0;
    refuse(a::prepare(profile, state, bodies, {{0}, {}}), a::Error::invalid_rig);
    bodies = rig();
    refuse(a::prepare(profile, state, bodies, {{std::numeric_limits<I>::min(), false}, {}}), a::Error::bank_refused);
    obstacles = {{1, box(0, 0)}, {1, box(3, 0)}};
    refuse(a::prepare(profile, state, bodies, {{0, false}, obstacles}), a::Error::query_refused);
    obstacles = {{1, box(0, 0)}, {0, box(3, 0)}};
    refuse(a::prepare(profile, state, bodies, {{0}, obstacles}), a::Error::query_refused);
    obstacles.assign(g::maximum_parts + 1, {1, box(0, 0)});
    refuse(a::prepare(profile, state, bodies, {{0}, obstacles}), a::Error::query_refused);
    obstacles = {{1, box(2, 0)}};
    const auto owned = blocked(a::prepare(profile, state, bodies, {{32}, obstacles}));
    profile.clear(); state.followers.clear(); bodies.followers.clear(); obstacles.clear();
    check(owned.state == initial() && owned.hit.obstacle == 1 && owned.follower == b::Id{3},
          "The retained blocked witness owns its original state after all caller containers are destroyed.");
}
struct Output { int code; std::string text; std::string errors; };
Output play(std::initializer_list<std::string_view> args, const std::string& commands) {
    std::istringstream input(commands);
    std::ostringstream out, errors;
    const int code = a::workbench(std::span(args.begin(), args.size()), input, out, errors);
    return {code, out.str(), errors.str()};
}
void caller() {
    const auto obstructed = play({"play"}, "move 32\nstatus\nquit\n");
    check(obstructed.code == 1 && obstructed.errors.empty() && obstructed.text.find("Blocked follower 3 by obstacle 11 at 1/16") != std::string::npos &&
          obstructed.text.find("Pin 4;") == std::string::npos, "The actual caller exposes the continuous witness and adopts no partial move.");
    const auto corrected = play({"play"}, "move 32\nlayout setback\nmove 32\nmove 0\nquit\n");
    check(corrected.code == 0 && corrected.errors.empty() && corrected.text.find("Blocked follower 3") != std::string::npos &&
          corrected.text.find("Pin 0; A 2; B 1; layout setback") != std::string::npos, "Moving the crate after a failed stroke resumes the same original rig.");
    check(play({"play"}, "layout raised\nmove 32\nmove 0\n").code == 0 && play({"play"}, "layout setback\nmove 32\nmove 0\n").code == 0,
          "Raising a guide and moving an obstacle provide two spatial solution families.");
    const auto paused = play({"play"}, "power off\nmove 32\npower on\nlayout raised\nmove 4\nmove 0\n");
    check(paused.code == 0 && paused.text.find("Hold unpowered") != std::string::npos && paused.text.find("Limit 7 at 1/1") != std::string::npos,
          "A paused full stroke creates no debt in the newly admitted shorter command.");
    check(play({"play"}, "layout raised\nmove 4\nmove 1\nstatus\n").code == 1, "Partial return cannot finish before the pin is home.");
    const auto edit = play({"play"}, "layout setback\nmove 4\nlayout raised\nstatus\n");
    check(edit.code == 1 && edit.text.find("BOTH original followers home") != std::string::npos,
          "Configuration edits cannot relocate an already-offset rig to bypass its obstacle.");
    check(play({"play"}, "layout raised\nmove -32\nmove 32\nmove 0\n").code == 0, "A clear negative service stroke recovers without a new rig or reset.");
    check(play({"play"}, "move nope\nmove 33\nmove 1 extra\nlayout missing\n").code == 1, "Malformed commands cannot admit a partial stroke.");
    const auto oversized = play({"play"}, "layout raised" + std::string(600, ' ') + "\nmove 32\n");
    check(oversized.code == 1 && oversized.text.find("command exceeds 512 bytes") != std::string::npos && oversized.text.find("Blocked follower 3") != std::string::npos,
          "An oversized layout prefix cannot secretly remove the obstruction.");
    check(play({"missing"}, "").code == 2 && play({"list"}, "").code == 0 && play({"--help"}, "").code == 0 && play({"play"}, "").code == 1,
          "Startup, catalogue and unfinished EOF preserve their distinct outcomes.");
    std::istringstream input; input.setstate(std::ios::badbit);
    std::ostringstream out, errors;
    const std::array<std::string_view, 1> args{"play"};
    check(a::workbench(args, input, out, errors) == 2, "Input failure cannot claim a completed spatial setup.");
    std::istringstream good; out.setstate(std::ios::badbit);
    check(a::workbench(args, good, out, errors) == 2, "Output failure cannot claim success.");
}
}  // namespace
int main() {
    try {
        literals(); oracle(); invalid(); caller();
        std::cout << checks << " slotted-clearance assertions passed, including 11232 independent half-grid joint-path cases.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " assertions: " << error.what() << '\n';
        return 1;
    }
}
