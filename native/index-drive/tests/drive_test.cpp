#include "factory/index_drive.hpp"

#include <array>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>

namespace d = factory::index_drive;
namespace m = factory::mechanisms;
namespace i = factory::indexing;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
const i::Orientation quarter{{i::Face::negative_z, i::Face::positive_y, i::Face::positive_x}};
d::Pose read(const d::Profile& profile, const d::State& state) {
    d::Pose pose;
    check(d::sample(profile, state, pose) == d::Error::none, "The expected bounded drive pose is valid.");
    return pose;
}

void literal_cycle() {
    const d::Profile profile;
    const std::array<m::Tooth, 10> carrier{0, 0, 0, 1, 2, 3, 3, 3, 2, 1};
    const std::array<m::Stage, 10> stages{m::Stage::dock, m::Stage::dock, m::Stage::outward, m::Stage::outward, m::Stage::outward,
                                         m::Stage::work, m::Stage::work, m::Stage::homeward, m::Stage::homeward, m::Stage::homeward};
    for (m::Tooth tooth = 0; tooth < carrier.size(); ++tooth) {
        const d::State state{{tooth}, {}};
        const auto pose = read(profile, state);
        check(pose.carrier == m::Pose{stages[tooth], carrier[tooth], 3}, "Every literal carrier boundary retains the original cycle's exact fraction.");
        const bool turning = tooth >= 2 && tooth <= 4;
        const auto from = tooth >= 5 ? quarter : i::Orientation{};
        const auto to = tooth >= 2 ? quarter : i::Orientation{};
        const d::AngularPose expected{from, to, turning ? tooth - 2 : 0, turning ? 3U : 1U, turning};
        check(pose.wheel == expected && pose.work_window == (tooth == 5 || tooth == 6),
              "The wheel turns only outward, holds the next stop at work/return and exposes only the far-dwell window.");
    }
    d::State last{{9}, {}};
    const auto before = read(profile, last);
    check(d::advance(profile, last, {}) == d::Error::none && last == d::State{{0}, quarter}, "Wrap rebases to the indexed stop exactly once.");
    const auto after = read(profile, last);
    check(before.wheel.from == after.wheel.from && !after.wheel.turning, "The reference change during wrap adds no physical turn.");
}

void obstruction_truth_table() {
    const d::Profile profile;
    const std::array<bool, 10> carrier_moves{false, false, true, true, true, false, false, true, true, true};
    const std::array<bool, 10> wheel_moves{false, false, true, true, true, false, false, false, false, false};
    for (m::Tooth tooth = 0; tooth < 10; ++tooth) {
        const d::State original{{tooth}, {}};
        auto paused = original;
        check(d::advance(profile, paused, {false, true, true}) == d::Error::none && paused == original,
              "Power loss holds the exact reference and phase, even under obstruction observations.");
        for (const bool wheel : {false, true}) {
            auto state = original;
            const auto result = d::advance(profile, state, {true, !wheel, wheel});
            const bool blocked = wheel ? wheel_moves[tooth] : carrier_moves[tooth];
            check(result == (blocked ? d::Error::obstructed : d::Error::none), "Literal displacement facts select the correct isolated obstruction domain.");
            if (blocked) check(state == original, "An obstructed interval preserves every drive field.");
            else {
                check(state.phase.tooth == (tooth + 1) % 10 && state.reference == (tooth == 9 ? quarter : i::Orientation{}),
                      "A permitted carrier interval advances once without an extra index.");
                if (wheel && tooth >= 7) {
                    const auto a = read(profile, original), b = read(profile, state);
                    check(a.wheel.from == b.wheel.from && a.wheel.to == b.wheel.to, "Wheel obstruction cannot reverse or move the held wheel during carrier overrun.");
                }
            }
        }
    }
}

void partial_hold_and_overrun() {
    const d::Profile profile;
    d::State state{{3}, {}};
    const auto partial = read(profile, state);
    for (int retry = 0; retry < 5; ++retry) {
        check(d::advance(profile, state, {true, false, true}) == d::Error::obstructed &&
              read(profile, state) == partial && state.phase.tooth == 3, "A wheel jam retains the original one-third quarter-turn without snapping to a stop.");
    }
    check(d::advance(profile, state, {}) == d::Error::none && d::advance(profile, state, {}) == d::Error::none &&
          state.phase.tooth == 5 && read(profile, state).wheel.from == quarter, "Clearance resumes the same partial index to the next stop.");
    for (int n = 0; n < 2; ++n) check(d::advance(profile, state, {}) == d::Error::none, "Far dwell advances to the carrier return.");
    check(state.phase.tooth == 7, "The overrun starts from full carrier displacement.");
    for (int n = 0; n < 3; ++n) check(d::advance(profile, state, {true, false, true}) == d::Error::none, "A blocked wheel remains isolated while the carrier returns.");
    check(state == d::State{{0}, quarter}, "Return ends docked with the same held quarter stop.");
    for (int n = 0; n < 2; ++n) check(d::advance(profile, state, {true, false, true}) == d::Error::none, "Dock dwell reaches the next motion boundary without moving the wheel.");
    const auto stopped = state;
    check(d::advance(profile, state, {true, false, true}) == d::Error::obstructed && state == stopped,
          "The same wheel obstruction applies again before the next actual indexing interval.");
}

void signed_axes_and_continuation() {
    const i::Orientation initial{{i::Face::positive_y, i::Face::negative_x, i::Face::positive_z}};
    for (const auto axis : {i::Axis::x, i::Axis::y, i::Axis::z}) for (const int direction : {-1, 1}) {
        const d::Profile profile{{1, 2, 1}, axis, direction};
        d::State state{{0}, initial};
        auto expected = initial;
        for (int revolution = 0; revolution < 4; ++revolution) {
            i::Orientation next;
            check(i::rotate(expected, axis, direction, next) == i::Error::none, "The existing native orientation kernel supplies the signed stop.");
            expected = next;
            for (int step = 0; step < 6; ++step) check(d::advance(profile, state, {}) == d::Error::none, "The complete short carrier profile advances through each interval.");
            check(state == d::State{{0}, expected}, "One carrier revolution advances exactly one native world-axis quarter from an arbitrary initial frame.");
        }
        check(state == d::State{{0}, initial}, "Four carrier revolutions close both phase and reference on every signed axis.");
    }
    const d::Profile profile;
    d::State uninterrupted{{3}, initial};
    const auto checkpoint = uninterrupted;
    auto resumed = checkpoint;
    for (int step = 0; step < 53; ++step) {
        const d::Observation observation{step >= 2, step == 12, step >= 2 && step < 7};
        const auto a = d::advance(profile, uninterrupted, observation), b = d::advance(profile, resumed, observation);
        check(a == b && uninterrupted == resumed && read(profile, uninterrupted) == read(profile, resumed),
              "A copied partial typed phase continues identically through power loss, jams and overrun, without a new clock or reference reset.");
    }
    check(checkpoint.phase.tooth == 3 && checkpoint.reference == initial, "The original in-memory cut stays unchanged; no Store result is claimed.");
}

void invalid_inputs_and_boundaries() {
    auto refuse = [&](d::Profile profile, d::State state, d::Error expected) {
        d::Pose output; output.carrier.numerator = 123; output.work_window = true;
        const auto sentinel = output;
        const auto original = state;
        check(d::sample(profile, state, output) == expected && output == sentinel, "A malformed read preserves every output field.");
        check(d::advance(profile, state, {false, true, true}) == expected && state == original &&
              d::advance(profile, state, {}) == expected && state == original, "Malformed state/profile is refused even while unpowered, without a partial advance.");
    };
    d::Profile profile;
    profile.carrier.dock = 0; refuse(profile, {}, d::Error::invalid_profile);
    profile = {}; profile.carrier.travel = 0; refuse(profile, {}, d::Error::invalid_profile);
    profile = {}; profile.carrier.work = 0; refuse(profile, {}, d::Error::invalid_profile);
    profile = {}; profile.carrier.dock = std::numeric_limits<m::Tooth>::max(); refuse(profile, {}, d::Error::invalid_profile);
    profile = {}; profile.axis = static_cast<i::Axis>(255); refuse(profile, {}, d::Error::invalid_profile);
    profile = {}; profile.direction = 0; refuse(profile, {}, d::Error::invalid_profile);
    profile = {}; profile.direction = 2; refuse(profile, {}, d::Error::invalid_profile);
    refuse({}, {{10}, {}}, d::Error::invalid_state);
    refuse({}, {{std::numeric_limits<m::Tooth>::max()}, {}}, d::Error::invalid_state);
    d::State reflection; reflection.reference.positive_axes[0] = i::Face::negative_x;
    refuse({}, reflection, d::Error::invalid_state);
    constexpr auto limit = std::numeric_limits<m::Tooth>::max();
    profile = {{1, 1, limit - 3}, i::Axis::y, 1};
    d::State last{{limit - 1}, {}};
    check(read(profile, last).carrier.stage == m::Stage::homeward, "The maximum representable cycle has an exact final return interval.");
    const auto original = last;
    check(d::advance(profile, last, {true, true, false}) == d::Error::obstructed && last == original,
          "Even the uint64 boundary retains the final interval under carrier blockage.");
    check(d::advance(profile, last, {true, false, true}) == d::Error::none && last == d::State{{0}, quarter},
          "Maximum-length wrap avoids overflow and does not add a wheel turn during isolated return.");
}

void actual_parser() {
    const std::string finish = "tick 5\nstamp\nstamp\ntick 10\nstamp\ntick 10\nstamp\ntick 10\nstamp\nrelease\ninspect\ntick 5\nrelease\n";
    auto run = [&](int direction, const std::string& commands, int expected, const std::string& marker) {
        std::istringstream input(commands); std::ostringstream output, errors;
        const auto result = d::play(direction, input, output, errors);
        check(result == expected && output.str().find(marker) != std::string::npos, "The real retained stdin caller reports the expected drive outcome.");
        return output.str();
    };
    for (const int direction : {-1, 1}) {
        const auto output = run(direction, finish, 0, "Solved: original tag 7 has all four marks; carrier docked and wheel home.");
        check(output.find("Refused: already_marked") != std::string::npos && output.find("Refused: dock the carrier") != std::string::npos,
              "The caller preserves duplicate-mark and complete-wheel/undocked-carrier refusals before the actual finish.");
    }
    const std::string recovery = "tick 3\nblock wheel\ntick 4\npower off\ntick 4\ninspect\nstamp\nreset\npower on\nblock none\ntick 2\nstamp\n"
                                 "tick 10\nstamp\ntick 10\nstamp\ntick 10\nstamp\ntick 5\nrelease\n";
    const auto resumed = run(1, recovery, 0, "Solved: original tag 7 has all four marks; carrier docked and wheel home.");
    check(resumed.find("Phase 3: carrier outward at 1/3; wheel turn 1/3") != std::string::npos &&
          resumed.find("Drive held: obstructed") != std::string::npos && resumed.find("Refused: stamping needs powered far dwell") != std::string::npos,
          "Power pause and a partial angular jam recover in the same process with the original tag.");
    run(1, "tick 5\nstamp\ntick 2\nblock wheel\ntick 3\ninspect\ntick 2\ntick 1\nquit\n", 1,
        "Phase 2: carrier outward at 0/3; wheel turn 0/3");
    run(1, "tick 7\nblock carrier\ntick 2\nquit\n", 1, "Phase 7: carrier homeward at 3/3; wheel turn 0/1");
    run(1, "tick 3\nstamp\nquit\n", 1, "Refused: stamping needs powered far dwell");
    run(1, "tick 5\nstamp\ntick 10\nstamp\ntick 10\nstamp\ntick 10\nstamp\nrelease\nquit\n", 1,
        "Refused: dock the carrier before releasing.");
    run(1, "tick 999\nreset\ninspect\nquit\n", 1, "Phase 0: carrier dock at 0/3");
    std::istringstream empty; std::ostringstream output, errors;
    check(d::play(0, empty, output, errors) == 2, "Invalid startup direction is refused.");
    std::istringstream long_line(std::string(300, 'x'));
    check(d::play(1, long_line, output, errors) == 2, "The caller refuses oversized input under its fixed line bound.");
    output.setstate(std::ios::badbit);
    check(d::play(1, empty, output, errors) == 2, "Output failure cannot report successful release.");
}
}  // namespace

int main() {
    try {
        literal_cycle(); obstruction_truth_table(); partial_hold_and_overrun(); signed_axes_and_continuation();
        invalid_inputs_and_boundaries(); actual_parser();
        std::cout << checks << " native index-drive checks, 0 failures; World_commands=0, engine_calls=0, physical_producers=0.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n'; return 1;
    }
}
