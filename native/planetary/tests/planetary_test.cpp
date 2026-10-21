#include "factory/planetary.hpp"
#include "factory/planetary_workbench.hpp"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>
#include <vector>

namespace p = factory::planetary;
namespace g = factory::mechanics;
namespace k = factory::geared_cycle;
using I = g::Integer;
namespace {
std::size_t assertions{}, mesh_witnesses{}, arrangements{};
void require(bool value, const char* message) {
    ++assertions;
    if (!value) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
g::Rate fraction(I n, I d = 1) { const I divisor = std::gcd(n, d); return {n / divisor, d / divisor}; }
g::Rate add(g::Rate a, g::Rate b) { return fraction(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator); }
g::Motion motion(g::Rate rate) { return {rate.numerator ? g::MotionState::rotating : g::MotionState::stopped, rate}; }
bool refused(const p::Result& result, p::Error reason) {
    const auto* value = std::get_if<p::Refusal>(&result);
    return value && value->reason == reason;
}

void controls() {
    const p::Profile profile;
    const std::array<p::Constraint, 2> reducer{{{p::Port::sun, {1, 1}}, {p::Port::ring, {0, 1}}}};
    const auto reduced = std::get<p::Evaluation>(p::evaluate(profile, reducer));
    require(reduced.outcome == p::Outcome::solved && reduced.motion[1].rate == g::Rate{1, 4} && reduced.motion[3].rate == g::Rate{-1, 2},
        "tooth-weighted ring lock gives a quarter-speed carrier and absolute planet spin");
    require(reduced.motion[1].rate != g::Rate{1, 2}, "an equal-weight differential is a discriminating wrong control");
    const std::array<p::Constraint, 2> fixed_carrier{{{p::Port::sun, {1, 1}}, {p::Port::carrier, {0, 1}}}};
    const auto reverse = std::get<p::Evaluation>(p::evaluate(profile, fixed_carrier));
    require(reverse.motion[2].rate == g::Rate{-1, 3} && reverse.motion[3].rate == g::Rate{-1, 1}, "fixed carrier reverses the internal ring through the external planet mesh");
    const std::array<p::Constraint, 2> fixed_sun{{{p::Port::sun, {0, 1}}, {p::Port::carrier, {1, 1}}}};
    const auto increased = std::get<p::Evaluation>(p::evaluate(profile, fixed_sun));
    require(increased.motion[2].rate == g::Rate{4, 3} && increased.motion[3].rate == g::Rate{2, 1}, "moving carrier contributes to both ring speed and absolute planet spin");
    const std::array<p::Constraint, 2> rotating_together{{{p::Port::sun, {1, 1}}, {p::Port::ring, {1, 1}}}};
    const auto together = std::get<p::Evaluation>(p::evaluate(profile, rotating_together));
    require(std::all_of(together.motion.begin(), together.motion.end(), [](auto m) { return m == motion({1, 1}); }),
        "zero relative mesh motion still carries a planet with nonzero absolute spin");
    std::array<p::Constraint, 3> conflict{{{p::Port::ring, {0, 7}}, {p::Port::carrier, {0, 9}}, {p::Port::sun, {2, 2}}}};
    const auto stalled = std::get<p::Evaluation>(p::evaluate(profile, conflict));
    conflict[2].rate = {0, 1};
    require(stalled.outcome == p::Outcome::stalled && stalled.prescribed[0] == g::Rate{1, 1} &&
        std::all_of(stalled.motion.begin(), stalled.motion.end(), [](auto m) { return m == g::Motion{g::MotionState::stalled, {0, 1}}; }),
        "incompatible triple owns normalized original prescriptions and stalls every member");
    const std::array<p::Constraint, 2> one_source{{{p::Port::sun, {1, 1}}, {p::Port::carrier, {0, 1}}}};
    require(refused(p::evaluate(profile, {one_source.data(), 1}), p::Error::underdetermined), "free is not an implicit locked carrier");
    require(refused(p::evaluate(profile, {}), p::Error::underdetermined), "no observations cannot pick a planetary motion");

    const auto minimum = std::numeric_limits<I>::min(), maximum = std::numeric_limits<I>::max();
    const std::array<p::Constraint, 2> extreme_reducible{{{p::Port::sun, {minimum, I{1} << 62}}, {p::Port::carrier, {0, maximum}}}};
    const auto normalized = std::get<p::Evaluation>(p::evaluate(profile, extreme_reducible));
    require(normalized.prescribed[0] == g::Rate{-2, 1} && normalized.prescribed[1] == g::Rate{0, 1} && normalized.motion[2].rate == g::Rate{2, 3},
        "reducible INT64_MIN and huge zero denominator normalize safely through native clock validation");
    const std::array<p::Constraint, 2> huge_equal{{{p::Port::sun, {maximum, maximum}}, {p::Port::ring, {1, 1}}}};
    require(std::get<p::Evaluation>(p::evaluate(profile, huge_equal)).motion == together.motion, "large reducible raw observations are not wrongly rejected before normalization");
    const std::array<p::Constraint, 2> fine{{{p::Port::sun, {2, 2000000}}, {p::Port::ring, {1, 1000000}}}};
    const auto fine_result = std::get<p::Evaluation>(p::evaluate(profile, fine));
    require(std::all_of(fine_result.motion.begin(), fine_result.motion.end(), [](auto m) { return m.rate == g::Rate{1, 1000000}; }),
        "native denominator cap applies after canonical reduction and preserves co-rotation exactly");

    const std::array<p::Constraint, 2> driven{{{p::Port::sun, {1, 1}}, {p::Port::carrier, {0, 1}}}};
    require(std::get<p::Evaluation>(p::evaluate({256, 1, 258}, driven)).motion[3].rate == g::Rate{-256, 1}, "exact native rate boundary for internal spin is admitted");
    const auto internal_limit = std::get<p::Refusal>(p::evaluate({257, 1, 259}, driven));
    require(internal_limit.reason == p::Error::unsupported_result && internal_limit.subject == p::Port::planet && internal_limit.rate_error == k::Error::rate_limit,
        "all external rates can fit while internal absolute spin refuses without partial output");
    const std::array<p::Constraint, 2> too_fast{{{p::Port::carrier, {256, 1}}, {p::Port::ring, {-256, 1}}}};
    const auto external_limit = std::get<p::Refusal>(p::evaluate(profile, too_fast));
    require(external_limit.reason == p::Error::unsupported_result && external_limit.subject == p::Port::sun, "unsupported inferred external rate refuses exactly");
    const std::array<p::Constraint, 3> incompatible{{{p::Port::sun, {1, 1}}, {p::Port::carrier, {256, 1}}, {p::Port::ring, {-256, 1}}}};
    require(std::get<p::Evaluation>(p::evaluate(profile, incompatible)).outcome == p::Outcome::stalled, "a contradictory prescribed triple stays a stall even if the conflicting pair would infer an unsupported rate");
    const std::array<p::Constraint, 2> incompatible_denominators{{{p::Port::sun, {1, 999983}}, {p::Port::carrier, {1, 999979}}}};
    require(refused(p::evaluate(profile, incompatible_denominators), p::Error::unsupported_result), "unsupported common denominator cannot be rounded into a motion");
    const std::array<p::Constraint, 2> wide_math{{{p::Port::sun, {256 * 999983 - 1, 999983}}, {p::Port::ring, {-(256 * 999979 - 1), 999979}}}};
    require(refused(p::evaluate({4094, 1, 4096}, wide_math), p::Error::unsupported_result), "largest coefficient and near-limit coprime rates remain safely bounded before refusal");
}

void validation() {
    const p::Profile profile;
    const auto minimum = std::numeric_limits<I>::min(), maximum = std::numeric_limits<I>::max();
    const std::array<p::Constraint, 2> valid{{{p::Port::sun, {1, 1}}, {p::Port::carrier, {0, 1}}}};
    for (const auto value : {minimum, I{-1}, I{0}, I{4097}, maximum}) for (int field = 0; field < 3; ++field) {
        auto bad = profile;
        if (field == 0) bad.sun = value;
        else if (field == 1) bad.planet = value;
        else bad.ring = value;
        require(refused(p::evaluate(bad, valid), p::Error::invalid_profile), "raw tooth counts refuse before sum or multiplication");
    }
    require(refused(p::evaluate({24, 24, 71}, valid), p::Error::invalid_profile), "same-pitch circles must close before solving their rates");
    const std::array<p::Constraint, 4> too_many{{valid[0], valid[1], {p::Port::ring, {0, 1}}, {p::Port::planet, {0, 1}}}};
    require(refused(p::evaluate(profile, too_many), p::Error::too_many_constraints), "complete excessive constraint set never truncates");
    for (auto bad_port : {p::Port::planet, static_cast<p::Port>(-1), static_cast<p::Port>(99)}) {
        auto bad = valid;
        bad[1].port = bad_port;
        require(refused(p::evaluate(profile, bad), p::Error::invalid_port), "only the three external ports accept prescriptions");
    }
    auto duplicate = valid;
    duplicate[1].port = p::Port::sun;
    require(refused(p::evaluate(profile, duplicate), p::Error::duplicate_port), "duplicate constraints do not become an artificial brake");
    for (const auto rate : {g::Rate{1, 0}, g::Rate{1, -1}, g::Rate{minimum, 1}, g::Rate{maximum, 1},
                           g::Rate{1, maximum}, g::Rate{1, minimum}, g::Rate{257, 1}, g::Rate{1, 1000001}}) {
        auto bad = valid;
        bad[1].rate = rate;
        const auto error = std::get<p::Refusal>(p::evaluate(profile, bad));
        require(error.reason == p::Error::invalid_rate && error.subject == p::Port::carrier && error.rate_error.has_value(), "all raw observation rates use existing exact validation before arithmetic");
    }
    const std::array<p::Constraint, 3> invalid_later{{valid[0], valid[1], {p::Port::ring, {1, 0}}}};
    require(refused(p::evaluate(profile, invalid_later), p::Error::invalid_rate), "bad final constraint cannot hide behind an earlier determinate pair");
    const std::array<p::Constraint, 3> zeros{{{p::Port::sun, {0, 13}}, {p::Port::carrier, {0, 17}}, {p::Port::ring, {0, 19}}}};
    const auto stopped = std::get<p::Evaluation>(p::evaluate(profile, zeros));
    require(stopped.outcome == p::Outcome::solved && std::all_of(stopped.motion.begin(), stopped.motion.end(), [](auto m) { return m.state == g::MotionState::stopped; }),
        "compatible explicit locks are stopped, distinct from unpowered or stalled");
}

// Independent local rolling witnesses: choose carrier c and signed SUN mesh
// tooth travel q. External sun/planet contact reverses q; internal planet/ring
// contact preserves that reversed direction. Thus local relative rates are
// q/S, -q/P, -q/R. Add c to each. This does not use the implementation's weighted
// three-port solve, inference routine or native clock validator as its oracle.
void independent_meshes() {
    for (I sun = 2; sun <= 10; ++sun) for (I planet = 1; planet <= 6; ++planet)
    for (I carrier_half = -4; carrier_half <= 4; ++carrier_half) for (I tooth_travel = -12; tooth_travel <= 12; ++tooth_travel) {
        ++mesh_witnesses;
        const p::Profile profile{sun, planet, sun + 2 * planet};
        const auto carrier = fraction(carrier_half, 2);
        const std::array<g::Rate, 4> expected{{add(carrier, fraction(tooth_travel, sun)), carrier,
            add(carrier, fraction(-tooth_travel, profile.ring)), add(carrier, fraction(-tooth_travel, planet))}};
        const std::array<g::Motion, 4> motions{{motion(expected[0]), motion(expected[1]), motion(expected[2]), motion(expected[3])}};
        for (std::size_t a = 0; a < 3; ++a) for (std::size_t b = a + 1; b < 3; ++b) for (bool reverse : {false, true}) {
            ++arrangements;
            std::array<p::Constraint, 2> constraints{{{static_cast<p::Port>(a), {expected[a].numerator * 2, expected[a].denominator * 2}},
                {static_cast<p::Port>(b), {expected[b].numerator * 3, expected[b].denominator * 3}}}};
            if (reverse) std::reverse(constraints.begin(), constraints.end());
            const auto result = p::evaluate(profile, constraints);
            const auto* solved = std::get_if<p::Evaluation>(&result);
            require(solved && solved->outcome == p::Outcome::solved && solved->motion == motions,
                "every external prescription pair recovers all independent local-mesh absolute rates");
            for (std::size_t index = 0; index < 3; ++index)
                require(solved->prescribed[index] == ((index == a || index == b) ? std::optional<g::Rate>(expected[index]) : std::nullopt),
                    "only supplied ports are prescribed and every owned value is canonical");
        }
        std::array<p::Constraint, 3> all{{{p::Port::ring, expected[2]}, {p::Port::sun, expected[0]}, {p::Port::carrier, expected[1]}}};
        ++arrangements;
        const auto consistent = std::get<p::Evaluation>(p::evaluate(profile, all));
        require(consistent.outcome == p::Outcome::solved && consistent.motion == motions, "independent compatible triple preserves all rates");
        all[0].rate = add(all[0].rate, {1, 1});
        ++arrangements;
        const auto stalled = std::get<p::Evaluation>(p::evaluate(profile, all));
        require(stalled.outcome == p::Outcome::stalled && std::all_of(stalled.motion.begin(), stalled.motion.end(),
            [](auto m) { return m == g::Motion{g::MotionState::stalled, {0, 1}}; }), "independent altered ring constraint stalls the entire gear set");
    }
}

void consumers() {
    struct Case { std::array<std::string_view, 5> args; int code; const char* witness; };
    const std::array<Case, 13> cases{{
        {{{"compact", "unit", "lock", "free", "ring"}}, 0, "ring result rotating -1/3."},
        {{{"compact", "double", "quarter", "free", "ring"}}, 0, "planet result rotating -3/2."},
        {{{"large-sun", "two-thirds", "lock", "free", "ring"}}, 0, "ring result rotating -1/3."},
        {{{"large-sun", "reverse", "free", "lock", "carrier"}}, 0, "carrier result rotating -1/3."},
        {{{"compact", "unit", "free", "lock", "carrier"}}, 1, "carrier result rotating 1/4."},
        {{{"compact", "lock", "unit", "free", "ring"}}, 1, "ring result rotating 4/3."},
        {{{"compact", "unit", "free", "free", "ring"}}, 1, "Unfinished: underdetermined."},
        {{{"compact", "off", "lock", "free", "ring"}}, 1, "sun native off unpowered 0/1."},
        {{{"compact", "stalled", "lock", "free", "ring"}}, 1, "Unfinished: a native source is stalled; no planetary motion is admitted."},
        {{{"mismatched", "unit", "lock", "free", "ring"}}, 1, "Unfinished: invalid_profile."},
        {{{"narrow", "double", "lock", "free", "ring"}}, 1, "Unfinished: unsupported_result at planet"},
        {{{"compact", "unit", "lock", "unit", "ring"}}, 2, ""},
        {{{"compact", "unit", "lock", "free", "planet"}}, 2, ""},
    }};
    for (const auto& value : cases) {
        std::ostringstream out, errors;
        const auto code = p::workbench(value.args, out, errors);
        require(code == value.code, "actual native-gear consumer exit matches solved/unfinished/malformed setup");
        if (code == 2) require(!errors.str().empty() && out.str().empty(), "prescribed or internal readout refuses before publishing output");
        else require(errors.str().empty() && out.str().find(value.witness) != std::string::npos, "actual native sources reach the declared planetary witness");
    }
    std::ostringstream out, errors;
    require(p::workbench({}, out, errors) == 0 && out.str().find("Planet readback is ABSOLUTE spin") != std::string::npos, "catalogue explains absolute and relative frames");
    const std::array<std::string_view, 5> unknown{{"unknown", "unit", "lock", "free", "ring"}};
    require(p::workbench(unknown, out, errors) == 2, "unknown profile is a malformed invocation");
    const std::array<std::string_view, 5> valid{{"compact", "unit", "lock", "free", "ring"}};
    out.setstate(std::ios::badbit);
    require(p::workbench(valid, out, errors) == 2, "failed output cannot report successful calibration");
}
}  // namespace

int main() {
    controls();
    validation();
    independent_meshes();
    consumers();
    std::cout << "Passed " << assertions << " assertions; " << mesh_witnesses << " independent local-mesh witnesses and "
              << arrangements << " prescribed-port arrangements.\n";
}
