#include "factory/screw_drive.hpp"
#include "factory/screw_workbench.hpp"

#include <algorithm>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>
#include <stdexcept>

namespace s = factory::screw_drive;
namespace k = factory::geared_cycle;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
s::Advance advance(s::Plan plan) {
    check(std::holds_alternative<s::Advance>(plan), "A nonempty applied screw motion is returned.");
    return std::get<s::Advance>(std::move(plan));
}
s::Hold hold(s::Plan plan, s::Stop stop, s::Turns turns) {
    check(std::holds_alternative<s::Hold>(plan), "A stopped actuator publishes no turn events.");
    auto result = std::get<s::Hold>(std::move(plan));
    check(result.reason == stop && result.turns == turns, "The stop reason and original unwrapped phase are preserved.");
    return result;
}
void refused(const s::Plan& plan, s::Error reason, s::Id id = 0) {
    check(std::holds_alternative<s::Refusal>(plan), "Invalid assembly/input publishes no partial phase or poses.");
    const auto& refusal = std::get<s::Refusal>(plan);
    check(refusal.reason == reason && refusal.subject == id, "The exact refusal and opaque subject are retained.");
}
g::Rate fraction(I n, I d) { const I divisor = std::gcd(n, d); return {n / divisor, d / divisor}; }
s::Turns turns(I n, I d = 1) { const auto value = fraction(n, d); return {value.numerator, value.denominator}; }
void literals() {
    s::Profile profile{1, {{1, {}, g::Axis::x, 2}}};
    const auto high = advance(s::prepare(profile, {}, {{5, 2}, true}));
    check(high.next == s::Turns{1, 1} && high.endstop == s::Endstop{s::End::upper, {2, 5}} &&
          high.crossings == std::vector<s::Crossing>{{1, 1, {2, 5}}} && high.poses[0].position[0] == g::Rate{2, 1},
          "An overshoot stops at the declared limit two-fifths through the original tick with no later events.");
    hold(s::prepare(profile, high.next, {{5, 2}, true}), s::Stop::upper_end, high.next);
    const auto low = advance(s::prepare(profile, {1, 2}, {{-2, 1}, true}));
    check(low.next == s::Turns{} && low.endstop == s::Endstop{s::End::lower, {1, 4}} &&
          low.crossings == std::vector<s::Crossing>{{0, -1, {1, 4}}},
          "Reverse overshoot reaches zero at a quarter tick instead of wrapping into the cyclic clock.");
    hold(s::prepare(profile, {}, {{-256, 1}, true}), s::Stop::lower_end, {});
    const auto exact = advance(s::prepare(profile, {}, {{1, 1}, true}));
    check(exact.endstop == s::Endstop{s::End::upper, {1, 1}}, "An exact end-of-tick arrival still reports the reached end stop.");
    hold(s::prepare(profile, {1, 1}, {{1, 1}, false}), s::Stop::unpowered, {1, 1});
    hold(s::prepare(profile, {1, 2}, {{0, 987654321}, true}), s::Stop::stopped, {1, 2});
    const auto interior = advance(s::prepare(profile, {1, 4}, {{1, 4}, true}));
    check(interior.next == s::Turns{1, 2} && !interior.endstop && interior.crossings.empty() &&
          interior.poses[0].position[0] == g::Rate{1, 1}, "Fractional interior travel retains exact turns and translation.");
    profile = {4, {{1, {}, g::Axis::x, 1}, {2, {9, 0, 0}, g::Axis::x, -3}}};
    const auto paired = std::get<std::vector<s::NutPose>>(s::sample(profile, {1, 3}));
    check(paired[0].position[0] == g::Rate{1, 3} && paired[1].position[0] == g::Rate{8, 1},
          "Opposite-hand nuts derive different exact positions from the same third-turn phase.");
    profile = {1, {{1, {}, g::Axis::x, 1}}};
    const s::Turns fine{1, 999983};
    const auto unclipped = k::prepare(k::maximum_teeth, fine, {5, 2});
    check(std::holds_alternative<k::Error>(unclipped) && std::get<k::Error>(unclipped) == k::Error::phase_limit,
          "The deliberately chosen unclipped destination exceeds the existing phase representation.");
    const auto clipped = advance(s::prepare(profile, fine, {{5, 2}, true}));
    check(clipped.next == s::Turns{1, 1} && clipped.endstop == s::Endstop{s::End::upper, fraction(1999964, 4999915)} &&
          clipped.crossings == std::vector<s::Crossing>{{1, 1, fraction(1999964, 4999915)}},
          "Clip to the representable end stop before requesting an unsupported interior overshoot.");
    profile.limit_turns = 4;
    const auto unsupported = s::prepare(profile, fine, {{1, 999979}, true});
    refused(unsupported, s::Error::clock_refused);
    check(std::get<s::Refusal>(unsupported).clock_error == k::Error::phase_limit,
          "An unsupported interior result refuses without rounding, reset or a new authority.");
    const auto extreme = advance(s::prepare(profile, {1, 2}, {{std::numeric_limits<I>::min(), I{1} << 62}, true}));
    check(extreme.endstop == s::Endstop{s::End::lower, {1, 4}}, "Normalize an extreme signed source before negating its reduced speed.");
    profile.limit_turns = s::maximum_turns;
    const auto largest = advance(s::prepare(profile, {8191, 2}, {{256, 1}, true}));
    check(largest.next == s::Turns{4096, 1} && largest.endstop == s::Endstop{s::End::upper, {1, 512}} &&
          largest.crossings == std::vector<s::Crossing>{{4096, 1, {1, 512}}},
          "The largest declared range clips the fastest supported rate without a cyclic alias.");
}

std::vector<s::NutPose> oracle_poses(const s::Profile& profile, I grid) {
    std::vector<s::NutPose> output;
    for (const auto& nut : profile.nuts) {
        s::NutPose pose{nut.id, {}};
        for (std::size_t axis = 0; axis < 3; ++axis)
            pose.position[axis] = fraction(nut.origin[axis] * 12 + (axis == static_cast<std::size_t>(nut.axis) ? nut.lead * grid : 0), 12);
        output.push_back(pose);
    }
    std::sort(output.begin(), output.end(), [](const auto& a, const auto& b) { return a.id < b.id; });
    return output;
}
void oracle() {
    std::size_t cases{};
    for (const I limit : {I{1}, I{2}, I{4}}) {
        for (const I lead : {I{1}, I{2}, I{3}}) {
            for (const auto axis : {g::Axis::x, g::Axis::y, g::Axis::z}) {
                const s::Profile profile{limit, {{7, {-3, 2, 5}, axis, lead}, {2, {19, 11, 7}, axis, -lead - 1}}};
                for (I initial = 0; initial <= limit * 12; ++initial) {
                    const auto phase = turns(initial, 12);
                    for (const I quanta : {I{-120}, I{-25}, I{-5}, I{-1}, I{0}, I{1}, I{5}, I{25}, I{120}, I{30}}) {
                        const bool powered = quanta != 30;
                        const bool moving = powered && quanta != 0;
                        const I direction = quanta < 0 ? -1 : 1;
                        const I count = quanta < 0 ? -quanta : quanta;
                        const I boundary = direction > 0 ? limit * 12 : 0;
                        I grid = initial;
                        std::vector<s::Crossing> events;
                        std::optional<s::Endstop> end;
                        if (moving && initial != boundary) {
                            // Independent linear walk: apply one tiny step until
                            // reaching a boundary, then freeze the rest of time.
                            for (I tick = 1; tick <= count; ++tick) {
                                grid += direction;
                                if (grid % 12 == 0) events.push_back({grid / 12, static_cast<int>(direction), fraction(tick, count)});
                                if (grid == boundary) {
                                    end = s::Endstop{direction > 0 ? s::End::upper : s::End::lower, fraction(tick, count)};
                                    break;
                                }
                            }
                        }
                        const auto actual = s::prepare(profile, phase, {{quanta, 12}, powered});
                        check(!std::holds_alternative<s::Refusal>(actual), "Every small linear oracle input is representable.");
                        if (!moving || initial == boundary) {
                            const auto expected_stop = !powered ? s::Stop::unpowered : quanta == 0 ? s::Stop::stopped
                                : direction > 0 ? s::Stop::upper_end : s::Stop::lower_end;
                            const auto held = hold(actual, expected_stop, phase);
                            check(held.poses == oracle_poses(profile, initial), "A held assembly retains every independently derived nut pose.");
                        } else {
                            const auto next = advance(actual);
                            check(next.next == turns(grid, 12) && next.poses == oracle_poses(profile, grid),
                                  "Both opposed nuts and the sole phase match the independent linear walk.");
                            check(next.crossings == events && next.endstop == end,
                                  "Reached turn order and original-tick arrival times match independent stop-and-freeze steps.");
                        }
                        ++cases;
                    }
                }
            }
        }
    }
    check(cases == 7830, "The linear oracle covers all declared axes, lead pairs, positions, rates and stops.");
}
void validation() {
    s::Profile profile;
    const auto original = profile.nuts;
    for (const I limit : {I{0}, I{-1}, s::maximum_turns + 1, std::numeric_limits<I>::max()}) {
        profile.limit_turns = limit;
        refused(s::prepare(profile, {}, {}), s::Error::invalid_profile);
    }
    profile = {};
    profile.nuts.clear();
    refused(s::prepare(profile, {}, {}), s::Error::invalid_profile);
    profile.nuts = original;
    profile.nuts.push_back({1, {2, 0, 0}, g::Axis::x, -1});
    refused(s::prepare(profile, {}, {}), s::Error::duplicate_nut, 1);
    profile.nuts.back().id = 0;
    refused(s::prepare(profile, {}, {{1, 1}, false}), s::Error::invalid_nut);
    profile.nuts.back().id = 99;
    profile.nuts.back().axis = static_cast<g::Axis>(8);
    refused(s::prepare(profile, {}, {{0, 1}, true}), s::Error::invalid_nut, 99);
    profile = {};
    for (const I lead : {I{0}, g::maximum_dimension + 1, -g::maximum_dimension - 1, std::numeric_limits<I>::min()}) {
        profile.nuts[0].lead = lead;
        refused(s::prepare(profile, {}, {}), s::Error::invalid_nut, 1);
    }
    profile = {};
    profile.nuts[0].origin[0] = g::maximum_coordinate;
    refused(s::prepare(profile, {}, {{0, 1}, false}), s::Error::invalid_nut, 1);
    profile = {};
    for (const auto bad : {s::Turns{-1, 1}, {0, 0}, {2, 4}, {5, 1}, {std::numeric_limits<I>::max(), 1}})
        refused(s::prepare(profile, bad, {}), s::Error::invalid_turns);
    refused(s::prepare(profile, {}, {{1, 0}, false}), s::Error::clock_refused);
    refused(s::prepare(profile, {}, {{257, 1}, true}), s::Error::clock_refused);
    profile.nuts.clear();
    for (s::Id id = 16; id > 0; --id) profile.nuts.push_back({id, {}, g::Axis::x, id % 2 ? 1 : -1});
    const auto all = advance(s::prepare(profile, {}, {{1, 1}, true}));
    check(all.poses.size() == 16 && all.poses.front().id == 1 && all.poses.back().id == 16,
          "The full assembly is returned in canonical opaque-ID order.");
    std::reverse(profile.nuts.begin(), profile.nuts.end());
    check(advance(s::prepare(profile, {}, {{1, 1}, true})).poses == all.poses,
          "Nut input order cannot choose a different geometric result.");
    profile.nuts.clear();
    check(all.poses[0].position[0] == g::Rate{1, 1}, "Returned poses remain owned after the original assembly is destroyed.");
    profile.nuts.resize(17);
    refused(s::prepare(profile, {}, {}), s::Error::invalid_profile);
}
struct Output { int code; std::string text; std::string errors; };
Output play(std::vector<std::string_view> args, const std::string& commands) {
    std::istringstream input(commands);
    std::ostringstream out, errors;
    const int code = s::workbench(args, input, out, errors);
    return {code, out.str(), errors.str()};
}
void caller() {
    const auto mixed = play({"play"}, "drive fast\ntick 1\nstatus\nquit\n");
    check(mixed.code == 1 && mixed.errors.empty() && mixed.text.find("End upper at 2/5") != std::string::npos &&
          mixed.text.find("Tip 1 at 2/1.") != std::string::npos && mixed.text.find("Tip 2 at 6/1.") != std::string::npos,
          "Real fast gearing reaches the mismatched pair's stop without faking alignment.");
    const auto corrected = play({"play"}, "drive fast\ntick 1\nkit fine\ndrive reverse\ntick 2\nkit fine\ndrive fast\ntick 1\nquit\n");
    check(corrected.code == 0 && corrected.errors.empty() && corrected.text.find("return the same spindle home") != std::string::npos &&
          corrected.text.find("End lower at 1/1") != std::string::npos && corrected.text.find("End upper at 4/5") != std::string::npos,
          "The caller protects screw replacement, returns the same phase home and corrects its assembly in one run.");
    check(play({"play"}, "kit coarse\ndrive fast\ntick 1\n").code == 0, "The coarse pair is a distinct valid alignment solution.");
    check(play({"play"}, "kit fine\ntick 4\n").code == 0, "Slow real native gearing also reaches the fine pair's datum.");
    check(play({"play"}, "kit fine\npower off\ntick 1\npower on\ndrive fast\ntick 1\n").code == 0,
          "Power pause retains the same phase and adds no motion debt.");
    check(play({"play"}, "kit fine\ndrive stalled\ntick 4\n").code == 1, "A genuinely stalled native gear fixture invents no spindle travel.");
    const auto malformed = play({"play"}, "tick 0\ntick 65\ntick 1 extra\nkit missing\ndrive missing\nstatus\n");
    check(malformed.code == 1 && malformed.text.find("Reached turn") == std::string::npos,
          "Malformed commands and unknown kit/drive names execute no partial motion.");
    const auto oversized = play({"play"}, "kit coarse" + std::string(600, ' ') + "\ndrive fast\ntick 1\n");
    check(oversized.code == 1 && oversized.text.find("command exceeds 512 bytes") != std::string::npos,
          "An oversized kit prefix cannot replace the mixed pair before the following valid drive.");
    check(play({"missing"}, "").code == 2 && play({"list"}, "").code == 0 && play({"--help"}, "").code == 0,
          "Startup is bounded and the catalogue/help remain accessible.");
    std::istringstream input;
    input.setstate(std::ios::badbit);
    std::ostringstream out, errors;
    const std::vector<std::string_view> args{"play"};
    check(s::workbench(args, input, out, errors) == 2, "Input failure is distinct from unfinished EOF.");
    std::istringstream good;
    out.setstate(std::ios::badbit);
    check(s::workbench(args, good, out, errors) == 2, "Output failure cannot become alignment success.");
}
}  // namespace
int main() {
    try {
        literals(); oracle(); validation(); caller();
        std::cout << checks << " screw-drive assertions passed, including 7830 independent linear-lattice cases.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " assertions: " << error.what() << '\n';
        return 1;
    }
}
