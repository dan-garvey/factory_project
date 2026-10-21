#include "factory/cardan_pair.hpp"
#include "factory/cardan_pair_workbench.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace c = factory::cardan_pair;
namespace g = factory::mechanics;
namespace k = factory::geared_cycle;
using I = g::Integer;
using V = std::array<I, 3>;
namespace {
std::size_t assertions{}, profiles{}, phase_cases{}, spider_witnesses{}, rate_cases{}, unsupported{}, caller_traces{}, domain_refusals{}, clocked_frame_pairs{};
void require(bool value, const char* message) {
    ++assertions;
    if (!value) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
g::Rate fraction(I n, I d = 1) {
    require(d != 0, "independent oracle denominator is nonzero");
    if (d < 0) { n = -n; d = -d; }
    const auto divisor = std::gcd(n, d);
    return {n / divisor, d / divisor};
}
g::Rate multiply(g::Rate a, g::Rate b) {
    const auto first = std::gcd(a.numerator, b.denominator), second = std::gcd(b.numerator, a.denominator);
    return fraction((a.numerator / first) * (b.numerator / second), (a.denominator / second) * (b.denominator / first));
}
c::Dial primitive(I x, I y) { const auto divisor = std::gcd(x, y); return {x / divisor, y / divisor}; }
V cross(V a, V b) { return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]}; }
I dot(V a, V b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
g::Motion motion(g::Rate rate) { return {rate.numerator ? g::MotionState::rotating : g::MotionState::stopped, rate}; }
std::optional<k::Error> limit(g::Rate rate) {
    const auto check = k::prepare(k::maximum_teeth, {}, rate, false);
    if (const auto* error = std::get_if<k::Error>(&check)) return *error;
    return {};
}
bool refused(const c::Result& result, c::Error reason, std::size_t stage = 0) {
    const auto* value = std::get_if<c::Refusal>(&result);
    return value && value->reason == reason && value->stage == stage;
}

struct Oracle { c::Dial next; g::Rate derivative; };
Oracle spider(const c::Joint& joint, c::Dial input) {
    const auto p = joint.bend.cosine, s = joint.bend.sine, q = joint.bend.scale;
    const V axis{0, 0, 1}, tilted{0, s, p}, first_basis{0, p, -s}, second_basis{-1, 0, 0};
    V u{}, v{};
    c::Dial next;
    if (joint.mount == c::Mount::forward) {
        u = {input.x, input.y, 0};
        // The actual second spider pin lies perpendicular to BOTH the first
        // pin and tilted shaft. Project that cross product onto its yoke frame.
        const auto pin = cross(tilted, u);
        next = primitive(dot(pin, first_basis), q * dot(pin, second_basis));
        v = {-q * next.y, p * next.x, -s * next.x};
    } else {
        v = {-q * input.y, p * input.x, -s * input.x};
        const auto pin = cross(v, axis);
        next = primitive(pin[0], pin[1]);
        u = {next.x, next.y, 0};
    }
    require(dot(u, axis) == 0 && dot(v, tilted) == 0 && dot(u, v) == 0,
        "independent 3D spider pins remain perpendicular to their shafts and each other");
    // Differentiate u.v=0 using omega*(unit shaft axis x pin). This oracle
    // never uses the production tangent formula or its diagonal coefficients.
    const auto first_term = q * dot(cross(axis, u), v), second_term = dot(u, cross(tilted, v));
    return {next, joint.mount == c::Mount::forward ? fraction(-first_term, second_term) : fraction(-second_term, first_term)};
}

void geometry_witnesses() {
    const std::array<c::Bend, 8> bends{{{1, 0, 1}, {3, 4, 5}, {4, 3, 5}, {5, 12, 13}, {12, 5, 13}, {8, 15, 17}, {7, 24, 25}, {20, 21, 29}}};
    const std::array<g::Rate, 4> rates{{{0, 1}, {1, 1}, {-1, 1}, {2, 3}}};
    for (auto a : bends) for (auto b : bends) for (I side_a : {-1, 1}) for (I side_b : {-1, 1}) {
        if ((!a.sine && side_a < 0) || (!b.sine && side_b < 0)) continue;
        a.sine = std::abs(a.sine) * side_a;
        b.sine = std::abs(b.sine) * side_b;
        for (auto mount_a : {c::Mount::forward, c::Mount::compensating}) for (auto mount_b : {c::Mount::forward, c::Mount::compensating}) {
            const c::Profile profile{{{{a, mount_a}, {b, mount_b}}}};
            const auto middle_diagonal = spider(profile.joints[0], {1, 1}).next;
            const bool constant = spider(profile.joints[1], middle_diagonal).next == c::Dial{1, 1};
            ++profiles;
            for (I x = -4; x <= 4; ++x) for (I y = -4; y <= 4; ++y) if (std::gcd(x, y) == 1) {
                const c::Dial dial{x, y};
                const auto first = spider(profile.joints[0], dial), second = spider(profile.joints[1], first.next);
                spider_witnesses += 2;
                ++phase_cases;
                for (auto rate : rates) {
                    ++rate_cases;
                    const auto candidate = c::evaluate(profile, dial, motion(rate));
                    const auto middle_rate = multiply(rate, first.derivative);
                    if (const auto error = limit(middle_rate)) {
                        const auto* refusal = std::get_if<c::Refusal>(&candidate);
                        require(refusal && refusal->reason == c::Error::unsupported_result && refusal->stage == 1 && refusal->rate_error == *error,
                            "unsupported intermediate reading never leaks a partial pair");
                        ++unsupported;
                        continue;
                    }
                    const auto output_rate = multiply(middle_rate, second.derivative);
                    if (const auto error = limit(output_rate)) {
                        const auto* refusal = std::get_if<c::Refusal>(&candidate);
                        require(refusal && refusal->reason == c::Error::unsupported_result && refusal->stage == 2 && refusal->rate_error == *error,
                            "unsupported final reading never rounds its denominator");
                        ++unsupported;
                        continue;
                    }
                    require(std::holds_alternative<c::Evaluation>(candidate), "independently representable spider reading is admitted");
                    const auto& value = std::get<c::Evaluation>(candidate);
                    require(value.profile == profile && value.dial == std::array<c::Dial, 3>{dial, first.next, second.next},
                        "owned projective poses match independent 3D pin intersections in every quadrant");
                    require(value.factors == std::array<g::Rate, 2>{first.derivative, second.derivative} &&
                        value.motion == std::array<g::Motion, 3>{motion(rate), motion(middle_rate), motion(output_rate)},
                        "instantaneous native signed rates match the differentiated orthogonality oracle");
                    require(value.composite.constant_rate() == constant && std::gcd(value.composite.x, value.composite.y) == 1,
                        "the whole-map certificate agrees with an independent geometric diagonal direction");
                    for (auto pose : value.dial) require(std::gcd(pose.x, pose.y) == 1 && (pose.x == 0 || (pose.x > 0) == (x > 0)) &&
                        (pose.y == 0 || (pose.y > 0) == (y > 0)), "primitive reduction cannot identify opposite dial quadrants");
                    require(value.output_axis.y * value.output_axis.y + value.output_axis.z * value.output_axis.z == value.output_axis.scale * value.output_axis.scale,
                        "composed signed bend remains an exact unit shaft direction");
                    if (constant) require(value.motion[2] == motion(rate), "a valid constant composite preserves the input rate at every tested pose");
                }
            }
        }
    }
}

void discriminators_and_limits() {
    c::Profile profile;
    const auto driven = motion({1, 1});
    const auto at_zero = std::get<c::Evaluation>(c::evaluate(profile, {1, 0}, driven));
    const auto at_quarter = std::get<c::Evaluation>(c::evaluate(profile, {0, 1}, driven));
    require(at_zero.motion[1] == motion({3, 5}) && at_quarter.motion[1] == motion({5, 3}) && at_zero.motion[2] == driven && at_quarter.motion[2] == driven,
        "correct opposite-bend pair cancels variable intermediate speed including the projective quarter-turn pole");
    require(at_zero.middle_axis == c::AxisDirection{4, 3, 5} && at_zero.output_axis == c::AxisDirection{0, 1, 1} && at_zero.composite == c::Diagonal{1, 1},
        "matched opposite bends return parallel output axes and an exact identity phase map");
    auto wrong = profile; wrong.joints[1].mount = c::Mount::forward;
    const auto misleading = std::get<c::Evaluation>(c::evaluate(wrong, {3, 5}, driven));
    require(misleading.motion[2] == driven && !misleading.composite.constant_rate() && misleading.composite == c::Diagonal{25, 9},
        "a wrong double yoke can match one exact speed without a constant whole-rotation map");
    require(std::get<c::Evaluation>(c::evaluate(wrong, {1, 0}, driven)).motion[2] == motion({9, 25}), "the misleading case differs at another pose without relying on average speed");
    auto same_bend = profile; same_bend.joints[1].bend.sine = 4;
    const auto same = std::get<c::Evaluation>(c::evaluate(same_bend, {}, driven));
    require(same.composite.constant_rate() && same.output_axis == c::AxisDirection{24, -7, 25}, "constant output alone does not imply a parallel fixed readout axis");
    for (auto state : {g::MotionState::unpowered, g::MotionState::stopped, g::MotionState::stalled}) {
        const auto paused = std::get<c::Evaluation>(c::evaluate(profile, {-3, -5}, {state, {0, std::numeric_limits<I>::max()}}));
        require(std::all_of(paused.motion.begin(), paused.motion.end(), [state](const auto& m) { return m == g::Motion{state, {}}; }) && paused.dial[0] == c::Dial{-3, -5},
            "unpowered, stopped and stalled retain their distinct native state without advancing a live input dial");
    }
    const auto minimum = std::numeric_limits<I>::min(), maximum = std::numeric_limits<I>::max();
    c::Dial dial{-3, -5};
    auto input = motion({minimum, I{1} << 62});
    const auto owned = std::get<c::Evaluation>(c::evaluate(profile, dial, input));
    profile.joints[0].bend = {1, 0, 1}; dial = {}; input = {};
    require(owned.motion[0] == motion({-2, 1}) && owned.motion[2] == motion({-2, 1}) && owned.profile.joints[0].bend == c::Bend{3, 4, 5} && owned.dial[0] == c::Dial{-3, -5},
        "raw MIN reduces before bounded rate arithmetic and every returned profile, dial and motion is owned");
    profile = {};
    require(std::get<c::Evaluation>(c::evaluate(profile, {}, motion({maximum, maximum}))).motion[2] == driven, "huge reducible native input is normalized before multiplication");
    const auto middle_limit = std::get<c::Refusal>(c::evaluate(profile, {0, 1}, motion({256, 1})));
    require(middle_limit.reason == c::Error::unsupported_result && middle_limit.stage == 1 && middle_limit.rate_error == k::Error::rate_limit,
        "even a constant final 256 reading cannot hide an unsupported intermediate 1280/3");
    require(std::get<c::Evaluation>(c::evaluate(profile, {}, motion({256, 1}))).motion[2] == motion({256, 1}), "exact native speed boundary is admitted when both intermediate and final fit");
    auto inverse_twice = profile; inverse_twice.joints[0].mount = c::Mount::compensating;
    require(refused(c::evaluate(inverse_twice, {}, motion({128, 1})), c::Error::unsupported_result, 2), "second-stage speed overflow is reported after a representable intermediate");
    require(refused(c::evaluate(profile, {}, motion({1, 999983})), c::Error::unsupported_result, 1), "a restored final denominator cannot conceal an unsupported intermediate precision");
    require(std::get<c::Evaluation>(c::evaluate(profile, {}, motion({5, 999983}))).motion[2] == motion({5, 999983}), "rate factors are multiplied before final reduction/admission, allowing exact cancellation");
    for (c::Dial edge : {c::Dial{64, 63}, {63, -64}, {-64, -63}, {-63, 64}}) {
        const auto reading = c::evaluate(profile, edge, motion({1, 1}));
        const auto a = spider(profile.joints[0], edge), b = spider(profile.joints[1], a.next);
        if (!limit(a.derivative) && !limit(multiply(a.derivative, b.derivative)))
            require(std::get<c::Evaluation>(reading).dial[2] == edge, "near-bound primitive dials remain exact without atan or rounding");
        else require(std::holds_alternative<c::Refusal>(reading), "near-bound unsupported instantaneous precision refuses exactly");
    }
}

void validation() {
    const c::Profile profile;
    const auto low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    for (std::size_t stage = 0; stage < 2; ++stage) for (int field = 0; field < 3; ++field) {
        const auto values = field == 1 ? std::vector<I>{low, -33, 33, high} : std::vector<I>{low, -1, 0, 33, high};
        for (auto value : values) {
            auto bad = profile;
            auto& bend = bad.joints[stage].bend;
            if (field == 0) bend.cosine = value;
            else if (field == 1) bend.sine = value;
            else bend.scale = value;
            require(refused(c::evaluate(bad, {}, {}), c::Error::invalid_profile, stage), "complete raw bend validation runs even when unpowered and before squaring extrema");
        }
    }
    for (std::size_t stage = 0; stage < 2; ++stage) {
        auto bad = profile; bad.joints[stage].bend.sine += 1;
        require(refused(c::evaluate(bad, {}, {}), c::Error::invalid_profile, stage), "non-unit Pythagorean bend refuses the entire profile");
        for (int value : {-1, 2, 99}) {
            bad = profile; bad.joints[stage].mount = static_cast<c::Mount>(value);
            require(refused(c::evaluate(bad, {}, {}), c::Error::invalid_mount, stage), "unknown yoke mounting enum never picks a default branch");
        }
    }
    for (auto dial : {c::Dial{0, 0}, {2, 0}, {2, 2}, {-2, 4}, {65, 1}, {1, -65}, {low, 1}, {1, high}})
        require(refused(c::evaluate(profile, dial, {}), c::Error::invalid_dial), "one caller-owned dial must already be bounded, nonzero and primitive");
    for (auto rate : {g::Rate{0, 0}, {1, -1}, {0, low}, {low, 1}, {high, 1}, {1, 1000001}, {257, 1}})
        require(refused(c::evaluate(profile, {}, {g::MotionState::unpowered, rate}), c::Error::invalid_rate), "raw rates are validated even when power is absent");
    require(refused(c::evaluate(profile, {}, {g::MotionState::rotating, {}}), c::Error::invalid_motion), "rotating zero contradicts native motion semantics");
    for (auto state : {g::MotionState::unpowered, g::MotionState::stopped, g::MotionState::stalled, static_cast<g::MotionState>(99)})
        require(refused(c::evaluate(profile, {}, {state, {1, 1}}), c::Error::invalid_motion), "nonrotating states cannot carry a hidden prescribed speed");
    auto scaled = profile;
    scaled.joints[0].bend = {6, 8, 10}; scaled.joints[1].bend = {6, -8, 10};
    const auto scaled_value = std::get<c::Evaluation>(c::evaluate(scaled, {3, 5}, motion({1, 1})));
    const auto normal = std::get<c::Evaluation>(c::evaluate(profile, {3, 5}, motion({1, 1})));
    require(scaled_value.dial == normal.dial && scaled_value.motion == normal.motion && scaled_value.output_axis == normal.output_axis,
        "equivalent bounded Pythagorean triples retain the same exact physical reading");
}

void domain_admission() {
    c::Profile steep;
    steep.joints = {{{{5, 12, 13}, c::Mount::forward}, {{5, -12, 13}, c::Mount::compensating}}};
    require(refused(c::evaluate(steep, {63, 64}, motion({1, 2})), c::Error::unsupported_result, 1),
        "a mathematically constant kit can have an unsupported intermediate reading at another allowed primitive dial");
    const std::array<std::string_view, 4> args{"steep", "slow", "same", "full"};
    std::ostringstream out, errors;
    require(c::workbench(args, out, errors) == 2 && out.str().find("Goal matched:") == std::string::npos && !errors.str().empty(),
        "a whole-map victory must refuse a hidden unsupported intermediate anywhere in the bounded dial domain");
}

Oracle clocked_spider(const c::Joint& joint, c::Dial input) {
    const auto p = joint.bend.cosine, s = joint.bend.sine, q = joint.bend.scale;
    const bool clocked = joint.mount == c::Mount::compensating;
    const auto pin_dial = clocked ? c::Dial{-input.y, input.x} : input;
    const V axis{0, 0, 1}, tilted{0, s, p}, u{pin_dial.x, pin_dial.y, 0};
    const auto pin = cross(tilted, u);
    const auto projected = primitive(dot(pin, {0, p, -s}), q * dot(pin, {-1, 0, 0}));
    const auto next = clocked ? c::Dial{projected.y, -projected.x} : projected;
    const auto out_pin_dial = clocked ? c::Dial{-next.y, next.x} : next;
    const V v{-q * out_pin_dial.y, p * out_pin_dial.x, -s * out_pin_dial.x};
    require(dot(axis, u) == 0 && dot(tilted, v) == 0 && dot(u, v) == 0,
        "quarter-clocked actual fork references retain the SAME physical input/output shaft axes and orthogonal spider pins");
    return {next, fraction(-q * dot(cross(axis, u), v), dot(u, cross(tilted, v)))};
}

void clocked_framing() {
    // Additional physical-frame qualification, not a regression claim. The
    // original model oracle used the reciprocal joint's shaft-exchange dual.
    // Here both fork references rotate by a fixed quarter turn on the original
    // shafts. Their static phase offsets leave the angular derivatives intact.
    const std::array<c::Bend, 8> bends{{{1, 0, 1}, {3, 4, 5}, {4, 3, 5}, {5, 12, 13}, {12, 5, 13}, {8, 15, 17}, {7, 24, 25}, {20, 21, 29}}};
    const std::array<c::Dial, 10> dials{{{1, 0}, {0, 1}, {-1, 0}, {0, -1}, {1, 1}, {-1, -1}, {3, 5}, {-3, -5}, {64, 63}, {-63, 64}}};
    for (auto bend : bends) for (I side : {-1, 1}) {
        if (!bend.sine && side < 0) continue;
        bend.sine = std::abs(bend.sine) * side;
        for (auto first_mount : {c::Mount::forward, c::Mount::compensating}) for (auto second_mount : {c::Mount::forward, c::Mount::compensating}) {
            auto second_bend = bend; second_bend.sine = -second_bend.sine;
            const c::Profile profile{{{{bend, first_mount}, {second_bend, second_mount}}}};
            for (const auto dial : dials) {
                const auto first = clocked_spider(profile.joints[0], dial), second = clocked_spider(profile.joints[1], first.next);
                const auto value = std::get<c::Evaluation>(c::evaluate(profile, dial, {g::MotionState::stopped, {}}));
                require(value.dial == std::array<c::Dial, 3>{dial, first.next, second.next} && value.factors == std::array<g::Rate, 2>{first.derivative, second.derivative},
                    "actual clocked-fork pin frames reproduce both stage poses and analytical velocity factors while paused");
                // Rotate the second physical shaft through the first joint's
                // complete local frame, independently of the production sum.
                const V local{0, second_bend.sine, second_bend.cosine};
                const V global{bend.scale * local[0], bend.cosine * local[1] + bend.sine * local[2], -bend.sine * local[1] + bend.cosine * local[2]};
                const auto denominator = bend.scale * second_bend.scale;
                const auto divisor = std::gcd(std::gcd(global[1], global[2]), denominator);
                require(value.output_axis == c::AxisDirection{global[1] / divisor, global[2] / divisor, denominator / divisor},
                    "physical shaft composition is independent of fork clocking and respects the specified global bend frame");
                ++clocked_frame_pairs;
            }
        }
    }
}

void further_domain_controls() {
    for (const auto args : {std::array<std::string_view, 4>{"steep", "reverse", "reverse", "full"},
        {"lean", "slow", "same", "full"}, {"lean", "reverse", "reverse", "full"}}) {
        std::ostringstream out, errors;
        require(c::workbench(args, out, errors) == 2 && out.str().find("Goal matched:") == std::string::npos &&
            errors.str().find("Whole dial domain refused") != std::string::npos,
            "all larger-kit controls refuse native precision rather than falsely winning a mechanical puzzle");
        ++domain_refusals;
    }
}

I primitive_domain_size() {
    // Independent number-theory count, rather than repeating the consumer's
    // coordinate enumeration: eight times the totient sum counts the square.
    std::vector<I> totients(static_cast<std::size_t>(c::maximum_dial_component + 1));
    std::iota(totients.begin(), totients.end(), 0);
    for (I prime = 2; prime <= c::maximum_dial_component; ++prime) if (totients[prime] == prime)
        for (I value = prime; value <= c::maximum_dial_component; value += prime) totients[value] -= totients[value] / prime;
    return 8 * std::accumulate(totients.begin(), totients.end(), I{});
}

void caller() {
    struct Case { std::array<std::string_view, 4> args; std::string_view witness; bool matched{}; };
    const std::array<Case, 20> cases{{
        {{{"balanced", "slow", "same", "full"}}, "output shaft half-span 30", true},
        {{{"balanced", "reverse", "reverse", "full"}}, "readout rotating 1/2", true},
        {{{"shallow", "slow", "same", "full"}}, "output shaft half-span 16", true},
        {{{"shallow", "reverse", "reverse", "full"}}, "readout rotating 1/2", true},
        {{{"wrong-yokes", "slow", "same", "full"}}, "coefficients 25:9; constant no"},
        {{{"wrong-yokes", "reverse", "reverse", "full"}}, "readout rotating 1/2"},
        {{{"unequal", "slow", "same", "full"}}, "output axis is not the fixed +Z"},
        {{{"same-bend", "slow", "same", "full"}}, "coefficients 1:1; constant yes"},
        {{{"offset", "slow", "same", "full"}}, "readout unpowered 0/1"},
        {{{"balanced", "slow", "same", "short"}}, "readout unpowered 0/1"},
        {{{"shallow", "reverse", "reverse", "short"}}, "readout unpowered 0/1"},
        {{{"balanced", "reverse", "same", "full"}}, "readout rotating -1/2"},
        {{{"balanced", "slow", "reverse", "full"}}, "readout rotating -1/2"},
        {{{"balanced", "fast", "same", "full"}}, "readout rotating 5/2"},
        {{{"balanced", "fast", "reverse", "full"}}, "readout rotating -5/2"},
        {{{"shallow", "slow", "reverse", "full"}}, "readout rotating -1/2"},
        {{{"shallow", "reverse", "same", "full"}}, "readout rotating -1/2"},
        {{{"shallow", "fast", "same", "full"}}, "readout rotating 5/2"},
        {{{"balanced", "off", "same", "full"}}, "source unpowered; no output drive is admitted"},
        {{{"balanced", "stalled", "same", "full"}}, "source stalled; no output drive is admitted"},
    }};
    for (const auto& example : cases) {
        std::ostringstream out, errors;
        require(c::workbench(example.args, out, errors) == 0 && errors.str().empty(), "valid kit produces an actual native consumer trace");
        require(out.str().find(example.witness) != std::string::npos && (out.str().find("Goal matched:") != std::string::npos) == example.matched,
            "whole-map cadence, physical axis, shaft reach and actual native source/output gears determine the goal");
        if (example.matched) require(out.str().find(std::to_string(primitive_domain_size()) + " primitive directions admitted") != std::string::npos,
            "every successful kit covers the full bounded native dial domain with an independently counted cardinality");
        if (example.args[0] == "wrong-yokes") require(out.str().find(example.args[1] == "reverse" ? "joints -1/2; readout rotating 1/2" : "joints 1/2; readout rotating 1/2") != std::string::npos,
            "a real native readout can match one pose while the exact global certificate still rejects the puzzle");
        ++caller_traces;
    }
    const std::array<std::vector<std::string_view>, 7> invalid{{{"balanced"}, {"balanced", "slow", "same"}, {"balanced", "slow", "same", "full", "extra"},
        {"missing", "slow", "same", "full"}, {"balanced", "missing", "same", "full"}, {"balanced", "slow", "missing", "full"}, {"balanced", "slow", "same", "missing"}}};
    for (const auto& args : invalid) {
        std::ostringstream out, errors;
        require(c::workbench(args, out, errors) == 2 && out.str().empty() && !errors.str().empty(), "invalid argv refuses before mechanical proposals");
    }
    std::ostringstream out, errors;
    const std::array<std::string_view, 1> args{"list"};
    require(c::workbench(args, out, errors) == 0 && out.str().find("not a time integration") != std::string::npos, "catalogue states the instantaneous-reading and authority limits");
    out.setstate(std::ios::badbit);
    require(c::workbench(args, out, errors) == 2, "failed output is never a successful trace");
}
}  // namespace

int main(int argc, char** argv) {
    const bool consumer = argc == 2 && std::string_view(argv[1]) == "--consumer-only";
    const bool framing = argc == 2 && std::string_view(argv[1]) == "--framing-only";
    if (argc > 1 && !consumer && !framing) return 2;
    if (consumer) {
        domain_admission();
        ++domain_refusals;
        further_domain_controls();
        caller();
    } else if (framing) {
        clocked_framing();
    } else {
        geometry_witnesses();
        discriminators_and_limits();
        validation();
    }
    std::cout << assertions << " assertions; " << profiles << " paired profiles; " << phase_cases << " projective phase cases; "
        << spider_witnesses << " independent 3D spider witnesses; " << rate_cases << " rate cases (" << unsupported << " exact representation refusals); "
        << caller_traces << " original native caller traces; " << domain_refusals << " full-domain refusals; " << clocked_frame_pairs << " physical clocked-frame pairs passed.\n";
}
