#include "factory/differential.hpp"
#include "factory/differential_workbench.hpp"

#include <algorithm>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace d = factory::differential;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
g::Rate fraction(I numerator, I denominator) {
    const I divisor = std::gcd(numerator, denominator);
    return {numerator / divisor, denominator / divisor};
}
d::Evaluation solved(const d::Result& result) {
    check(std::holds_alternative<d::Evaluation>(result), "The bounded constraints produce an owned evaluation.");
    return std::get<d::Evaluation>(result);
}
void refusal(const d::Result& result, d::Error expected) {
    check(std::holds_alternative<d::Refusal>(result) && std::get<d::Refusal>(result).reason == expected,
          "Invalid or underconstrained input refuses without inventing an output.");
}
d::Result evaluate(std::initializer_list<d::Constraint> values) {
    return d::evaluate(std::span(values.begin(), values.size()));
}
void literals() {
    const auto sum = solved(evaluate({{d::Port::left, {5, 2}}, {d::Port::right, {-1, 2}}}));
    check(sum.outcome == d::Outcome::solved && sum.motion[1] == g::Motion{g::MotionState::rotating, {1, 1}},
          "Fast and reversed side inputs produce carrier speed one, preserving the sign.");
    const auto double_speed = solved(evaluate({{d::Port::left, {0, 1}}, {d::Port::carrier, {1, 2}}}));
    check(double_speed.motion[2] == g::Motion{g::MotionState::rotating, {1, 1}} && double_speed.motion[0].state == g::MotionState::stopped,
          "A real zero-speed constraint permits a distinct carrier-driven speed-doubling solution.");
    const auto balanced = solved(evaluate({{d::Port::left, {1, 2}}, {d::Port::right, {-1, 2}}}));
    check(balanced.motion[1] == g::Motion{g::MotionState::stopped, {0, 1}} && balanced.motion[0].state == g::MotionState::rotating,
          "Opposite side motion can hold the carrier without stalling the side shafts.");
    const auto held = solved(evaluate({{d::Port::carrier, {0, 100}}, {d::Port::right, {0, 9}}}));
    check(std::all_of(held.motion.begin(), held.motion.end(), [](const auto& value) { return value == g::Motion{g::MotionState::stopped, {0, 1}}; }),
          "Two explicit locks hold the entire component, with canonical zero rates.");
    const auto extreme = solved(evaluate({{d::Port::left, {std::numeric_limits<I>::min(), I{1} << 62}},
                                          {d::Port::carrier, {I{1} << 62, I{1} << 62}}}));
    check(extreme.motion[2].rate == g::Rate{4, 1}, "Normalize raw signed extremes before weighted arithmetic.");
    const auto conflict = solved(evaluate({{d::Port::left, {-256, 1}}, {d::Port::carrier, {256, 1}}, {d::Port::right, {256, 1}}}));
    check(conflict.outcome == d::Outcome::stalled && conflict.prescribed[0] == g::Rate{-256, 1},
          "A fully prescribed conflict is diagnosed before refusing its unsupported inferred rate.");
    refusal(evaluate({{d::Port::left, {-256, 1}}, {d::Port::carrier, {256, 1}}}), d::Error::unsupported_result);
    refusal(evaluate({{d::Port::left, {1, 999983}}, {d::Port::carrier, {1, 999979}}}), d::Error::unsupported_result);
    const auto exact = solved(evaluate({{d::Port::left, {2, 999983}}, {d::Port::right, {0, 1}}}));
    check(exact.motion[1].rate == g::Rate{1, 999983}, "Reduce the inferred fraction before imposing its representation bound.");
}
void lattice() {
    std::size_t pairs{}, triples{};
    // Search the third velocity on an independent integer lattice instead of
    // evaluating the implementation's rational rearrangement in the oracle.
    for (std::size_t missing = 0; missing < 3; ++missing) {
        for (I a = -12; a <= 12; ++a) for (I b = -12; b <= 12; ++b) {
            std::array<I, 3> grid{};
            std::vector<d::Constraint> observations;
            bool first = true;
            for (std::size_t index = 0; index < 3; ++index) {
                if (index == missing) continue;
                grid[index] = 2 * (first ? a : b);
                observations.push_back({static_cast<d::Port>(index), fraction(first ? a : b, 12)});
                first = false;
            }
            unsigned matches{};
            I chosen{};
            for (I trial = -96; trial <= 96; ++trial) {
                grid[missing] = trial;
                if (2 * grid[1] == grid[0] + grid[2]) { ++matches; chosen = trial; }
            }
            check(matches == 1, "Two constraints admit exactly one small lattice velocity.");
            grid[missing] = chosen;
            const auto actual = solved(d::evaluate(observations));
            check(actual.outcome == d::Outcome::solved, "A consistent pair is not a contradiction stall.");
            for (std::size_t index = 0; index < 3; ++index) {
                check(actual.motion[index].rate == fraction(grid[index], 24), "Every inferred and prescribed rate matches the independent lattice search.");
                check(actual.prescribed[index].has_value() == (index != missing), "The result preserves which port was free.");
                check(actual.motion[index].state == (grid[index] == 0 ? g::MotionState::stopped : g::MotionState::rotating),
                      "Zero output is stopped rather than unpowered or stalled.");
            }
            std::reverse(observations.begin(), observations.end());
            check(solved(d::evaluate(observations)) == actual, "Observation order does not choose a different constraint solution.");
            ++pairs;
        }
    }
    for (I left = -12; left <= 12; ++left) for (I carrier = -12; carrier <= 12; ++carrier) for (I right = -12; right <= 12; ++right) {
        std::vector<d::Constraint> observations{{d::Port::right, fraction(right, 12)}, {d::Port::left, fraction(left, 12)},
                                                 {d::Port::carrier, fraction(carrier, 12)}};
        const bool consistent = 2 * carrier == left + right;
        const auto actual = solved(d::evaluate(observations));
        check(actual.outcome == (consistent ? d::Outcome::solved : d::Outcome::stalled),
              "The independently enumerated three-port equation distinguishes a stall from a consistent prescription.");
        const std::array<I, 3> values{left, carrier, right};
        for (std::size_t index = 0; index < 3; ++index) {
            check(actual.prescribed[index] == fraction(values[index], 12), "Even a conflict retains each original normalized prescription.");
            const g::Motion expected = consistent ? g::Motion{values[index] == 0 ? g::MotionState::stopped : g::MotionState::rotating, fraction(values[index], 12)}
                                                 : g::Motion{g::MotionState::stalled, {0, 1}};
            check(actual.motion[index] == expected, "A conflict stalls every port without publishing a partially compatible branch.");
        }
        observations.clear();
        check(actual.prescribed[0] == fraction(left, 12), "Evaluation data is owned after the caller destroys its observations.");
        ++triples;
    }
    check(pairs == 1875 && triples == 15625, "The complete declared two-port and three-port lattices were exercised.");
}
void invalid() {
    refusal(evaluate({}), d::Error::underdetermined);
    refusal(evaluate({{d::Port::left, {0, 1}}}), d::Error::underdetermined);
    refusal(evaluate({{d::Port::carrier, {1, 2}}}), d::Error::underdetermined);
    refusal(evaluate({{static_cast<d::Port>(-1), {0, 1}}}), d::Error::invalid_port);
    refusal(evaluate({{static_cast<d::Port>(3), {0, 1}}}), d::Error::invalid_port);
    refusal(evaluate({{d::Port::left, {1, 2}}, {d::Port::left, {2, 4}}}), d::Error::duplicate_port);
    for (const auto rate : {g::Rate{1, 0}, {1, -1}, {1, 1000001}, {257, 1}, {std::numeric_limits<I>::min(), 1}})
        refusal(evaluate({{d::Port::left, rate}}), d::Error::invalid_rate);
    refusal(evaluate({{d::Port::left, {0, 1}}, {d::Port::carrier, {0, 1}}, {d::Port::right, {0, 1}}, {d::Port::left, {0, 1}}}),
            d::Error::too_many_constraints);
    const auto normalized = solved(evaluate({{d::Port::left, {10, 4}}, {d::Port::right, {-9, 18}}, {d::Port::carrier, {99, 99}}}));
    check(normalized.outcome == d::Outcome::solved && normalized.prescribed[0] == g::Rate{5, 2},
          "Equivalent unreduced prescriptions are compared canonically rather than cross-multiplied.");
}
struct Output { int code; std::string text; std::string errors; };
Output run(std::initializer_list<std::string_view> args) {
    std::ostringstream out, errors;
    const int code = d::workbench(std::span(args.begin(), args.size()), out, errors);
    return {code, out.str(), errors.str()};
}
void caller() {
    const auto sum = run({"fast", "free", "reverse", "carrier"});
    check(sum.code == 0 && sum.errors.empty() && sum.text.find("left native fast rotating 5/2") != std::string::npos &&
          sum.text.find("right native reverse rotating -1/2") != std::string::npos && sum.text.find("carrier result rotating 1/1") != std::string::npos,
          "The summing solution uses actual independently derived geometric gear rates.");
    const auto doubled = run({"lock", "slow", "free", "right"});
    check(doubled.code == 0 && doubled.text.find("left explicitly locked") != std::string::npos &&
          doubled.text.find("carrier native slow rotating 1/2") != std::string::npos && doubled.text.find("right result rotating 1/1") != std::string::npos,
          "The alternate solution uses a real carrier drive and explicit side brake.");
    check(run({"free", "slow", "lock", "left"}).code == 0, "The symmetric braked assembly also matches its free readout.");
    const auto balanced = run({"slow", "free", "reverse", "carrier"});
    check(balanced.code == 1 && balanced.text.find("carrier result stopped 0/1") != std::string::npos,
          "A balanced moving assembly is unfinished rather than falsely stalled or matched.");
    check(run({"fast", "free", "fast", "carrier"}).code == 1, "A plausible but wrong positive speed remains unfinished.");
    const auto free = run({"free", "slow", "free", "right"});
    check(free.code == 1 && free.text.find("underdetermined") != std::string::npos && free.text.find("right result") == std::string::npos,
          "An unobserved port cannot be silently used as a brake.");
    const auto stalled = run({"lock", "stalled", "free", "right"});
    check(stalled.code == 1 && stalled.text.find("native stalled stalled 0/1") != std::string::npos && stalled.text.find("right result") == std::string::npos,
          "A genuinely stalled native source admits no imagined differential motion.");
    check(run({"free", "free", "free", "carrier"}).code == 1 && run({"lock", "lock", "free", "right"}).code == 1,
          "No source and two locks cannot manufacture the target speed.");
    check(run({"unknown", "free", "reverse", "carrier"}).code == 2 && run({"fast", "free", "reverse", "unknown"}).code == 2 &&
          run({"fast", "slow", "reverse", "left"}).code == 2 && run({"fast", "free"}).code == 2,
          "Unknown conditions, a prescribed readout and malformed startup are refused.");
    check(run({}).code == 0 && run({"list"}).code == 0 && run({"--help"}).code == 0, "The bounded catalogue and help are available.");
    std::ostringstream out, errors;
    out.setstate(std::ios::badbit);
    const std::array<std::string_view, 4> args{"fast", "free", "reverse", "carrier"};
    check(d::workbench(args, out, errors) == 2, "Output failure cannot be reported as a successful speed match.");
}
}  // namespace
int main() {
    try {
        literals(); lattice(); invalid(); caller();
        std::cout << checks << " differential assertions passed, including 1875 independent velocity searches and 15625 triple constraints.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " assertions: " << error.what() << '\n';
        return 1;
    }
}
