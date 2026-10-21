#include "factory/geared_carriage.hpp"
#include "factory/geared_carriage_workbench.hpp"

#include <algorithm>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>
#include <stdexcept>

namespace a = factory::geared_carriage;
namespace c = factory::clearance;
namespace k = factory::geared_cycle;
namespace m = factory::mechanisms;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
a::Step step(a::Plan plan) {
    check(std::holds_alternative<a::Step>(plan), "The entire proposed geared interval is clear.");
    return std::get<a::Step>(std::move(plan));
}
a::Hold hold(a::Plan plan, a::Stop reason, k::Phase original) {
    check(std::holds_alternative<a::Hold>(plan), "A hold publishes no proposed crossings or prefix effects.");
    auto held = std::get<a::Hold>(std::move(plan));
    check(held.reason == reason && held.phase == original, "A hold preserves the original canonical phase and exact stop reason.");
    return held;
}
void refused(const a::Plan& plan, a::Error error, c::Error geometry = c::Error::none) {
    check(std::holds_alternative<a::Refusal>(plan), "Invalid input publishes neither a hold nor partial motion.");
    const auto& refusal = std::get<a::Refusal>(plan);
    check(refusal.reason == error && refusal.geometry_error == geometry, "The refusal retains its exact local/native category.");
}
c::Obstacle barrier(std::uint64_t id, I x, I height = 0) {
    return {id, {{x, height, 0}, {x + 1, height + 1, 1}}};
}
void literals() {
    const a::Profile profile;
    const auto sampled = a::sample(profile, {5, 2});
    check(std::holds_alternative<a::Pose>(sampled) && std::get<a::Pose>(sampled) == a::Pose{
        {{0, 0, 0}, {1, 1, 1}}, {{2, 0, 0}, {3, 1, 1}}, {1, 2}},
        "Fractional pose interpolates the literal canonical integer carriage envelopes.");
    const c::Obstacle obstacle = barrier(7, 3);
    const auto full = hold(a::prepare(profile, {}, {{10, 1}, true, {&obstacle, 1}}), a::Stop::obstructed, {});
    check(full.contact == a::Contact{7, 3, 3, {0, 1}, false},
          "A complete geared revolution cannot hide contact behind identical clear endpoints.");
    auto first = step(a::prepare(profile, {}, {{5, 2}, true, {&obstacle, 1}}));
    check(first.proposed.next == k::Phase{5, 2} && first.proposed.crossings.size() == 2,
          "The first fast tick retains a genuinely fractional clear pose and two accepted stops.");
    const auto blocked = hold(a::prepare(profile, first.proposed.next, {{5, 2}, true, {&obstacle, 1}}), a::Stop::obstructed, {5, 2});
    check(blocked.contact == a::Contact{7, 1, 3, {0, 1}, false},
          "A later obstruction rejects the entire tick, including its otherwise clear prefix.");
    const auto raised = barrier(7, 3, 2);
    auto phase = first.proposed.next;
    std::size_t visits = first.proposed.crossings.size();
    for (int tick = 0; tick < 3; ++tick) {
        auto next = step(a::prepare(profile, phase, {{5, 2}, true, {&raised, 1}}));
        phase = next.proposed.next;
        visits += next.proposed.crossings.size();
    }
    check(phase == k::Phase{} && visits == 10, "Raising the real barrier resumes the same phase and original accepted visits without reset.");
    const auto grazing = barrier(7, 3, 1);
    check(step(a::prepare(profile, {}, {{10, 1}, true, {&grazing, 1}})).proposed.crossings.size() == 10,
          "Exact surface grazing preserves the canonical strict-interior policy.");

    a::Profile wide;
    wide.stroke = 12;
    auto early = barrier(7, 1);
    check(step(a::prepare(wide, {11, 4}, {{1, 8}, true, {&early, 1}})).proposed.next == k::Phase{23, 8},
          "A clear fractional tail after an earlier collision interval is not blocked by the whole-cell sweep.");
    auto middle = barrier(7, 2);
    check(step(a::prepare(wide, {2, 1}, {{1, 8}, true, {&middle, 1}})).proposed.next == k::Phase{17, 8},
          "A clear partial interval before future contact remains admitted.");
    check(step(a::prepare(wide, {2, 1}, {{1, 4}, true, {&middle, 1}})).proposed.next == k::Phase{9, 4},
          "Contact only at the fractional destination is clear.");
    const auto enters = hold(a::prepare(wide, {9, 4}, {{1, 8}, true, {&middle, 1}}), a::Stop::obstructed, {9, 4});
    check(enters.contact == a::Contact{7, 0, 2, {1, 4}, false}, "Fractional starting contact followed by penetration holds without rounding.");
    check(step(a::prepare(wide, {3, 1}, {{-1, 4}, true, {&middle, 1}})).proposed.next == k::Phase{11, 4},
          "Reverse movement ending at a surface is clear.");
    const auto reverse = hold(a::prepare(wide, {3, 1}, {{-1, 2}, true, {&middle, 1}}), a::Stop::obstructed, {3, 1});
    check(reverse.contact == a::Contact{7, 0, 2, {3, 4}, false}, "Reverse clipping selects the higher phase contact, not the forward entry.");
    const auto paused = hold(a::prepare(wide, {2, 1}, {{10, 1}, false, {&middle, 1}}), a::Stop::unpowered, {2, 1});
    check(!paused.contact, "A paused current pose ignores a future collision while validating every obstacle.");
    const auto penetrated = hold(a::prepare(wide, {5, 2}, {{1, 1}, false, {&middle, 1}}), a::Stop::obstructed, {5, 2});
    check(penetrated.contact && penetrated.contact->initially_overlapping, "Current positive penetration is retained even while unpowered.");
    hold(a::prepare(profile, {5, 2}, {{0, 3}, true, {}}), a::Stop::stopped, {5, 2});
    a::Profile thirds;
    thirds.stroke = 9;
    const auto third = hold(a::prepare(thirds, {7, 3}, {{1, 3}, true, {&middle, 1}}), a::Stop::obstructed, {7, 3});
    check(third.contact == a::Contact{7, 0, 2, {1, 3}, false}, "Nonbinary fractions preserve exact one-third contact.");
    a::Profile short_cycle;
    short_cycle.timing = {1, 1, 1};
    short_cycle.stroke = 3;
    const auto short_hit = hold(a::prepare(short_cycle, {}, {{4, 1}, true, {&middle, 1}}), a::Stop::obstructed, {});
    check(short_hit.contact == a::Contact{7, 1, 1, {1, 3}, false}, "A different valid carriage timing retains its own period and exact stroke fraction.");
    a::Profile boundary;
    boundary.timing = {1, 1, 1};
    boundary.dock = {{-g::maximum_coordinate, 0, 0}, {-g::maximum_coordinate + 1, 1, 1}};
    boundary.stroke = 2 * g::maximum_coordinate - 1;
    const auto origin = barrier(17, 0);
    const auto fractional = hold(a::prepare(boundary, {3, 2}, {{1, 1}, false, {&origin, 1}}), a::Stop::obstructed, {3, 2});
    check(fractional.contact == a::Contact{17, 0, 1, {1, 2}, true},
          "A half-step spanning the entire bounded grid detects literal fractional penetration without rounding.");
}

c::Fraction fraction(I n, I d) {
    const I divisor = std::gcd(n, d);
    return {n / divisor, d / divisor};
}
I wrap(I n, I period) { const auto r = n % period; return r < 0 ? r + period : r; }
c::Box scaled_box(const a::Profile& profile, I grid) {
    const I tooth = grid / 12;
    const I remainder = grid % 12;
    m::Pose from, to;
    check(m::sample(profile.timing, {static_cast<m::Tooth>(tooth)}, from) == m::Error::none &&
          m::sample(profile.timing, {static_cast<m::Tooth>((tooth + 1) % 10)}, to) == m::Error::none,
          "The independent oracle samples canonical integer geometry.");
    auto box = profile.dock;
    for (std::size_t axis = 0; axis < 3; ++axis) { box.minimum[axis] *= 12; box.maximum[axis] *= 12; }
    const I offset = profile.stroke / 3 * (static_cast<I>(from.numerator) * 12 +
        (static_cast<I>(to.numerator) - static_cast<I>(from.numerator)) * remainder);
    box.minimum[static_cast<std::size_t>(profile.axis)] += offset;
    box.maximum[static_cast<std::size_t>(profile.axis)] += offset;
    return box;
}
struct Oracle {
    std::optional<a::Contact> contact;
    k::Phase next;
    std::size_t visits{};
};
Oracle walk(const a::Profile& profile, I initial, I quanta, bool powered, const std::vector<c::Obstacle>& obstacles) {
    std::vector<c::Obstacle> scaled = obstacles;
    for (auto& item : scaled)
        for (std::size_t axis = 0; axis < 3; ++axis) { item.box.minimum[axis] *= 12; item.box.maximum[axis] *= 12; }
    const I direction = quanta < 0 ? -1 : 1;
    const I count = powered ? (quanta < 0 ? -quanta : quanta) : 0;
    I grid = initial;
    Oracle result;
    for (I tick = 0; tick < (count == 0 ? 1 : count); ++tick) {
        const auto from = scaled_box(profile, grid);
        const I next_grid = count == 0 ? grid : wrap(grid + direction, 120);
        const auto to = scaled_box(profile, next_grid);
        c::Point delta{};
        for (std::size_t axis = 0; axis < 3; ++axis) delta[axis] = to.minimum[axis] - from.minimum[axis];
        const auto direct = c::sweep(from, delta, scaled);
        check(direct.error == c::Error::none, "One actual scaled microsegment fits the canonical grid.");
        if (direct.hit) {
            I base = grid / 12;
            I start_fraction = grid % 12;
            if (count != 0 && direction < 0 && start_fraction == 0) { base = wrap(base - 1, 10); start_fraction = 12; }
            const auto hit = *direct.hit;
            const auto at = fraction(start_fraction * hit.time.denominator +
                (count == 0 ? 0 : direction * hit.time.numerator), 12 * hit.time.denominator);
            result.contact = a::Contact{hit.obstacle, 0, base, at, hit.initially_overlapping};
            return result;
        }
        grid = next_grid;
        if (count != 0 && grid % 12 == 0) ++result.visits;
    }
    const auto phase = fraction(grid, 12);
    result.next = {phase.numerator, phase.denominator};
    return result;
}
void oracle() {
    const std::vector<std::vector<c::Obstacle>> layouts{
        {}, {barrier(7, 3)}, {barrier(7, 1)}, {barrier(9, 3), barrier(2, 3)},
        {barrier(1, 5), barrier(19, 2), barrier(3, 4, 1)},
    };
    std::size_t cases{};
    for (const I stroke : {I{6}, I{12}}) {
        a::Profile profile;
        profile.stroke = stroke;
        for (const auto& layout : layouts) {
            for (I initial = 0; initial < 120; ++initial) {
                const auto initial_fraction = fraction(initial, 12);
                const k::Phase phase{initial_fraction.numerator, initial_fraction.denominator};
                for (const I quanta : {I{-120}, I{-33}, I{-5}, I{-1}, I{0}, I{1}, I{5}, I{33}, I{120}, I{30}}) {
                    const bool powered = quanta != 30;
                    const auto expected = walk(profile, initial, quanta, powered, layout);
                    const auto actual = a::prepare(profile, phase, {{quanta, 12}, powered, layout});
                    check(!std::holds_alternative<a::Refusal>(actual), "Every small scaled oracle scene has representable valid inputs.");
                    if (expected.contact) {
                        const auto held = hold(actual, a::Stop::obstructed, phase);
                        check(held.contact && held.contact->obstacle == expected.contact->obstacle &&
                              held.contact->tooth == expected.contact->tooth && held.contact->fraction == expected.contact->fraction &&
                              held.contact->initially_overlapping == expected.contact->initially_overlapping,
                              "Clipped two-sweep contact agrees with direct tiny scaled sweeps, including order, identity and penetration.");
                    } else if (!powered || quanta == 0) {
                        const auto held = hold(actual, powered ? a::Stop::stopped : a::Stop::unpowered, phase);
                        check(!held.contact, "A clear stopped/paused oracle pose has no invented contact.");
                    } else {
                        const auto next = step(actual);
                        check(next.proposed.next == expected.next && next.proposed.crossings.size() == expected.visits,
                              "Clear motion retains the independently walked phase and every boundary visit.");
                    }
                    ++cases;
                }
            }
        }
    }
    check(cases == 12000, "The independent scaled-grid oracle covers every declared phase, direction, speed and layout.");
}

void validation_and_axes() {
    a::Profile profile;
    for (const auto axis : {g::Axis::x, g::Axis::y, g::Axis::z}) {
        profile.axis = axis;
        auto obstacle = barrier(7, 3);
        const auto index = static_cast<std::size_t>(axis);
        std::swap(obstacle.box.minimum[0], obstacle.box.minimum[index]);
        std::swap(obstacle.box.maximum[0], obstacle.box.maximum[index]);
        check(hold(a::prepare(profile, {}, {{10, 1}, true, {&obstacle, 1}}), a::Stop::obstructed, {}).contact->tooth == 3,
              "The same literal obstruction is found on every carriage axis.");
    }
    profile = {};
    auto tie = std::vector<c::Obstacle>{barrier(9, 3), barrier(2, 3)};
    const auto first = hold(a::prepare(profile, {}, {{10, 1}, true, tie}), a::Stop::obstructed, {});
    std::reverse(tie.begin(), tie.end());
    check(first == hold(a::prepare(profile, {}, {{10, 1}, true, tie}), a::Stop::obstructed, {}) && first.contact->obstacle == 2,
          "Equal contacts select the lowest stable identity independently of supplied order.");
    auto invalid = tie;
    invalid.push_back(barrier(0, 100));
    refused(a::prepare(profile, {}, {{10, 1}, true, invalid}), a::Error::invalid_obstacles, c::Error::invalid_id);
    invalid.back() = barrier(9, 100);
    refused(a::prepare(profile, {}, {{1, 1}, false, invalid}), a::Error::invalid_obstacles, c::Error::duplicate_id);
    invalid.back() = barrier(11, 100);
    invalid.back().box.maximum[0] = invalid.back().box.minimum[0];
    refused(a::prepare(profile, {}, {{0, 1}, true, invalid}), a::Error::invalid_obstacles, c::Error::invalid_box);
    std::vector<c::Obstacle> many;
    for (std::size_t i = 0; i < g::maximum_parts; ++i) many.push_back(barrier(i + 1, static_cast<I>(100 + 2 * i)));
    check(step(a::prepare(profile, {}, {{10, 1}, true, many})).proposed.crossings.size() == 10, "The full 256-obstacle set is usable without truncation.");
    many.push_back(barrier(999, 1000));
    refused(a::prepare(profile, {}, {{1, 1}, false, many}), a::Error::invalid_obstacles, c::Error::too_many_obstacles);
    refused(a::prepare(profile, {2, 4}, {}), a::Error::invalid_clock);
    refused(a::prepare(profile, {}, {{1, 0}, false, {}}), a::Error::invalid_clock);
    const auto phase_limit = a::prepare(profile, {1, 999983}, {{1, 999979}, true, {}});
    refused(phase_limit, a::Error::invalid_clock);
    check(std::get<a::Refusal>(phase_limit).clock_error == k::Error::phase_limit,
          "The original native phase-limit refusal propagates without a geometry fallback.");
    check(step(a::prepare(profile, {}, {{std::numeric_limits<I>::min(), I{1} << 62}, true, {}})).proposed.next == k::Phase{8, 1},
          "The normalized extreme reverse rate needs no local signed negation.");
    profile.axis = static_cast<g::Axis>(8);
    refused(a::prepare(profile, {}, {}), a::Error::invalid_profile);
    profile = {};
    profile.stroke = 7;
    refused(a::prepare(profile, {}, {}), a::Error::invalid_profile);
    profile.stroke = std::numeric_limits<I>::max();
    refused(a::prepare(profile, {}, {}), a::Error::invalid_profile);
    profile = {};
    profile.timing.dock = 0;
    refused(a::prepare(profile, {}, {}), a::Error::invalid_profile);
    profile = {};
    profile.dock.maximum[0] = g::maximum_coordinate;
    refused(a::prepare(profile, {}, {}), a::Error::invalid_profile, c::Error::invalid_motion);
    profile = {};
    profile.timing = {65533, 1, 1};
    profile.stroke = 1;
    check(step(a::prepare(profile, {65535, 1}, {{1, 1}, true, {}})).proposed.next == k::Phase{},
          "The exact largest supported cycle wraps using its own last carriage interval.");
    ++profile.timing.dock;
    refused(a::prepare(profile, {}, {}), a::Error::invalid_profile);
}
struct Output { int code; std::string text; std::string errors; };
Output play(std::vector<std::string_view> args, const std::string& commands) {
    std::istringstream input(commands);
    std::ostringstream out, errors;
    const int code = a::workbench(args, input, out, errors);
    return {code, out.str(), errors.str()};
}
void caller() {
    const auto blocked = play({"play", "burst"}, "tick 1\nstatus\nquit\n");
    check(blocked.code == 1 && blocked.errors.empty() && blocked.text.find("Native output rotating 10/1.") != std::string::npos &&
          blocked.text.find("Phase 0/1; accepted visits 0") != std::string::npos && blocked.text.find("Hold obstructed") != std::string::npos,
          "Actual native burst gearing cannot skip a whole-revolution obstruction or award prefix visits.");
    const auto recovered = play({"play", "fast"}, "tick 1\ntick 1\nstatus\nbarrier raised\ntick 3\nquit\n");
    check(recovered.code == 0 && recovered.errors.empty() && recovered.text.find("Phase 5/2; accepted visits 2") != std::string::npos &&
          recovered.text.find("Phase 0/1; accepted visits 10") != std::string::npos,
          "The terminal retains earlier partial progress and resumes the same phase after raising its barrier.");
    check(play({"play", "burst"}, "barrier grazing\ntick 1\n").code == 0, "A real terminal grazing layout completes without a reset.");
    check(play({"play", "reverse"}, "barrier raised\ntick 20\n").code == 0, "The native reverse gear fixture completes the same original cycle.");
    check(play({"play", "slow"}, "barrier raised\npower off\ntick 2\npower on\ntick 20\n").code == 0,
          "Pause/resume through actual commands adds no phase debt.");
    check(play({"play", "stalled"}, "barrier raised\ntick 20\n").code == 1, "A real stalled native output invents no visits.");
    const auto malformed = play({"play", "burst"}, "tick 0\ntick 65\ntick 1 extra\nbarrier missing\nstatus\n");
    check(malformed.code == 1 && malformed.text.find("accepted visits 0") != std::string::npos && malformed.text.find("Hold obstructed") == std::string::npos,
          "Malformed commands execute no partial ticks or barrier change.");
    const auto oversized = play({"play", "burst"}, "barrier raised" + std::string(600, ' ') + "\ntick 1\nstatus\n");
    check(oversized.code == 1 && oversized.text.find("Hold obstructed") != std::string::npos,
          "An oversized valid-looking barrier prefix leaves the real route blocked for the following tick.");
    check(play({"play", "burst"}, "barrier missing\ntick 1\n").code == 1,
          "An unknown barrier pose cannot silently raise the obstacle before a valid tick.");
    check(play({"play", "missing"}, "").code == 2 && play({"list"}, "").code == 0 && play({"--help"}, "").code == 0,
          "Startup refuses an unknown fixture and exposes the catalogue/help.");
    std::istringstream input;
    input.setstate(std::ios::badbit);
    std::ostringstream out, errors;
    const std::vector<std::string_view> args{"play", "burst"};
    check(a::workbench(args, input, out, errors) == 2, "Input failure is distinct from ordinary unfinished EOF.");
    std::istringstream good;
    out.setstate(std::ios::badbit);
    check(a::workbench(args, good, out, errors) == 2, "Output failure cannot become completion.");
}
}  // namespace
int main() {
    try {
        literals(); oracle(); validation_and_axes(); caller();
        std::cout << checks << " geared-carriage controls passed, including 12000 scaled-grid oracle cases.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " controls: " << error.what() << '\n';
        return 1;
    }
}
