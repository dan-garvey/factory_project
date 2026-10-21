#include "factory/geared_cycle_workbench.hpp"

#include <algorithm>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>
#include <stdexcept>

namespace c = factory::geared_cycle;
namespace g = factory::mechanics;
using I = c::Integer;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
c::Prepared accepted(c::Plan plan) {
    check(std::holds_alternative<c::Prepared>(plan), "The representable phase proposal is accepted.");
    return std::get<c::Prepared>(std::move(plan));
}
void refused(const c::Plan& plan, c::Error error) {
    check(std::holds_alternative<c::Error>(plan) && std::get<c::Error>(plan) == error,
          "The exact refusal returns no partial phase or crossing sequence.");
}
void literals() {
    const auto half = accepted(c::prepare(10, {}, {1, 2}));
    check(half.next == c::Phase{1, 2} && half.crossings.empty(), "Half a tooth remains explicit instead of being rounded away.");
    const auto whole = accepted(c::prepare(10, half.next, {2, 4}));
    check(whole.next == c::Phase{1, 1} && whole.crossings == std::vector<c::Crossing>{{1, 1, {1, 1}}},
          "The second half reaches exactly one boundary at the end of the tick.");
    const auto fast = accepted(c::prepare(10, {}, {5, 2}));
    check(fast.next == c::Phase{5, 2} && fast.crossings == std::vector<c::Crossing>{{1, 1, {2, 5}}, {2, 1, {4, 5}}},
          "A 5/2 input visits both crossed stops at literal two-fifths and four-fifths.");
    const auto next = accepted(c::prepare(10, fast.next, {5, 2}));
    check(next.next == c::Phase{5, 1} && next.crossings == std::vector<c::Crossing>{{3, 1, {1, 5}}, {4, 1, {3, 5}}, {5, 1, {1, 1}}},
          "Retained fractional phase shifts the next tick's event times without changing speed.");
    const auto reverse = accepted(c::prepare(10, {5, 2}, {-5, 2}));
    check(reverse.next == c::Phase{0, 1} && reverse.crossings == std::vector<c::Crossing>{{2, -1, {1, 5}}, {1, -1, {3, 5}}, {0, -1, {1, 1}}},
          "Reverse motion reaches the literal stops in descending order, excluding the starting stop.");
    const auto wrapped = accepted(c::prepare(10, {1, 4}, {-1, 2}));
    check(wrapped.next == c::Phase{39, 4} && wrapped.crossings == std::vector<c::Crossing>{{0, -1, {1, 2}}},
          "A reverse fraction crosses zero halfway through the tick and retains the exact wrapped phase.");
    const auto turn = accepted(c::prepare(10, {}, {10, 1}));
    check(turn.next == c::Phase{} && turn.crossings.size() == 10 && turn.crossings.front() == c::Crossing{1, 1, {1, 10}} &&
          turn.crossings.back() == c::Crossing{0, 1, {1, 1}},
          "Equal start/end phase still reports every stop of a complete revolution.");
    check(std::count_if(turn.crossings.begin(), turn.crossings.end(), [](auto event) { return event.tooth == 5 || event.tooth == 6; }) == 2,
          "The full-turn event stream cannot silently skip the two-tooth work window.");
    auto phase = half.next;
    for (int i = 0; i < 40; ++i) {
        const auto paused = accepted(c::prepare(10, phase, {5, 2}, false));
        check(paused.next == half.next && paused.crossings.empty(), "Paused ticks retain the same fractional phase with no catch-up debt.");
        phase = paused.next;
    }
    check(accepted(c::prepare(10, phase, {1, 2})).next == c::Phase{1, 1}, "Resuming adds one current tick, not the paused history.");
    check(accepted(c::prepare(10, phase, {0, 987654321})).next == phase, "A normalized zero source holds the original phase.");
}

// Independent small-grid oracle: move one twelfth of a tooth at a time, wrapping
// immediately and recording an event only when that walk lands on a tooth. No
// production phase addition or boundary-enumeration formula is reused.
void lattice_oracle() {
    std::size_t cases{};
    for (I period = 1; period <= 7; ++period) {
        for (I initial = 0; initial < period * 12; ++initial) {
            const I phase_divisor = std::gcd(initial, I{12});
            const c::Phase phase{initial / phase_divisor, 12 / phase_divisor};
            for (I numerator = -8; numerator <= 8; ++numerator) {
                for (I denominator = 1; denominator <= 4; ++denominator) {
                    const auto actual = accepted(c::prepare(period, phase, {numerator, denominator}));
                    const I direction = numerator < 0 ? -1 : 1;
                    const I steps = (numerator < 0 ? -numerator : numerator) * (12 / denominator);
                    I position = initial;
                    std::vector<c::Crossing> events;
                    for (I step = 1; step <= steps; ++step) {
                        position += direction;
                        if (position < 0) position = period * 12 - 1;
                        if (position >= period * 12) position = 0;
                        if (position % 12 == 0) {
                            const I divisor = std::gcd(step, steps);
                            events.push_back({position / 12, static_cast<int>(direction), {step / divisor, steps / divisor}});
                        }
                    }
                    const I divisor = std::gcd(position, I{12});
                    check(actual.next == c::Phase{position / divisor, 12 / divisor}, "Exact phase agrees with the independent wrapped lattice walk.");
                    check(actual.crossings == events, "Every ordered stop, direction and tick fraction agrees with the independent walk.");
                    ++cases;
                }
            }
        }
    }
    check(cases == 22848, "The oracle covers all declared phases, signs, small ratios and seven cycle lengths.");
}
void bounds() {
    for (const I period : {I{0}, I{-1}, c::maximum_teeth + 1, std::numeric_limits<I>::max()})
        refused(c::prepare(period, {}, {1, 1}), c::Error::invalid_profile);
    for (const c::Phase phase : {c::Phase{-1, 1}, {10, 1}, {0, 0}, {0, 2}, {2, 4}, {1, c::maximum_denominator + 1}, {std::numeric_limits<I>::max(), 1}})
        refused(c::prepare(10, phase, {1, 1}), c::Error::invalid_phase);
    refused(c::prepare(10, {}, {1, 0}), c::Error::invalid_rate);
    refused(c::prepare(10, {}, {1, -1}), c::Error::invalid_rate);
    refused(c::prepare(10, {}, {257, 1}), c::Error::rate_limit);
    refused(c::prepare(10, {}, {-257, 1}), c::Error::rate_limit);
    refused(c::prepare(10, {}, {1, c::maximum_denominator + 1}), c::Error::rate_limit);
    refused(c::prepare(10, {}, {std::numeric_limits<I>::min(), 1}), c::Error::rate_limit);
    refused(c::prepare(10, {}, {1, 0}, false), c::Error::invalid_rate);
    const c::Phase fine{1, 999983};
    refused(c::prepare(10, fine, {1, 999979}), c::Error::phase_limit);
    check(accepted(c::prepare(10, fine, {1, 999979}, false)).next == fine,
          "A paused representable input does not try to store a hypothetical overflowing denominator.");
    check(accepted(c::prepare(10, fine, {1, 999983})).next == c::Phase{2, 999983},
          "The same retained phase continues exactly after a representable rate change.");
    const auto maximum = accepted(c::prepare(1, {}, {-256, 1}));
    check(maximum.next == c::Phase{} && maximum.crossings.size() == 256 &&
          maximum.crossings.front() == c::Crossing{0, -1, {1, 256}} && maximum.crossings.back() == c::Crossing{0, -1, {1, 1}},
          "The exact speed limit retains 256 distinct arrivals even on a one-tooth cycle.");
    const auto large = accepted(c::prepare(c::maximum_teeth,
        {c::maximum_teeth * c::maximum_denominator - 1, c::maximum_denominator}, {256, 1}));
    check(large.next == c::Phase{255999999, 1000000} && large.crossings.size() == 256 &&
          large.crossings.front() == c::Crossing{0, 1, {1, 256000000}},
          "The largest cycle, fraction and speed retain exact phase and a fine-grained event time.");
    const auto end = accepted(c::prepare(10, {999999, 1000000}, {1, 1000000}));
    check(end.next == c::Phase{1, 1} && end.crossings == std::vector<c::Crossing>{{1, 1, {1, 1}}},
          "Reduce the final phase before imposing the persistent denominator bound.");
    check(accepted(c::prepare(10, {}, {std::numeric_limits<I>::min(), I{1} << 62})).next == c::Phase{8, 1},
          "Normalize INT64_MIN without signed negation when the actual reduced rate is legal.");
    check(accepted(c::prepare(10, {}, {std::numeric_limits<I>::max(), std::numeric_limits<I>::max()})).next == c::Phase{1, 1},
          "A large raw rate reduces before applying representation limits.");
}
struct Output { int code; std::string out; std::string errors; };
Output run(std::vector<std::string_view> args) {
    std::ostringstream out, errors;
    const int code = c::workbench(args, out, errors);
    return {code, out.str(), errors.str()};
}
void consumer() {
    for (const auto name : {"slow", "fast", "reverse", "stalled"}) {
        const auto scene = *c::fixture(name);
        const auto derived = g::evaluate(scene.parts, scene.sources);
        check(derived.accepted(), "The fixture uses an accepted actual geometric gear assembly.");
        const auto output = derived.motion.at("output");
        if (std::string_view(name) == "stalled") check(output.state == g::MotionState::stalled,
            "Opposing prescribed sources actually stall the connected gear assembly.");
        else check(output == g::Motion{g::MotionState::rotating,
            std::string_view(name) == "fast" ? g::Rate{5, 2} : std::string_view(name) == "reverse" ? g::Rate{-1, 2} : g::Rate{1, 2}},
            "The native kernel supplies the fixture's literal signed ratio.");
    }
    const auto slow = run({"slow", "20"});
    check(slow.code == 0 && slow.errors.empty() && slow.out.find("Crossings=10 cam_hits=2 final=0/1.") != std::string::npos,
          "Twenty actual half-speed ticks make one complete ten-tooth cam revolution.");
    const auto fast = run({"fast", "4"});
    check(fast.code == 0 && fast.out.find("Tick 1 tooth 1 at 2/5 direction 1") != std::string::npos &&
          fast.out.find("Crossings=10 cam_hits=2 final=0/1.") != std::string::npos,
          "Four fast ticks preserve all cam visits instead of sampling only four endpoints.");
    const auto reverse = run({"reverse", "20"});
    check(reverse.code == 0 && reverse.out.find("Tick 2 tooth 9 at 1/1 direction -1") != std::string::npos &&
          reverse.out.find("Crossings=10 cam_hits=2 final=0/1.") != std::string::npos,
          "The actual caller reports reverse stops and the same original cam window.");
    for (const auto& args : {std::vector<std::string_view>{"fast", "20", "--paused"}, {"stalled", "20"}, {"slow", "0"}}) {
        const auto held = run(args);
        check(held.code == 0 && held.out.find("Crossings=0 cam_hits=0 final=0/1.") != std::string::npos,
              "Paused, stalled and zero-tick traces create no phase or cam events.");
    }
    for (const auto& args : {std::vector<std::string_view>{"unknown", "1"}, {"slow", "257"}, {"slow", "-1"}, {"slow", "1x"}, {"slow", "1", "--other"}, {"slow"}})
        check(run(args).code == 2, "Unknown, malformed or out-of-bound batch arguments refuse.");
    check(run({"list"}).code == 0 && run({"--help"}).code == 0 && !c::fixture("missing"), "Help/catalogue are accessible and unknown fixtures have no fallback.");
    std::ostringstream out, errors;
    out.setstate(std::ios::badbit);
    const std::vector<std::string_view> args{"slow", "1"};
    check(c::workbench(args, out, errors) == 2, "Output failure cannot become a successful trace.");
}
}  // namespace
int main() {
    try {
        literals(); lattice_oracle(); bounds(); consumer();
        std::cout << checks << " geared-cycle controls passed, including 22848 independent lattice cases.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " controls: " << error.what() << '\n';
        return 1;
    }
}
