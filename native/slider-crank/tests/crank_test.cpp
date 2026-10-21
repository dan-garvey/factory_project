#include "factory/slider_crank.hpp"
#include "factory/slider_crank_workbench.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace s = factory::slider_crank;
namespace g = factory::mechanics;
namespace k = factory::geared_cycle;
using I = g::Integer;
using F = g::Rate;
namespace {
std::size_t assertions{}, coordinate_cases{}, pose_cases{}, unreachable{}, cycles{}, caller_traces{};
void require(bool value, const char* message) {
    ++assertions;
    if (!value) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
F fraction(I n, I d = 1) {
    require(d > 0, "independent rational oracle denominator is positive");
    const auto divisor = std::gcd(n, d);
    return {n / divisor, d / divisor};
}
F add(F a, F b) { return fraction(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator); }
F scale(F a, I n) { return fraction(a.numerator * n, a.denominator); }
F multiply(F a, F b) { return fraction(a.numerator * b.numerator, a.denominator * b.denominator); }
g::Motion moving(F rate = {1, 2}) { return {g::MotionState::rotating, rate}; }
template<class T> bool refused(const T& value, s::Error reason) {
    const auto* error = std::get_if<s::Refusal>(&value);
    return error && error->reason == reason;
}
long double numeric(const s::Coordinate& c) {
    return (c.base + (c.branch == s::Branch::positive ? 1 : -1) * std::sqrt(static_cast<long double>(c.radicand))) / c.denominator;
}

void exact_coordinates() {
    for (I root = 0; root <= 128; ++root) for (I base : {-1000000, -17, 0, 17, 1000000})
    for (I denominator : {1, 2, 5, 17, 256}) for (auto branch : {s::Branch::positive, s::Branch::negative}) {
        const s::Coordinate c{base, root * root, denominator, branch};
        const I signed_root = branch == s::Branch::positive ? root : -root;
        const auto expected = fraction(base + signed_root, denominator);
        require(std::get<std::optional<F>>(s::rational_view(c)) == std::optional<F>{expected}, "perfect square views reduce exactly, including signed branches and zero");
        for (I target : {-1000000, -100, -1, 0, 1, 100, 1000000}) {
            const I left = base + signed_root, right = target * denominator;
            const auto order = left < right ? s::Order::less : left > right ? s::Order::greater : s::Order::equal;
            require(std::get<s::Order>(s::compare_to_grid(c, target)) == order, "root comparison agrees with an independent signed rational cross product");
            ++coordinate_cases;
        }
    }
    auto interval = [](I n, I between) {
        // n² < K < (n+1)² is an exact independent bracket. Put the
        // corresponding irrational coordinate just below/above an integer,
        // including at both native grid extremes, without computing sqrt(K).
        const I squared = n * n + between;
        require(between > 0 && between < 2 * n + 1, "independent irrational bracket is strict");
        for (I denominator : {1, 2, 5, 17, 256}) for (I target : {-1000000, -17, 0, 1, 1000000}) {
            const std::array<s::Coordinate, 4> values{{{target * denominator - n, squared, denominator, s::Branch::positive},
                {target * denominator - n - 1, squared, denominator, s::Branch::positive},
                {target * denominator + n, squared, denominator, s::Branch::negative},
                {target * denominator + n + 1, squared, denominator, s::Branch::negative}}};
            for (std::size_t i = 0; i < values.size(); ++i) {
                require(std::get<s::Order>(s::compare_to_grid(values[i], target)) == (i == 0 || i == 3 ? s::Order::greater : s::Order::less),
                    "nonsquare coordinates preserve the correct side of exact grid limits without rounding");
                require(!std::get<std::optional<F>>(s::rational_view(values[i])), "a nonsquare has no invented rational view");
                ++coordinate_cases;
            }
        }
    };
    for (I n = 1; n <= 64; ++n) for (I between = 1; between <= 2 * n; ++between) interval(n, between);
    for (I n : {1023, 4096, 65535, 1048575}) for (I between : {I{1}, n, 2 * n}) interval(n, between);
    const I low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    for (const auto c : {s::Coordinate{low, 0, 1}, {high, 0, 1}, {0, low, 1}, {0, high, 1}, {0, -1, 1}, {0, 1, 0}, {0, 1, -1}, {0, 1, 257}, {0, 1, high}, {0, 0, 1, static_cast<s::Branch>(-1)}}) {
        require(std::get<s::Error>(s::compare_to_grid(c, 0)) == s::Error::invalid_coordinate && std::get<s::Error>(s::rational_view(c)) == s::Error::invalid_coordinate,
            "raw root extrema and unknown branches refuse before products or binary search");
    }
    for (I target : {low, high, -g::maximum_coordinate - 1, g::maximum_coordinate + 1})
        require(std::get<s::Error>(s::compare_to_grid({}, target)) == s::Error::invalid_grid, "raw comparison targets are bounded before multiplication");
}

void circle_rod_and_cycle() {
    const std::array<s::Direction, 12> directions{{{}, {0, 1, 1}, {-1, 0, 1}, {0, -1, 1}, {3, 4, 5}, {-3, 4, 5}, {3, -4, 5}, {-3, -4, 5}, {5, 12, 13}, {-5, 12, 13}, {8, 15, 17}, {20, -21, 29}}};
    const std::array<g::Motion, 5> motions{{moving(), moving({-7, 11}), {g::MotionState::unpowered, {}}, {g::MotionState::stopped, {}}, {g::MotionState::stalled, {}}}};
    for (std::size_t a = 0; a < 3; ++a) for (std::size_t u = 0; u < 3; ++u) {
        if (a == u) continue;
        const auto v = 3 - a - u;
        std::array<I, 3> normal{}, travel{}; normal[a] = 1; travel[u] = 1;
        const std::array<I, 3> transverse{normal[1] * travel[2] - normal[2] * travel[1], normal[2] * travel[0] - normal[0] * travel[2], normal[0] * travel[1] - normal[1] * travel[0]};
        for (const auto origin : {g::Point{0, 0, 8}, {-42, 17, 36}}) for (I radius : {1, 3, 5}) for (I length : {1, 2, 3, 5, 7, 10})
        for (I offset : {-4, -1, 0, 1, 4}) for (auto branch : {s::Branch::positive, s::Branch::negative}) {
            s::Profile p; p.origin = origin; p.shaft = static_cast<g::Axis>(a); p.travel = static_cast<g::Axis>(u);
            p.radius = radius; p.rod_length = length; p.guide_offset = offset; p.branch = branch; p.lower = -1000000; p.upper = 1000000;
            const auto cycle = std::get<s::Cycle>(s::inspect(p));
            const s::Direction worst{0, offset > 0 ? -1 : 1, 1};
            const auto worst_pose = s::sample(p, worst, moving());
            require(cycle.closed() != refused(worst_pose, s::Error::unreachable), "the exact opposite transverse crank extremum independently witnesses worst complete-turn rod reach");
            require(cycle.extrema.has_value() == cycle.closed() && cycle.guide_fits == cycle.closed(), "an impossible full cycle never publishes invented extrema or guide acceptance");
            if (cycle.closed()) {
                require(cycle.regular() == std::get<s::Sample>(worst_pose).per_radian.has_value(), "regular full-cycle reach is distinct from zero longitudinal projection");
                for (std::size_t end = 0; end < 2; ++end) {
                    const auto& c = (*cycle.extrema)[end];
                    const I reach = branch == s::Branch::positive ? (end ? length + radius : length - radius) : (end ? length - radius : length + radius);
                    require(c.base == origin[u] && c.denominator == 1 && c.branch == branch && c.radicand + offset * offset == reach * reach,
                        "slider extrema lie on the independent inner/outer tangent circles about the crank axis");
                }
            }
            ++cycles;
            for (const auto direction : directions) for (const auto input : motions) {
                const auto reading = s::sample(p, direction, input);
                const F along = fraction(radius * direction.cosine, direction.scale), across = fraction(radius * direction.sine * transverse[v], direction.scale);
                const F gap = add(fraction(transverse[v] * offset), scale(across, -1));
                const bool reaches = gap.numerator * gap.numerator <= length * length * gap.denominator * gap.denominator;
                if (!reaches) { require(refused(reading, s::Error::unreachable), "the crank-pin-to-guide perpendicular distance exceeds the finite rod length"); ++unreachable; continue; }
                require(std::holds_alternative<s::Sample>(reading), "independently reachable circle/guide pose retains an exact coordinate");
                const auto& sample = std::get<s::Sample>(reading);
                require(sample.profile == p && sample.direction == direction && sample.crank == input, "owned profile/direction and all native source states remain distinct");
                require(sample.pin[u] == add(fraction(origin[u]), along) && sample.pin[v] == add(fraction(origin[v]), across) && sample.pin[a] == fraction(origin[a]) &&
                    sample.guide_anchor[v] == origin[v] + transverse[v] * offset && sample.guide_anchor[a] == origin[a], "the exact 3D crank and fixed guide follow the independent right-handed frame");
                const auto& c = sample.slider;
                require(fraction(c.base, c.denominator) == sample.pin[u] && c.branch == branch &&
                    add(fraction(c.radicand, c.denominator * c.denominator), multiply(gap, gap)) == fraction(length * length),
                    "the exact radical longitudinal component and physical transverse component close the full rod-length constraint");
                s::Point r{}; r[u] = along; r[v] = across;
                const s::Point pin_derivative{add(scale(r[2], normal[1]), scale(r[1], -normal[2])), add(scale(r[0], normal[2]), scale(r[2], -normal[0])), add(scale(r[1], normal[0]), scale(r[0], -normal[1]))};
                if (c.radicand) {
                    require(sample.per_radian && sample.per_radian->radicand == c.radicand && sample.per_radian->direct == pin_derivative[u] &&
                        sample.per_radian->inverse_root == scale(multiply(gap, pin_derivative[v]), c.denominator * (branch == s::Branch::positive ? 1 : -1)),
                        "differentiating the independent 3D rod constraint produces the same two exact geometric derivative terms");
                } else require(!sample.per_radian, "zero longitudinal projection does not publish a derivative or divide by zero");
                require(sample.guide_fits, "all bounded current poses fit the deliberately broad test guide");
                if (cycle.closed()) require(numeric(c) >= numeric((*cycle.extrema)[0]) - 1e-12L && numeric(c) <= numeric((*cycle.extrema)[1]) + 1e-12L,
                    "small-profile numerical cross-check keeps current poses inside the separately certified global extrema");
                ++pose_cases;
            }
        }
    }
}

void discriminators_and_raw() {
    s::Profile p;
    const auto irrational = std::get<s::Sample>(s::sample(p, {3, 4, 5}, moving()));
    require(irrational.slider == s::Coordinate{9, 481, 5, s::Branch::positive} && !std::get<std::optional<F>>(s::rational_view(irrational.slider)) &&
        std::get<s::Order>(s::compare_to_grid(irrational.slider, 6)) == s::Order::greater && std::get<s::Order>(s::compare_to_grid(irrational.slider, 7)) == s::Order::less,
        "a nonsquare slider pose remains exactly between grid six and seven instead of rounding to either one");
    const auto reversal = std::get<s::Sample>(s::sample(p, {}, moving()));
    require(reversal.per_radian && reversal.per_radian->direct == F{} && reversal.per_radian->inverse_root == F{}, "normal zero slider speed at a stroke reversal is finite and differs from a missing derivative");
    p.rod_length = 2;
    require(std::get<s::Sample>(s::sample(p, {}, moving())).guide_fits && !std::get<s::Cycle>(s::inspect(p)).closed(), "one fitting rod pose cannot establish a complete revolution");
    p = {}; p.upper = 7;
    require(std::get<s::Sample>(s::sample(p, {0, 1, 1}, moving())).guide_fits && !std::get<s::Cycle>(s::inspect(p)).guide_fits, "one current guide fit cannot hide the full-stroke upper endstop");
    p = {}; p.rod_length = 10; p.guide_offset = 4; p.lower = 6; p.upper = 13;
    require(std::get<s::Sample>(s::sample(p, {0, 1, 1}, moving())).guide_fits && !std::get<s::Cycle>(s::inspect(p)).guide_fits, "nonsquare global extrema are compared exactly against finite guide bounds");
    p.lower = 5;
    require(std::get<s::Cycle>(s::inspect(p)).guide_fits, "a one-unit wider guide admits the same nonsquare complete stroke");
    p = {}; p.rod_length = p.radius;
    const auto singular = std::get<s::Sample>(s::sample(p, {0, 1, 1}, moving()));
    const auto limiting = std::get<s::Cycle>(s::inspect(p));
    require(!singular.per_radian && limiting.closed() && !limiting.regular() && limiting.extrema, "the singular limiting assembly stays explicit rather than becoming regular admission");
    p = {};
    const auto saved = std::get<s::Cycle>(s::inspect(p));
    p.origin = {}; p.branch = s::Branch::negative;
    require(saved.profile == s::Profile{} && irrational.profile == s::Profile{} && irrational.slider.radicand == 481, "owned observations survive caller mutation without storing a live slider mirror");
    const I low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    for (I bad : {low, high, I{0}, I{-1}, g::maximum_dimension + 1}) for (bool rod : {false, true}) {
        p = {}; (rod ? p.rod_length : p.radius) = bad;
        require(refused(s::sample(p, {}, moving()), s::Error::invalid_profile) && refused(s::inspect(p), s::Error::invalid_profile), "raw dimensions refuse before root products");
    }
    for (I bad : {low, high, -g::maximum_dimension - 1, g::maximum_dimension + 1}) {
        p = {}; p.guide_offset = bad;
        require(refused(s::sample(p, {}, moving()), s::Error::invalid_profile), "signed raw offsets are bounded before magnitude or products");
    }
    for (I bad : {low, high, -g::maximum_coordinate - 1, g::maximum_coordinate + 1}) for (std::size_t a = 0; a < 3; ++a) {
        p = {}; p.origin[a] = bad;
        require(refused(s::inspect(p), s::Error::invalid_profile), "raw origins refuse before axis geometry");
    }
    p = {}; p.lower = p.upper;
    require(refused(s::inspect(p), s::Error::invalid_profile), "a finite guide has ordered nonzero travel");
    p = {}; p.slider_id = p.crank_id;
    require(refused(s::sample(p, {}, moving()), s::Error::invalid_profile), "opaque part identities must differ");
    p = {}; p.crank_id = 0;
    require(refused(s::inspect(p), s::Error::invalid_profile), "missing identities refuse");
    p = {}; p.branch = static_cast<s::Branch>(-1);
    require(refused(s::sample(p, {}, moving()), s::Error::invalid_profile), "unknown assembly branches do not choose a default");
    p = {}; p.travel = p.shaft;
    require(refused(s::inspect(p), s::Error::invalid_axes), "travel and shaft axes must be independent");
    p = {}; p.shaft = static_cast<g::Axis>(-1);
    require(refused(s::sample(p, {}, moving()), s::Error::invalid_axes), "raw axis enums are validated before indexing");
    p = {};
    for (const auto d : {s::Direction{0, 0, 1}, {1, 1, 1}, {6, 8, 10}, {1, 0, 0}, {low, 0, 1}, {1, high, 1}, {1, 0, high}})
        require(refused(s::sample(p, d, moving()), s::Error::invalid_direction), "raw physical directions are bounded and primitive before squares/gcd");
    for (const F rate : {F{1, 0}, {0, -1}, {low, 1}, {high, 1}, {1, k::maximum_denominator + 1}, {257, 1}})
        require(refused(s::sample(p, {}, moving(rate)), s::Error::invalid_rate), "unsupported native rates refuse without coercion");
    require(refused(s::sample(p, {}, {g::MotionState::unpowered, {1, 0}}), s::Error::invalid_rate), "unpowered states still validate rate representations");
    require(refused(s::sample(p, {}, {static_cast<g::MotionState>(-1), {}}), s::Error::invalid_motion), "unknown native motion states refuse");
    require(refused(s::sample(p, {}, moving({0, 1})), s::Error::invalid_motion), "rotating zero is inconsistent");
    for (auto state : {g::MotionState::unpowered, g::MotionState::stopped, g::MotionState::stalled}) {
        require(refused(s::sample(p, {}, {state, {1, 1}}), s::Error::invalid_motion), "nonrotating states cannot carry speed");
        require(std::get<s::Sample>(s::sample(p, {}, {state, {0, high}})).crank == g::Motion{state, {}}, "zero normalization preserves each distinct native state");
    }
    for (const auto raw : {F{high, high}, F{low, I{1} << 62}, F{256, 1}, F{-256, 1}}) {
        const auto expected = raw.numerator == low ? F{-2, 1} : fraction(raw.numerator, raw.denominator);
        require(std::get<s::Sample>(s::sample(p, {}, moving(raw))).crank == moving(expected), "reducible raw extrema normalize before native bounds");
    }
    p.origin[0] = g::maximum_coordinate;
    require(refused(s::sample(p, {0, 1, 1}, moving()), s::Error::representation_limit) && refused(s::inspect(p), s::Error::representation_limit), "derived current and complete slider extrema retain grid bounds");
    p = {}; p.origin[1] = g::maximum_coordinate; p.guide_offset = 1;
    require(refused(s::sample(p, {}, moving()), s::Error::representation_limit) && refused(s::inspect(p), s::Error::representation_limit), "the fixed guide anchor cannot escape the native grid even if source motion is valid");
}

void consumers() {
    struct Case { std::string_view kit, source, finding; bool matched; int exit; };
    const std::array<Case, 21> cases{{
        {"standard", "slow", "Goal matched.", true, 0}, {"standard", "reverse", "Goal matched.", true, 0},
        {"mirrored", "slow", "Goal matched.", true, 0}, {"mirrored", "reverse", "Goal matched.", true, 0},
        {"short-rod", "slow", "rod cannot close", false, 0}, {"tight-guide", "slow", "escapes the finite guide", false, 0},
        {"low-guide", "slow", "escapes the finite guide", false, 0}, {"offset", "slow", "rod cannot close", false, 0},
        {"long-rod", "slow", "escapes the finite guide", false, 0}, {"singular", "slow", "zero longitudinal rod projection", false, 0},
        {"shifted", "slow", "escapes the finite guide", false, 0}, {"wrong-travel", "slow", "fixed +X guide line", false, 0},
        {"short-drive", "slow", "source unpowered", false, 0}, {"standard", "fast", "speed magnitude 1/2", false, 0},
        {"mirrored", "fast", "speed magnitude 1/2", false, 0}, {"standard", "stalled", "source stalled", false, 0},
        {"standard", "off", "source unpowered", false, 0}, {"mirrored", "stalled", "source stalled", false, 0},
        {"mirrored", "off", "source unpowered", false, 0}, {"near-edge", "slow", "representation_limit", false, 2},
        {"near-edge", "off", "representation_limit", false, 2},
    }};
    for (const auto& test : cases) {
        const std::array args{test.kit, test.source};
        std::ostringstream out, errors;
        require(s::workbench(args, out, errors) == test.exit, "the actual native consumer returns its declared trace/refusal status");
        require((out.str() + errors.str()).find(test.finding) != std::string::npos && (out.str().find("Goal matched.") != std::string::npos) == test.matched,
            "finite rod/guide geometry, explicit assembly side and real native power decide the original stroke goal");
        require(test.exit == 2 ? !errors.str().empty() : errors.str().empty(), "native representation refusal stays separate from a valid unfinished mechanism");
        if (test.matched) require(out.str().find("sqrt(481)") != std::string::npos, "working assemblies retain an actual nonsquare coordinate in their caller output");
        if (test.kit == "short-rod" || test.kit == "tight-guide") require(out.str().find("current guide fit yes") != std::string::npos, "current fitting observations cannot masquerade as a complete stroke certificate");
        ++caller_traces;
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{}, {"list"}, {"--help"}}) {
        std::ostringstream out, errors;
        require(s::workbench(args, out, errors) == 0 && errors.str().empty() && out.str().find("Nonsquare coordinates stay exact") != std::string::npos, "catalogue discloses exact geometry and physical-adoption limits");
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{"bogus", "slow"}, {"standard", "bogus"}, {"standard"}, {"standard", "slow", "extra"}, {"list", "extra"}}) {
        std::ostringstream out, errors;
        require(s::workbench(args, out, errors) == 2 && !errors.str().empty() && out.str().find("Goal matched.") == std::string::npos, "malformed argv refuses before a completed-stroke claim");
    }
    std::ostringstream failed, errors; failed.setstate(std::ios::badbit);
    const std::array<std::string_view, 2> args{"standard", "slow"};
    require(s::workbench(args, failed, errors) == 2, "an unwritable transcript is not a successful observation");
}
}  // namespace

int main() {
    exact_coordinates(); circle_rod_and_cycle(); discriminators_and_raw(); consumers();
    std::cout << "PASS " << assertions << " assertions; " << coordinate_cases << " exact coordinate comparisons; " << cycles << " cycle profiles; "
        << pose_cases << " reachable poses; " << unreachable << " unreachable observations; " << caller_traces << " consumer traces.\n";
}
