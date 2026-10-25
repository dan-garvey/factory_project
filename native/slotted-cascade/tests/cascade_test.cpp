#include "factory/slotted_cascade.hpp"
#include "factory/slotted_cascade_workbench.hpp"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace h = factory::slotted_cascade;
namespace b = factory::slotted_bank;
namespace s = factory::slotted_link;
namespace w = factory::slotted_workcell;
namespace r = factory::slotted_clearance;
namespace p = factory::slotted_pairs;
namespace c = factory::clearance;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
std::size_t assertions{}, model_cases{};
void require(bool value, const char* message) {
    ++assertions;
    if (!value) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
g::Rate fraction(I n, I d) { const I divisor = std::gcd(n, d); return {n / divisor, d / divisor}; }
c::Fraction time(I n, I d) { const auto f = fraction(n, d); return {f.numerator, f.denominator}; }
c::Box box(I x, I y) { return {{x, y, 0}, {x + 1, y + 1, 1}}; }
const std::array<b::Link, 2> chain{{{19, {0, 6, 2, 1}}, {3, {0, 6, 1, 3}}}};
const b::State initial{0, {{3, 0}, {19, 0}}};
const r::Rig rig{g::Axis::x, box(0, -3), {{19, box(0, 0)}, {3, box(0, 3)}}};
bool refused(const h::Plan& plan, h::Error error) {
    const auto* value = std::get_if<h::Refusal>(&plan);
    return value && value->reason == error;
}

void controls() {
    const auto step = std::get<h::Advance>(h::prepare(chain, initial, rig, {{5, true}, {}}, {}));
    require(step.next == b::State{5, {{3, 1}, {19, 4}}}, "series follower receives the previous original follower instead of the base pin");
    require(step.traces[0] == h::Trace{3, s::Contact{s::Side::positive, {4, 5}}, s::Span{{4, 5}, {1, 1}}, {}},
        "downstream cumulative take-up keeps original commanded time and canonical identity");
    const auto parallel = std::get<b::Advance>(b::prepare(chain, initial, {5, true}));
    require(parallel.next != step.next && parallel.next.followers[0].position == 2,
        "parallel bank is a discriminating wrong control for a cascaded mechanism");
    const auto reversed = std::get<h::Advance>(h::prepare(chain, step.next, rig, {{-3, true}, {}}, {}));
    require(reversed.next == b::State{-2, {{3, 1}, {19, 0}}} && reversed.limit == b::Limit{19, {s::Side::negative, {7, 8}}},
        "upstream lower stop clips all original downstream history to one prefix");
    auto short_chain = chain;
    short_chain[0].slot.upper = 3;
    const auto clipped = std::get<h::Advance>(h::prepare(short_chain, initial, rig, {{8, true}, {}}, {}));
    require(clipped.next == b::State{4, {{3, 0}, {19, 3}}} && clipped.limit == b::Limit{19, {s::Side::positive, {1, 2}}},
        "upstream guide can stop before a downstream tool starts");
    require(clipped.traces[0] == h::Trace{3, s::Contact{s::Side::positive, {1, 2}}, {}, {}},
        "complete take-up only at the clipped endpoint is not downstream motion");
    require(clipped.traces[1].motion == s::Span{{1, 8}, {1, 2}}, "earlier moving stage remains in original full-stroke time");
    const auto hold = std::get<b::Hold>(h::prepare(short_chain, clipped.next, rig, {{8, true}, {}}, {}));
    require(hold.reason == b::Stop::limit && hold.state == clipped.next && hold.limit->id == 19, "binding upstream stop holds the entire cascade");
    const std::array<c::Obstacle, 1> frame{{{29, box(2, 3)}}};
    auto state = initial;
    auto obstacles = frame;
    const auto blocked = std::get<w::Blocked>(h::prepare(chain, state, rig, {{8, true}, obstacles}, {}));
    require(blocked.state == initial && std::get<w::StationaryContact>(blocked.contact) == w::StationaryContact{3, {29, {5, 8}, false}},
        "stationary contact includes all preceding delays and publishes no partial bank");
    state.followers.clear();
    obstacles[0].id = 1;
    require(blocked.state == initial && std::get<w::StationaryContact>(blocked.contact).hit.obstacle == 29, "blocked state and witness own their storage");
    const auto paused = std::get<b::Hold>(h::prepare(chain, step.next, rig, {{0, false}, {}}, {}));
    require(paused.state == step.next && paused.reason == b::Stop::unpowered, "pause retains one bank without a pending stroke");
    const std::array<b::Link, 3> three{{{19, {0, 6, 1, 1}}, {3, {0, 6, 1, 0}}, {47, {0, 6, 1, 1}}}};
    const b::State all{0, {{3, 0}, {19, 0}, {47, 0}}};
    auto shapes = rig;
    shapes.followers.push_back({47, box(0, 6)});
    const auto three_step = std::get<h::Advance>(h::prepare(three, all, shapes, {{3, true}, {}}, {}));
    require(three_step.next == b::State{3, {{3, 2}, {19, 2}, {47, 1}}}, "three stages retain arbitrary chain order and canonical live identities");
    require(three_step.traces[0].drive_engagement == s::Contact{s::Side::positive, {1, 3}},
        "local second slot already touches at zero but its cumulative drive engagement is later");
    auto tied = chain;
    tied[0].slot.upper = 3;
    tied[1].slot.upper = 0;  // Invalid raw profile must not be used as a limit.
    require(refused(h::prepare(tied, initial, rig, {{8, true}, {}}, {}), h::Error::link_refused), "invalid later profile never appears as a successful stop");
    tied[1].slot = {0, 2, 1, 1};
    const auto tie = std::get<h::Advance>(h::prepare(tied, initial, rig, {{8, true}, {}}, {}));
    require(tie.next == b::State{4, {{3, 2}, {19, 3}}} && tie.limit->id == 3,
        "equal binding times choose canonical identity rather than earlier chain rank");
}

void validation() {
    const b::State locally_impossible{0, {{3, -1}, {19, 1}}};
    std::array<b::Link, 2> local_chain{{{19, {-2, 4, 2, 1}}, {3, {-2, 4, 2, 1}}}};
    const std::array<b::Link, 2> aggregate{{{19, {-2, 4, 2, 1}}, {3, {-2, 4, 4, 2}}}};
    require(!std::holds_alternative<b::Refusal>(b::prepare(aggregate, locally_impossible, {0, false})),
        "wrong aggregate-only validation would accept the impossible local slot");
    const auto refusal = std::get<h::Refusal>(h::prepare(local_chain, locally_impossible, rig, {{0, false}, {}}, {}));
    require(refusal.reason == h::Error::link_refused && refusal.stage == 3 && refusal.link_error == s::Error::invalid_state,
        "every local retained relation is validated even paused");
    require(refused(h::prepare({}, initial, rig, {{0, false}, {}}, {}), h::Error::invalid_chain), "empty chain refuses");
    auto duplicate = chain;
    duplicate[1].id = 19;
    require(refused(h::prepare(duplicate, initial, rig, {{0, false}, {}}, {}), h::Error::invalid_chain), "duplicate chain IDs refuse");
    duplicate[1].id = 0;
    require(refused(h::prepare(duplicate, initial, rig, {{0, false}, {}}, {}), h::Error::invalid_chain), "zero chain ID refuses");
    auto unsorted = initial;
    std::reverse(unsorted.followers.begin(), unsorted.followers.end());
    require(refused(h::prepare(chain, unsorted, rig, {{0, false}, {}}, {}), h::Error::invalid_state), "chain order does not replace canonical live-state order");
    for (I raw : {std::numeric_limits<I>::min(), std::numeric_limits<I>::max()}) {
        auto invalid = initial;
        invalid.pin = raw;
        require(refused(h::prepare(chain, invalid, rig, {{0, false}, {}}, {}), h::Error::invalid_state), "raw pin bounded before arithmetic");
        invalid = initial;
        invalid.followers[0].position = raw;
        require(refused(h::prepare(chain, invalid, rig, {{0, false}, {}}, {}), h::Error::invalid_state), "raw follower bounded before subtraction");
        auto profile = chain;
        profile[1].slot.front = raw;
        require(refused(h::prepare(profile, initial, rig, {{0, false}, {}}, {}), h::Error::link_refused), "raw profiles validated before cumulative addition");
        require(refused(h::prepare(chain, initial, rig, {{raw, false}, {}}, {}), h::Error::workcell_refused), "raw destination still receives parent validation while paused");
    }
    auto huge = chain;
    huge[0].slot.back = huge[1].slot.back = 0;
    huge[0].slot.front = huge[1].slot.front = 2048;
    require(std::holds_alternative<b::Hold>(h::prepare(huge, initial, rig, {{0, false}, {}}, {})), "maximum effective native clearance is admitted exactly");
    huge[1].slot.front = 2049;
    require(refused(h::prepare(huge, initial, rig, {{0, false}, {}}, {}), h::Error::representation_limit), "cumulative clearance never widens native bounds");
    const std::array<b::Link, 2> edge{{{19, {-999999, -999998, 1, 0}}, {3, {-999999, -999998, 1, 0}}}};
    require(refused(h::prepare(edge, {-1000000, {{3, -999999}, {19, -999999}}}, rig, {{-1000000, false}, {}}, {}), h::Error::representation_limit),
        "valid local edge profiles may still exceed the effective bounded representation");
    const std::array<c::Obstacle, 1> frame{{{29, box(2, 3)}}};
    const std::array<p::Pair, 1> unknown{{{3, 99}}};
    require(refused(h::prepare(chain, initial, rig, {{8, true}, frame}, unknown), h::Error::workcell_refused), "bad pair set is checked before an earlier stationary block");
    auto wrong = rig;
    wrong.followers[1].id = 99;
    require(refused(h::prepare(chain, initial, wrong, {{0, false}, {}}, {}), h::Error::workcell_refused), "rig identity validation is retained");
    std::vector<c::Obstacle> many;
    for (std::size_t index = 0; index < g::maximum_parts; ++index) many.push_back({index + 1, box(100, 3)});
    many.back().box = box(2, 3);
    require(std::get<w::StationaryContact>(std::get<w::Blocked>(h::prepare(chain, initial, rig, {{8, true}, many}, {})).contact).hit.obstacle == g::maximum_parts,
        "last admitted obstacle participates in the complete cascade query");
    many.push_back({999, box(100, 3)});
    require(refused(h::prepare(chain, initial, rig, {{8, true}, many}, {}), h::Error::workcell_refused), "oversized obstacle set never truncates");
    std::vector<b::Link> too_many(b::maximum_links + 1, chain[0]);
    require(refused(h::prepare(too_many, initial, rig, {{0, false}, {}}, {}), h::Error::invalid_chain), "oversized chain refuses before copy");
}

// Independent continuous witness on an integer lattice. Propagate the original
// pin in HALF-unit steps through each LOCAL wall, in chain order. All wall and
// unit-box contact boundaries lie on integer coordinates, so the first strict
// interior sample follows its exact boundary by one half step. No effective
// clearance, production link/bank helper or sweep is used by this oracle.
struct Model {
    std::array<I, 3> at;
    I total{}, prefix{}, entry{};
    bool blocked{}, initially{};
    std::optional<b::Id> limit;
    std::array<std::optional<g::Rate>, 2> engagement;
    std::array<std::optional<s::Span>, 2> motion;
};
Model walk(I pin, I a, I tail, const std::array<b::Link, 2>& links, I destination, bool powered, int scene) {
    Model model{{pin * 2, a * 2, tail * 2}, std::abs(destination - pin) * 2, 0, 0, false, false, {}, {}, {}};
    const auto overlap = [&](const auto& at) {
        if (scene == 1) return at[2] + 2 > 4 && at[2] < 6;
        if (scene == 2) return at[1] + 2 > at[2] + 4 && at[1] < at[2] + 6;
        return false;
    };
    if (overlap(model.at)) { model.blocked = model.initially = true; return model; }
    if (!powered || !model.total) return model;
    const I direction = destination > pin ? 1 : -1;
    const auto observe = [&] {
        bool taut = true;
        for (std::size_t index = 0; index < 2; ++index) {
            const auto& slot = links[index].slot;
            taut = taut && model.at[index] == model.at[index + 1] + (direction > 0 ? slot.front : -slot.back) * 2;
            if (taut && !model.engagement[index]) model.engagement[index] = fraction(model.prefix, model.total);
            if (taut && model.at[index + 1] == (direction > 0 ? slot.upper : slot.lower) * 2 &&
                (!model.limit || links[index].id < *model.limit)) model.limit = links[index].id;
        }
    };
    observe();
    for (I distance = 1; distance <= model.total; ++distance) {
        auto proposed = model.at;
        proposed[0] += direction;
        bool outside = false;
        for (std::size_t index = 0; index < 2; ++index) {
            const auto& slot = links[index].slot;
            if (proposed[index] > proposed[index + 1] + slot.front * 2) proposed[index + 1] = proposed[index] - slot.front * 2;
            if (proposed[index] < proposed[index + 1] - slot.back * 2) proposed[index + 1] = proposed[index] + slot.back * 2;
            if (proposed[index + 1] < slot.lower * 2 || proposed[index + 1] > slot.upper * 2) outside = true;
        }
        if (outside) break;
        if (overlap(proposed)) { model.blocked = true; model.entry = distance - 1; return model; }
        for (std::size_t index = 0; index < 2; ++index) if (proposed[index + 1] != model.at[index + 1]) {
            if (!model.motion[index]) model.motion[index] = s::Span{fraction(distance - 1, model.total), fraction(distance, model.total)};
            else model.motion[index]->end = fraction(distance, model.total);
        }
        model.at = proposed;
        model.prefix = distance;
        observe();
    }
    return model;
}

void independent_model() {
    const std::array<std::pair<I, I>, 5> gaps{{{0, 0}, {1, 0}, {0, 1}, {1, 2}, {2, 1}}};
    for (const auto& [back_a, front_a] : gaps) for (const auto& [back_b, front_b] : gaps) {
        const std::array<b::Link, 2> links{{{19, {-1, 3, back_a, front_a}}, {3, {-1, 3, back_b, front_b}}}};
        for (I a = -1; a <= 3; ++a) for (I tail = -1; tail <= 3; ++tail) for (I pin = -4; pin <= 6; ++pin) {
            if (pin < a - back_a || pin > a + front_a || a < tail - back_b || a > tail + front_b) continue;
            for (I destination = -5; destination <= 7; destination += 2) for (bool power : {false, true}) for (int scene = 0; scene <= 2; ++scene) {
                ++model_cases;
                const b::State state{pin, {{3, tail}, {19, a}}};
                auto shapes = rig;
                shapes.followers[1].at_zero = box(scene == 2 ? 2 : 0, scene == 2 ? 0 : 3);
                const std::array<c::Obstacle, 1> frame{{{29, box(2, 3)}}};
                const std::span<const c::Obstacle> obstacles = scene == 1 ? std::span<const c::Obstacle>(frame) : std::span<const c::Obstacle>();
                const std::array<p::Pair, 1> forbidden{{{19, 3}}};
                const std::span<const p::Pair> pairs = scene == 2 ? std::span<const p::Pair>(forbidden) : std::span<const p::Pair>();
                const auto expected = walk(pin, a, tail, links, destination, power, scene);
                const auto plan = h::prepare(links, state, shapes, {{destination, power}, obstacles}, pairs);
                if (expected.blocked) {
                    const auto* blocked = std::get_if<w::Blocked>(&plan);
                    require(blocked && blocked->state == state, "independent local cascade block retains the complete original bank");
                    const auto at = expected.initially ? c::Fraction{0, 1} : time(expected.entry, expected.total);
                    if (scene == 1) require(std::get<w::StationaryContact>(blocked->contact) == w::StationaryContact{3, {29, at, expected.initially}},
                        "independent delayed stationary contact time");
                    else require(std::get<w::MovingContact>(blocked->contact) == w::MovingContact{{3, 19}, at, expected.initially}, "independent relative contact and canonical pair");
                } else if (!expected.prefix) {
                    const auto* held = std::get_if<b::Hold>(&plan);
                    const auto reason = !power ? b::Stop::unpowered : destination == pin ? b::Stop::rest : b::Stop::limit;
                    require(held && held->state == state && held->reason == reason && held->limit.has_value() == expected.limit.has_value(),
                        "independent local cascade pause/rest/binding hold");
                    if (held->limit) require(held->limit->id == *expected.limit && held->limit->stop.at == g::Rate{0, 1}, "independent canonical zero-time binding stop");
                } else {
                    const auto* step = std::get_if<h::Advance>(&plan);
                    require(expected.at[0] % 2 == 0 && expected.at[1] % 2 == 0 && expected.at[2] % 2 == 0, "independent model ends on the admitted integer lattice");
                    require(step && step->next == b::State{expected.at[0] / 2, {{3, expected.at[2] / 2}, {19, expected.at[1] / 2}}} &&
                        step->limit.has_value() == expected.limit.has_value(), "independent local cascade endpoints and whole-drive prefix");
                    for (const auto& trace : step->traces) {
                        const auto index = trace.id == 19 ? 0 : 1;
                        require(trace.motion == expected.motion[index], "independent local follower motion interval");
                        require(trace.drive_engagement.has_value() == expected.engagement[index].has_value(), "independent full push-path take-up existence");
                        if (trace.drive_engagement) require(trace.drive_engagement->at == *expected.engagement[index], "independent full push-path take-up time");
                    }
                    if (step->limit) require(step->limit->id == *expected.limit && step->limit->stop.at == fraction(expected.prefix, expected.total),
                        "independent earliest canonical guide binding in original stroke time");
                }
            }
        }
    }
}

void terminal() {
    struct Case { const char* input; int code; const char* witness; };
    const std::array<Case, 9> cases{{
        {"move 8\nmove 0\nquit\n", 1, "Pin 0; stage 7 2; tip 11 0;"},
        {"power off\nguide long\npower on\nmove 5\nmove 0\nquit\n", 0, "Matched: original pin 0, stage 7 at 2 and tip 11 at 1."},
        {"power off\ncoupler tight\npower on\nmove 3\nmove 0\nquit\n", 0, "Matched: original pin 0, stage 7 at 2 and tip 11 at 1."},
        {"move 8\npower off\nguide long\npower on\nmove 5\nmove 0\nquit\n", 0, "Pin 4; stage 7 3; tip 11 0; guide long;"},
        {"move 8\nmove -1\npower off\ncoupler tight\npower on\nmove 3\nmove 0\nquit\n", 0, "Matched: original pin 0, stage 7 at 2 and tip 11 at 1."},
        {"move 8\npower off\ncoupler tight\nquit\n", 1, "Refused: the proposed guide/coupler does not fit the retained state and frame."},
        {"power off\nguide long\npower on\nmove 8\nquit\n", 1, "Frame 29 blocks tip 11 at 5/8; ALL original positions retained."},
        {"guide long\ncoupler tight\nmove 33\nmove 2x\nmove 1 extra\nquit\n", 1, "Pin 0; stage 7 0; tip 11 0; guide short; coupler slack;"},
        {"power off\nmove 8\nquit\n", 1, "Hold unpowered."},
    }};
    for (const auto& value : cases) {
        std::istringstream input(value.input);
        std::ostringstream output, errors;
        require(h::play(input, output, errors) == value.code && errors.str().empty() && output.str().find(value.witness) != std::string::npos,
            "actual cascade terminal preserves solutions, starvation, editing and recovery");
    }
    std::istringstream oversized(std::string(513, 'x') + "\nstatus\nquit\n");
    std::ostringstream output, errors;
    require(h::play(oversized, output, errors) == 1 && output.str().find("command exceeds 512 bytes") != std::string::npos, "oversized terminal input is drained");
    std::istringstream broken;
    broken.setstate(std::ios::badbit);
    require(h::play(broken, output, errors) == 2, "failed terminal input is an operational error");
}
}  // namespace

int main() {
    controls();
    validation();
    independent_model();
    terminal();
    std::cout << "Passed " << assertions << " assertions; " << model_cases << " independent sequential half-step cascade cases.\n";
}
