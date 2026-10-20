#include "factory/lift_transfer.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

namespace l = factory::lift;
namespace m = factory::mechanisms;
namespace c = factory::clearance;
namespace {
int checks{}, failures{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) { ++failures; std::cerr << "FAIL: " << message << '\n'; }
}
constexpr std::array<int, 12> tops{2, 2, 2, 3, 4, 5, 6, 6, 6, 5, 4, 3};

bool held(const l::Plan& plan, l::Stop reason, m::Tooth phase) {
    const auto* hold = std::get_if<l::Hold>(&plan);
    return hold && hold->reason == reason && hold->phase.tooth == phase;
}
void poses() {
    for (m::Tooth phase = 0; phase < tops.size(); ++phase) {
        l::Pose at;
        check(l::sample({}, {phase}, at) == l::Error::none, "Every default phase has a valid lift pose.");
        check(at.platform == c::Box{{1, tops[phase] - 1, -1}, {3, tops[phase], 1}},
              "Literal endpoint/dwell/travel positions preserve the complete box dimensions.");
    }
    for (m::Tooth dock = 1; dock <= 3; ++dock) for (m::Tooth travel = 1; travel <= 5; ++travel)
        for (m::Tooth work = 1; work <= 3; ++work) {
            l::Profile profile{{dock, travel, work}, {{-1, -10, -1}, {1, -9, 1}}, static_cast<c::Coordinate>(travel * 2)};
            const auto length = dock + travel * 2 + work;
            for (m::Tooth phase = 0; phase < length; ++phase) {
                const auto height = phase < dock ? 0 : phase < dock + travel ? phase - dock :
                    phase < dock + travel + work ? travel : length - phase;
                l::Pose at;
                check(l::sample(profile, {phase}, at) == l::Error::none &&
                      at.platform.minimum[1] == -10 + static_cast<c::Coordinate>(height * 2),
                      "Other timing profiles preserve exact two-grid-unit steps and both dwells.");
            }
        }
}

void all_observations() {
    for (m::Tooth phase = 0; phase < tops.size(); ++phase) for (unsigned flags = 0; flags < 16; ++flags) {
        const bool power = flags & 1U, loaded = flags & 2U, source = flags & 4U, receiver = flags & 8U;
        const l::Observation observed{power, loaded, source, receiver, {}};
        const auto plan = l::prepare({}, {phase}, observed);
        check(plan == l::prepare({}, {phase}, observed), "Identical observations propose identical results without consuming state.");
        if (!power) check(held(plan, l::Stop::unpowered, phase), "Power loss holds every well-formed phase without a handoff.");
        else if (tops[phase] == 2 && !loaded) {
            if (!source) check(held(plan, l::Stop::empty_source, phase), "An empty lower port never advances an empty lift.");
            else {
                const auto* transfer = std::get_if<l::Handoff>(&plan);
                check(transfer && transfer->direction == l::Direction::load && transfer->phase.tooth == phase,
                      "A lower pickup proposes a handoff at the unchanged phase.");
            }
        } else if (tops[phase] == 6 && loaded) {
            if (!receiver) check(held(plan, l::Stop::receiver_closed, phase), "A full or closed upper port retains its original load and phase.");
            else {
                const auto* transfer = std::get_if<l::Handoff>(&plan);
                check(transfer && transfer->direction == l::Direction::unload && transfer->phase.tooth == phase,
                      "An upper delivery proposes a handoff before any return step.");
            }
        } else if (phase >= 3 && phase <= 5 && !loaded) check(held(plan, l::Stop::missing_load, phase), "A missing mid-ascent load is visible.");
        else if (phase >= 9 && loaded) check(held(plan, l::Stop::load_on_return, phase), "An unexpected mid-return load does not silently travel down.");
        else {
            const auto* step = std::get_if<l::Step>(&plan);
            const auto next = (phase + 1) % tops.size();
            check(step && step->next.tooth == next && step->pose.platform.maximum[1] == tops[next],
                  "Only an admitted step proposes the next phase and its exact position.");
        }
    }
}

void swept_contacts() {
    const l::Profile fast{{1, 1, 1}, {{-1, 0, -1}, {1, 1, 1}}, 8};
    std::array<c::Obstacle, 2> beam{{{17, {{-1, 3, -1}, {1, 4, 1}}}, {5, {{-1, 3, -1}, {1, 4, 1}}}}};
    auto up = l::prepare(fast, {1}, {true, true, false, true, beam});
    const auto* collision = std::get_if<l::Hold>(&up);
    check(held(up, l::Stop::obstructed, 1) && collision->hit && collision->hit->obstacle == 5 &&
          collision->hit->time == c::Fraction{1, 4} && !collision->hit->initially_overlapping &&
          collision->pose.platform == fast.lower_box,
          "The full upward segment catches an intermediate beam with exact first contact and unchanged pose.");
    std::reverse(beam.begin(), beam.end());
    check(up == l::prepare(fast, {1}, {true, true, false, true, beam}), "Obstacle order cannot change an equal-time identity tie.");
    const auto down = l::prepare(fast, {3}, {true, false, false, true, beam});
    collision = std::get_if<l::Hold>(&down);
    check(held(down, l::Stop::obstructed, 3) && collision->hit && collision->hit->time == c::Fraction{1, 2},
          "The empty return uses the full downward segment as well.");
    check(std::holds_alternative<l::Handoff>(l::prepare(fast, {1}, {true, false, true, true, beam})),
          "An obstruction later on the path does not invent a current pickup obstruction.");
    const auto release = l::prepare(fast, {3}, {true, true, false, true, beam});
    check(std::holds_alternative<l::Handoff>(release) && std::get<l::Handoff>(release).direction == l::Direction::unload,
          "A valid current unloading can clear the load before a separately obstructed return.");
    const std::array<c::Obstacle, 1> grazing{{{2, {{1, 2, -1}, {2, 7, 1}}}}};
    check(std::holds_alternative<l::Step>(l::prepare(fast, {1}, {true, true, false, true, grazing})),
          "Side tangency follows the accepted positive-interior-overlap policy.");
    const std::array<c::Obstacle, 1> endpoint{{{2, {{-1, 9, -1}, {1, 10, 1}}}}};
    check(std::holds_alternative<l::Step>(l::prepare(fast, {1}, {true, true, false, true, endpoint})),
          "Contact only at the upper destination remains clear under the accepted query policy.");
    const std::array<c::Obstacle, 1> overlap{{{2, fast.lower_box}}};
    const auto initial = l::prepare(fast, {}, {true, false, true, true, overlap});
    collision = std::get_if<l::Hold>(&initial);
    check(held(initial, l::Stop::obstructed, 0) && collision->hit && collision->hit->initially_overlapping,
          "Initial penetration also blocks a stationary handoff.");
    check(held(l::prepare(fast, {}, {false, false, true, true, overlap}), l::Stop::unpowered, 0),
          "Power loss remains an unchanged hold even when contact is observed.");
    check(std::holds_alternative<l::Step>(l::prepare(fast, {1}, {true, true, false, true, {}})),
          "A fresh clear observation resumes the exact previously held phase.");
}

void refusals_and_bounds() {
    const auto maximum = std::numeric_limits<m::Tooth>::max();
    const auto grid = factory::mechanics::maximum_coordinate;
    std::vector<l::Profile> invalid{
        {{0, 4, 2}}, {{2, 0, 2}}, {{2, 4, 0}}, {{maximum, 1, 1}},
        {{2, 4, 2}, {}, 0}, {{2, 4, 2}, {}, -1},
        {{2, 4, 2}, {{1, 1, -1}, {3, 2, 1}}, 5},
        {{2, maximum, 2}}, {{2, 4, 2}, {}, 2 * grid + 1},
        {{2, 1, 2}, {{0, grid - 1, 0}, {1, grid, 1}}, 1},
        {{2, 1, 2}, {{-grid - 1, 0, 0}, {1, 1, 1}}, 1},
        {{2, 1, 2}, {{0, 0, 0}, {0, 1, 1}}, 1},
        {{2, 1, 2}, {{0, 0, 0}, {1, std::numeric_limits<c::Coordinate>::max(), 1}}, 1},
    };
    const l::Pose sentinel{{m::Stage::work, 9, 11}, {{-5, -4, -3}, {2, 3, 4}}};
    for (const auto& profile : invalid) {
        auto output = sentinel;
        check(l::sample(profile, {}, output) == l::Error::invalid_profile && output == sentinel,
              "Malformed, overflowing, off-grid and nonintegral profiles preserve every output field.");
        const auto plan = l::prepare(profile, {}, {false, false, false, false, {}});
        check(std::holds_alternative<l::Error>(plan) && std::get<l::Error>(plan) == l::Error::invalid_profile,
              "A stopped observation never bypasses profile validation.");
    }
    auto output = sentinel;
    check(l::sample({}, {12}, output) == l::Error::invalid_phase && output == sentinel, "An invalid phase preserves output.");
    const auto bad_phase = l::prepare({}, {maximum}, {false, false, false, false, {}});
    check(std::holds_alternative<l::Error>(bad_phase) && std::get<l::Error>(bad_phase) == l::Error::invalid_phase,
          "An unpowered invalid phase refuses instead of becoming a hold.");
    const l::Profile edge{{1, 1, 1}, {{-grid, -grid, -grid}, {grid, -grid + 1, grid}}, 2 * grid - 1};
    check(l::sample(edge, {2}, output) == l::Error::none && output.platform.maximum[1] == grid,
          "Both signs and the exact outer grid boundary remain valid without intermediate overflow.");
    const l::Profile long_dwell{{maximum - 3, 1, 1}};
    const auto wrap = l::prepare(long_dwell, {maximum - 1}, {true, false, false, true, {}});
    check(std::holds_alternative<l::Step>(wrap) && std::get<l::Step>(wrap).next.tooth == 0,
          "A maximum-length valid cycle wraps without increment overflow.");

    std::vector<std::vector<c::Obstacle>> invalid_obstacles{
        {{0, {{4, 0, 0}, {5, 1, 1}}}},
        {{1, {{4, 0, 0}, {5, 1, 1}}}, {1, {{5, 0, 0}, {6, 1, 1}}}},
        {{1, {{0, 0, 0}, {0, 1, 1}}}},
        {{1, {{-grid - 1, 0, 0}, {0, 1, 1}}}},
        {{1, {{1, 1, -1}, {3, 2, 1}}}, {0, {{5, 0, 0}, {6, 1, 1}}}},
    };
    std::vector<c::Obstacle> all;
    for (std::uint64_t id = 1; id <= factory::mechanics::maximum_parts; ++id) all.push_back({id, {{4, 0, 0}, {5, 1, 1}}});
    check(std::holds_alternative<l::Handoff>(l::prepare({}, {}, {true, false, true, true, all})),
          "The complete maximum-sized obstacle set remains admissible.");
    all.push_back({257, {{4, 0, 0}, {5, 1, 1}}});
    invalid_obstacles.push_back(all);
    for (const auto& obstacles : invalid_obstacles) for (const bool power : {false, true}) {
        const auto plan = l::prepare({}, {}, {power, false, false, false, obstacles});
        check(std::holds_alternative<l::Error>(plan) && std::get<l::Error>(plan) == l::Error::invalid_obstacles,
              "Every obstacle is validated before any power, empty-source or early-contact hold.");
    }
}

struct Run { int code; std::string output, errors; };
Run play(const std::string& commands) {
    std::istringstream input(commands);
    std::ostringstream output, errors;
    const int code = l::play(input, output, errors);
    return {code, output.str(), errors.str()};
}
std::string last_tags(const std::string& output) {
    const auto start = output.rfind("Tags pending:");
    return start == std::string::npos ? "" : output.substr(start, output.find('\n', start) - start);
}
void terminal() {
    const auto stalled = play("step 64\nstep 64\ninspect\nquit\n");
    check(stalled.code == 1 && stalled.errors.empty() && stalled.output.find("Held: receiver_closed") != std::string::npos &&
          stalled.output.find("Phase 6, work, platform top y=6") != std::string::npos &&
          last_tags(stalled.output) == "Tags pending: 8 9 10; carried: 7; delivered: none.",
          "Waiting for a later common-shaft cam never consumes the held tag or advances the blocked phase.");
    const auto recovered = play("step 64\npower off\ngate 6\nstep 64\npower on\nstep 64\n");
    check(recovered.code == 0 && recovered.errors.empty() && recovered.output.find("Held: unpowered") != std::string::npos &&
          recovered.output.find("Complete: tags 7 8 9 10 delivered; the empty carrier is back at the lower dock.") != std::string::npos &&
          last_tags(recovered.output) == "Tags pending: none; carried: none; delivered: 7 8 9 10.",
          "Re-keying and resuming the original loaded fixture completes all four identities without reset.");
    for (unsigned key = 0; key < 12; ++key) {
        const auto run = play("gate " + std::to_string(key) + "\nstep 64\n");
        check(run.code == ((key == 5 || key == 6) ? 0 : 1),
              "Exactly the two fixed-width windows containing upper arrival permit a full cycle.");
    }
    const auto not_returned = play("gate 6\nstep 50\n");
    check(not_returned.code == 1 && last_tags(not_returned.output) == "Tags pending: none; carried: none; delivered: 7 8 9 10." &&
          not_returned.output.find("Complete:") == std::string::npos,
          "Even all four deliveries do not finish before the final empty return.");
    const auto final_return = play("gate 6\nstep 50\nstep 6");
    check(final_return.code == 0 && final_return.errors.empty(), "The last return completes across separate lines without a final newline.");
    const auto partial = play("gate 6\nstep 42\n");
    check(partial.code == 1 && last_tags(partial.output) == "Tags pending: 10; carried: none; delivered: 7 8 9.",
          "A productive prefix preserves the remaining finite input and stays unfinished.");
    const auto refused = play("gate 12\ngate -1\ngate 18446744073709551616\nstep 0\nstep 65\nstep -1\nreset\n" +
        std::string(257, 'x') + "\ninspect\nquit\n");
    check(refused.code == 1 && !refused.errors.empty() &&
          last_tags(refused.output) == "Tags pending: 7 8 9 10; carried: none; delivered: none.",
          "Invalid syntax, integer overflow, oversized batches and reset requests preserve the original fixture.");
    std::ostringstream comparison;
    check(l::compare(comparison) == 0 && comparison.str().find("four descending chute pieces, no lift") != std::string::npos &&
          comparison.str().find("lift four levels") != std::string::npos,
          "The actual gravity query distinguishes lowering the cell from spending a lift to keep it raised.");
    std::istringstream bad_input;
    bad_input.setstate(std::ios::badbit);
    std::ostringstream output, errors;
    check(l::play(bad_input, output, errors) == 2, "An input failure cannot report completion.");
    std::istringstream empty;
    std::ostringstream bad_output;
    bad_output.setstate(std::ios::badbit);
    check(l::play(empty, bad_output, errors) == 2, "An output failure cannot report success.");
}
}  // namespace

int main() {
    poses();
    all_observations();
    swept_contacts();
    refusals_and_bounds();
    terminal();
    std::cout << "Lift transfer: " << checks << " checks, " << failures << " failures.\n";
    return failures ? 1 : 0;
}
