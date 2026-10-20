#include "factory/docked_ports.hpp"
#include "factory/cycle.hpp"

#include <array>
#include <iostream>
#include <limits>
#include <string>
#include <string_view>

namespace p = factory::docked_ports;
namespace g = factory::mechanics;
namespace m = factory::mechanisms;
namespace {
int checks{};
int failures{};

void check(bool condition, std::string_view message) {
    ++checks;
    if (!condition) { ++failures; std::cerr << "FAIL: " << message << '\n'; }
}

p::Port sender() { return {{{"carrier", 4}, 2}, {7, -3, 11}, g::Axis::x, 1, p::Mode::fixed, 0, true}; }
p::Port receiver() { return {{{"receiver", 9}, 5}, {7, -3, 11}, g::Axis::x, -1, p::Mode::fixed, 0, true}; }
constexpr p::Observation ready{true, true, true, 2};

void expect_hold(const p::Port& a, const p::Port& b, p::Observation observation, p::Stop stop) {
    check(p::prepare(a, b, observation) == p::Plan{p::Hold{stop, a.reference, b.reference}},
          "A refused stroke names its reason and retains both original port references.");
}

void geometry() {
    auto a = sender();
    auto b = receiver();
    check(p::prepare(a, b, ready) == p::Plan{p::Stroke{a.reference, b.reference, 2, std::nullopt}},
          "Two fixed, aligned, opposing ports propose a stroke without inventing a deadline.");
    for (const auto axis : {g::Axis::x, g::Axis::y, g::Axis::z}) {
        for (const int sign : {-1, 1}) {
            a.normal_axis = b.normal_axis = axis;
            a.normal_sign = sign;
            b.normal_sign = -sign;
            check(std::holds_alternative<p::Stroke>(p::prepare(a, b, ready)),
                  "Every opposed axis/sign pair qualifies at the same anchor.");
            b.normal_sign = sign;
            expect_hold(a, b, ready, p::Stop::wrong_facing);
            b.normal_sign = -sign;
            b.normal_axis = static_cast<g::Axis>((static_cast<int>(axis) + 1) % 3);
            expect_hold(a, b, ready, p::Stop::wrong_facing);
        }
    }
    a = sender(); b = receiver();
    for (std::size_t axis = 0; axis < 3; ++axis) {
        ++b.anchor[axis];
        expect_hold(a, b, ready, p::Stop::misaligned);
        --b.anchor[axis];
    }
    for (const auto position : {g::Point{-g::maximum_coordinate, 0, g::maximum_coordinate},
                                g::Point{0, 0, 0}, g::Point{91, -38, 217}}) {
        a.anchor = b.anchor = position;
        check(std::holds_alternative<p::Stroke>(p::prepare(a, b, ready)),
              "Common translation and inclusive grid boundaries preserve coupling.");
    }
    for (const auto coordinate : {g::maximum_coordinate + 1, -g::maximum_coordinate - 1,
                                  std::numeric_limits<g::Integer>::min(), std::numeric_limits<g::Integer>::max()}) {
        for (std::size_t axis = 0; axis < 3; ++axis) {
            a = sender(); b = receiver();
            b.anchor[axis] = coordinate;
            check(p::prepare(a, b, {false, true, true, 2}) == p::Plan{p::Error::invalid_geometry},
                  "Malformed receiver geometry is rejected even when power is absent.");
            a.anchor[axis] = coordinate;
            b = receiver();
            check(p::prepare(a, b, ready) == p::Plan{p::Error::invalid_geometry},
                  "Extreme sender coordinates are rejected without distance arithmetic.");
        }
    }
}

void windows_and_waits() {
    auto a = sender();
    auto b = receiver();
    expect_hold(a, b, {false, true, true, 2}, p::Stop::unpowered);
    expect_hold(a, b, {true, false, true, 2}, p::Stop::empty_source);
    expect_hold(a, b, {true, true, false, 2}, p::Stop::full_receiver);
    a.gate_open = false;
    expect_hold(a, b, ready, p::Stop::closed_gate);
    a.gate_open = true; b.gate_open = false;
    expect_hold(a, b, ready, p::Stop::closed_gate);
    b.gate_open = true;
    a.mode = p::Mode::dwell; a.remaining = 3;
    check(p::prepare(a, b, ready) == p::Plan{p::Stroke{a.reference, b.reference, 2, 3}},
          "The finite sender window remains visible in the proposal.");
    b.mode = p::Mode::dwell; b.remaining = 2;
    check(p::prepare(a, b, ready) == p::Plan{p::Stroke{a.reference, b.reference, 2, 2}},
          "The shorter endpoint window governs, and exact-length strokes fit.");
    a.remaining = 1;
    expect_hold(a, b, ready, p::Stop::short_dwell);
    a = sender(); b.remaining = 1;
    expect_hold(a, b, ready, p::Stop::short_dwell);
    b.mode = p::Mode::moving; b.remaining = 0;
    expect_hold(a, b, ready, p::Stop::moving);
    a.mode = p::Mode::moving; b = receiver();
    expect_hold(a, b, ready, p::Stop::moving);
    constexpr auto maximum = std::numeric_limits<p::Tick>::max();
    a = sender(); b = receiver();
    check(std::holds_alternative<p::Stroke>(p::prepare(a, b, {true, true, true, maximum})),
          "A fixed-port query does not overflow when asked about a maximum-length stroke.");
    a.mode = b.mode = p::Mode::dwell; a.remaining = b.remaining = maximum;
    check(p::prepare(a, b, {true, true, true, maximum}) ==
              p::Plan{p::Stroke{a.reference, b.reference, maximum, maximum}},
          "Maximum finite durations compare exactly without adding absolute deadlines.");
}

void malformed_inputs() {
    const auto a = sender();
    const auto b = receiver();
    check(p::prepare(a, b, {true, true, true, 0}) == p::Plan{p::Error::invalid_request},
          "A zero-duration request cannot bypass the finite-stroke contract.");
    for (const bool alter_sender : {false, true}) {
        auto left = a; auto right = b;
        auto& bad = alter_sender ? left : right;
        bad.reference.entity.id.clear();
        check(p::prepare(left, right, ready) == p::Plan{p::Error::invalid_reference}, "An empty entity identity is invalid.");
        bad = alter_sender ? a : b;
        for (const auto generation : {std::int64_t{0}, std::int64_t{-1}, std::numeric_limits<std::int64_t>::min()}) {
            bad.reference.entity.generation = generation;
            check(p::prepare(left, right, ready) == p::Plan{p::Error::invalid_reference}, "A nonpositive generation is invalid.");
        }
        bad = alter_sender ? a : b;
        for (const int sign : {0, 2, -2, std::numeric_limits<int>::min()}) {
            bad.normal_sign = sign;
            check(p::prepare(left, right, ready) == p::Plan{p::Error::invalid_geometry}, "Only a signed unit normal is allowed.");
        }
        bad = alter_sender ? a : b;
        for (const auto axis : {static_cast<g::Axis>(-1), static_cast<g::Axis>(3)}) {
            bad.normal_axis = axis;
            check(p::prepare(left, right, ready) == p::Plan{p::Error::invalid_geometry}, "Unknown normal axes are rejected.");
        }
        bad = alter_sender ? a : b;
        bad.mode = static_cast<p::Mode>(255);
        check(p::prepare(left, right, ready) == p::Plan{p::Error::invalid_phase}, "Unknown phase modes are rejected.");
        for (const auto mode : {p::Mode::fixed, p::Mode::moving, p::Mode::dwell}) {
            bad.mode = mode;
            bad.remaining = mode == p::Mode::dwell ? 0 : 1;
            check(p::prepare(left, right, {false, false, false, 2}) == p::Plan{p::Error::invalid_phase},
                  "Noncanonical mode/window pairs fail before operational waits.");
        }
    }
    auto same = b;
    same.reference = a.reference;
    check(p::prepare(a, same, ready) == p::Plan{p::Error::same_port}, "A port cannot couple to its own alias.");
    ++same.reference.port;
    check(std::holds_alternative<p::Stroke>(p::prepare(a, same, ready)),
          "Different ports on one current entity remain distinct endpoints.");
    ++same.reference.entity.generation;
    check(p::prepare(a, same, ready) == p::Plan{p::Error::identity_conflict},
          "Two generations of one entity cannot be presented as simultaneous endpoints.");
    auto extreme = a;
    extreme.reference.entity.generation = std::numeric_limits<std::int64_t>::max();
    extreme.reference.port = std::numeric_limits<std::uint32_t>::max();
    check(p::prepare(extreme, b, ready) == p::Plan{p::Stroke{extreme.reference, b.reference, 2, std::nullopt}},
          "Maximum canonical identity fields are retained without arithmetic or truncation.");
}

void exhaustive_eligibility() {
    // Endpoint profiles are independently enumerated, including finite windows
    // on either side. The oracle is the conjunction of physical prerequisites,
    // independent of the implementation's ordering of diagnostic reasons.
    struct Profile { p::Mode mode; p::Tick window; bool stopped; bool enough; };
    constexpr std::array<Profile, 5> profiles{{
        {p::Mode::fixed, 0, true, true}, {p::Mode::moving, 0, false, false},
        {p::Mode::dwell, 1, true, false}, {p::Mode::dwell, 2, true, true},
        {p::Mode::dwell, 3, true, true},
    }};
    for (const auto left : profiles) for (const auto right : profiles) {
        for (unsigned flags = 0; flags < 32; ++flags) for (unsigned geometry = 0; geometry < 4; ++geometry) {
            auto a = sender(); auto b = receiver();
            a.mode = left.mode; a.remaining = left.window;
            b.mode = right.mode; b.remaining = right.window;
            const p::Observation observation{(flags & 1) != 0, (flags & 2) != 0, (flags & 4) != 0, 2};
            a.gate_open = (flags & 8) != 0; b.gate_open = (flags & 16) != 0;
            if (geometry & 1) ++b.anchor[1];
            if (geometry & 2) b.normal_sign = 1;
            const bool eligible = flags == 31 && geometry == 0 && left.stopped && right.stopped && left.enough && right.enough;
            const auto plan = p::prepare(a, b, observation);
            check(std::holds_alternative<p::Stroke>(plan) == eligible && !std::holds_alternative<p::Error>(plan),
                  "The full valid-input eligibility matrix agrees with independent prerequisites.");
        }
    }
}

void ownership_and_carriage() {
    auto a = sender(); auto b = receiver();
    a.reference.entity.id = std::string(200, 'a');
    b.reference.entity.id = std::string(200, 'b');
    const auto original_a = a.reference;
    const auto original_b = b.reference;
    const auto proposal = p::prepare(a, b, ready);
    const auto refusal = p::prepare(a, b, {true, true, false, 2});
    for (int i = 0; i < 8; ++i) check(p::prepare(a, b, ready) == proposal, "Repeated queries do not reserve or consume anything.");
    a.reference.entity.id.assign(200, 'x'); ++a.reference.entity.generation;
    b.reference.entity.id.clear();
    check(proposal == p::Plan{p::Stroke{original_a, original_b, 2, std::nullopt}} &&
          refusal == p::Plan{p::Hold{p::Stop::full_receiver, original_a, original_b}},
          "Proposals and holds own their references even after caller storage changes; neither is an admission receipt.");

    const m::Slide slide{3, 2, 2};
    a = sender(); b = receiver();
    for (m::Tooth tooth = 0; tooth < 9; ++tooth) {
        const m::Phase phase{tooth};
        m::Pose pose;
        check(m::sample(slide, phase, pose) == m::Error::none, "The caller samples an existing valid carriage phase.");
        a.mode = pose.stage == m::Stage::dock ? p::Mode::dwell : p::Mode::moving;
        a.remaining = a.mode == p::Mode::dwell ? slide.dock - tooth : 0;
        // All anchors deliberately coincide: position alone cannot authorize a
        // stroke while the next carriage interval is moving or is at work.
        const auto plan = p::prepare(a, b, ready);
        check(std::holds_alternative<p::Stroke>(plan) == (tooth < 2) && phase == m::Phase{tooth},
              "Only a sufficient dock interval qualifies, and planning never advances the carriage.");
        if (tooth == 2) expect_hold(a, b, ready, p::Stop::short_dwell);
        if (tooth == 3) expect_hold(a, b, ready, p::Stop::moving);
    }
}
}  // namespace

int main() {
    geometry();
    windows_and_waits();
    malformed_inputs();
    exhaustive_eligibility();
    ownership_and_carriage();
    std::cout << checks << " checks, " << failures << " failures\n";
    return failures ? 1 : 0;
}
