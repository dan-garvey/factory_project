#include "factory/indexed_clearance.hpp"

#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>

namespace f = factory::indexed_clearance;
namespace i = factory::indexing;
namespace c = factory::clearance;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
void advance(const f::Profile& profile, f::State& state) {
    auto proposal = f::plan_step(profile, state);
    check(std::holds_alternative<f::State>(proposal), "The expected fixture operation has an accepted proposal.");
    state = std::get<f::State>(std::move(proposal));
    check(f::valid(profile, state), "An accepted operation retains the complete finite-tag and pose invariant.");
}
unsigned finish(const f::Profile& profile, f::State& state) {
    unsigned count{};
    while (!f::finished(profile, state) && count < 64) { advance(profile, state); ++count; }
    check(f::finished(profile, state), "The finite batch completes with its empty holder home.");
    return count;
}
void all_complete_routes() {
    for (const auto height : {0, 1, 2}) {
        for (const auto route : {f::Route::short_path, f::Route::detour, f::Route::short_return}) {
            const f::Profile profile{height};
            auto state = f::start(route);
            const auto inputs = state.pending;
            check(f::valid(profile, state), "Every declared layout begins with exactly the three original tag records.");
            const bool should_complete = height == 2 || route == f::Route::detour;
            if (!should_complete) continue;
            const auto steps = finish(profile, state);
            const auto expected_steps = route == f::Route::detour ? 27 : route == f::Route::short_path ? 15 : 21;
            check(steps == static_cast<unsigned>(expected_steps), "The fixture actually executes every outbound, work, release and return operation.");
            check(state.pending.empty() && std::holds_alternative<i::Orientation>(state.holder) &&
                  std::get<i::Orientation>(state.holder) == i::Orientation{} && state.completed.size() == inputs.size(),
                  "Completion is a closed finite cycle, not an output-count shortcut.");
            for (std::size_t n = 0; n < state.completed.size(); ++n) {
                const auto& output = state.completed[n];
                i::Face exposed{};
                check(output.id == inputs[n].id && output.required == inputs[n].required && output.marked == inputs[n].required &&
                      i::world_face(output.orientation, i::Face::positive_x, exposed) == i::Error::none && exposed == i::Face::positive_z,
                      "Every released original tag retains its requirements and actual native X+ tool mark at the work station.");
            }
        }
    }
}

void blocked_short_and_recovery() {
    for (const auto height : {0, 1}) {
        const f::Profile profile{height};
        auto state = f::start(f::Route::short_path);
        advance(profile, state);  // Load original tag 7.
        const auto blocked = state;
        for (int repeat = 0; repeat < 4; ++repeat) {
            const auto result = f::plan_step(profile, state);
            const auto* refusal = std::get_if<f::Refusal>(&result);
            check(refusal && refusal->error == f::Error::blocked && refusal->obstacle == 7 && state == blocked,
                  "Repeated obstructed proposals retain the same tag, pose, face marks and outbound cursor.");
        }
        check(std::get<i::Job>(state.holder).id == 7 && std::get<i::Job>(state.holder).marked == 0 && state.pending.size() == 2,
              "Loading before a blockage does not replace the original work or refill the pending queue.");
        auto rerouted = f::plan_route(profile, state, f::Route::detour);
        check(std::holds_alternative<f::State>(rerouted), "The unchanged intake junction permits a real route correction.");
        auto expected = state; expected.route = f::Route::detour;
        state = std::get<f::State>(std::move(rerouted));
        check(state == expected, "A route correction changes only the route choice, with no reset or tag movement.");
        check(finish(profile, state) == 26, "The corrected run completes the remaining operations after its original load.");
    }
}

void stranded_return_and_closure() {
    const f::Profile profile{};
    auto state = f::start(f::Route::short_return);
    for (int step = 0; step < 6; ++step) advance(profile, state);
    check(state.phase == f::Phase::returning && state.completed.size() == 1 && state.completed.front().id == 7 &&
          state.pending.size() == 2 && !f::finished(profile, state), "One completed tag cannot hide a stranded empty holder.");
    const auto first_output = state.completed.front();
    const auto saved = state;
    const auto blocked = f::plan_step(profile, state);
    check(std::holds_alternative<f::Refusal>(blocked) && std::get<f::Refusal>(blocked).error == f::Error::blocked && state == saved,
          "The actual return arc hits the corner without moving the released work or cursor.");
    auto correction = f::plan_route(profile, state, f::Route::detour);
    check(std::holds_alternative<f::State>(correction), "The real work-station junction supports a safe longer return.");
    auto expected = state; expected.route = f::Route::detour;
    state = std::get<f::State>(std::move(correction));
    check(state == expected, "The same-state repair preserves the released tag, pending tags and empty holder orientation.");
    for (unsigned step = 0; state.completed.size() < 3 && step < 64; ++step) advance(profile, state);
    check(state.completed.size() == 3 && !f::finished(profile, state) && state.phase == f::Phase::returning,
          "Even three marked outputs remain unfinished until the last empty return closes the cycle.");
    check(finish(profile, state) == 3 && state.completed.front() == first_output,
          "The final three actual clear quarters finish without changing the original first output.");
}

void typed_in_memory_continuation() {
    const f::Profile profile{};
    auto state = f::start();
    for (int step = 0; step < 5; ++step) advance(profile, state);
    check(state.phase == f::Phase::release && std::get<i::Job>(state.holder).marked == 1,
          "The checkpoint is after marking and before release of original tag 7.");
    const auto checkpoint = state;
    auto resumed = checkpoint;
    unsigned tail{};
    while (!f::finished(profile, state) && tail++ < 64) {
        advance(profile, state); advance(profile, resumed);
        check(state == resumed, "A copied typed metadata cut continues identically without refilling work or replaying its stamp.");
    }
    check(f::finished(profile, state) && checkpoint.phase == f::Phase::release && checkpoint.completed.empty(),
          "Continuation leaves the original immutable cut intact; this is not file/Store evidence.");
}

void malformed_and_unsafe() {
    const f::Profile profile{};
    const auto original = f::start();
    auto refuse = [&](f::State bad) {
        const auto saved = bad;
        const auto transition = f::plan_step(profile, bad);
        check(!f::valid(profile, bad) && std::holds_alternative<f::Refusal>(transition) &&
              std::get<f::Refusal>(transition).error == f::Error::invalid_state && bad == saved,
              "Malformed metadata is refused without publishing a partial repair or new state.");
    };
    auto bad = original; bad.pending[1].id = bad.pending[0].id; refuse(bad);
    bad = original; bad.pending.pop_back(); refuse(bad);
    bad = original; bad.pending[0].required = 3; refuse(bad);
    bad = original; bad.pending[0].marked = 1; refuse(bad);
    bad = original; bad.phase = static_cast<f::Phase>(99); refuse(bad);
    bad = original; bad.route = static_cast<f::Route>(99); refuse(bad);
    bad = original; bad.quarter = 1000000; refuse(bad);
    bad = original; bad.holder = bad.pending.front(); refuse(bad);
    bad = original; std::get<i::Orientation>(bad.holder).positive_axes[0] = i::Face::negative_x; refuse(bad);
    check(!f::valid({3}, original) && !f::envelope({3}, {}) && !f::envelope({}, std::get<i::Orientation>(bad.holder)),
          "Invalid fixed layouts and reflected native orientations do not yield a body envelope.");
    auto moving = original; advance(profile, moving); advance(profile, moving);
    const auto moving_cut = moving;
    const auto route = f::plan_route(profile, moving, f::Route::short_path);
    check(std::holds_alternative<f::Refusal>(route) && std::get<f::Refusal>(route).error == f::Error::unsafe_route_change && moving == moving_cut,
          "A route cannot be rewritten halfway through a leg to retarget its cursor.");
    auto ready = original; for (int n = 0; n < 6; ++n) advance(profile, ready);
    bad = ready; bad.completed[0].marked = 0; refuse(bad);
    bad = ready; bad.completed[0].id = 8; refuse(bad);
    const c::Box literal_home{{2, -1, -1}, {3, 1, 1}};
    check(f::envelope({}, {}) == literal_home, "The collision envelope uses the same literal home geometry as the rotary component.");
    i::Orientation work;
    check(i::rotate({}, i::Axis::y, -1, work) == i::Error::none &&
          f::envelope({}, work) == c::Box{{-1, -1, 2}, {1, 1, 3}}, "The physical work envelope follows the actual native indexed pose.");
}

void actual_parser() {
    auto run = [&](f::Profile profile, f::Route route, const std::string& commands, int expected, const std::string& marker) {
        std::istringstream input(commands); std::ostringstream output, errors;
        const auto code = f::play(profile, route, input, output, errors);
        check(code == expected && output.str().find(marker) != std::string::npos,
              "The actual retained stdin parser reports the expected state or complete batch.");
        return output.str();
    };
    run({}, f::Route::detour, "run 64\nquit\n", 0, "Solved batch: 7 8 9; empty holder home.");
    run({2}, f::Route::short_path, "step\ninspect\nrun 64\n", 0, "Solved batch: 7 8 9; empty holder home.");
    const auto recovered = run({}, f::Route::short_return, "run 64\ninspect\nroute detour\nrun 64\nquit\n", 0, "Solved batch: 7 8 9; empty holder home.");
    check(recovered.find("Phase returning, quarter 0, route short_return. Pending: 8 9; held: empty; released: 7.") != std::string::npos &&
          recovered.find("Refused: blocked by corner 7") != std::string::npos, "The parser exposes the actual first-output/stranded-return counterexample before recovery.");
    run({}, f::Route::short_path, "run 64\nhelp\nroute detour\nrun 64\nquit\n", 0, "Solved batch: 7 8 9; empty holder home.");
    run({}, f::Route::short_return, "run 64\nreset\ninspect\nquit\n", 1, "Pending: 8 9; held: empty; released: 7.");
    run({}, f::Route::detour, "run 999\nroute teleport\ninspect\n", 1, "Pending: 7 8 9; held: empty; released:.");
    std::istringstream long_line(std::string(300, 'x')); std::ostringstream output, errors;
    check(f::play({}, f::Route::detour, long_line, output, errors) == 2 && errors.str().find("256") != std::string::npos,
          "An oversized command refuses under the caller's declared input bound.");
    std::istringstream input("run 64\n"); output.setstate(std::ios::badbit);
    check(f::play({}, f::Route::detour, input, output, errors) == 2, "An unusable output stream cannot claim a completed session.");
}
}  // namespace

int main() {
    try {
        all_complete_routes(); blocked_short_and_recovery(); stranded_return_and_closure();
        typed_in_memory_continuation(); malformed_and_unsafe(); actual_parser();
        std::cout << checks << " native indexed-cycle checks, 0 failures; metadata_tags=3, World_commands=0, engine_calls=0, physical_producers=0.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n'; return 1;
    }
}
