#include "factory/slotted_bank.hpp"
#include "factory/slotted_bank_workbench.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>
#include <stdexcept>

namespace b = factory::slotted_bank;
namespace s = factory::slotted_link;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
b::Fraction fraction(I numerator, I denominator) {
    const auto divisor = std::gcd(numerator, denominator);
    return {numerator / divisor, denominator / divisor};
}
b::Advance advance(const b::Plan& plan) {
    check(std::holds_alternative<b::Advance>(plan), "The entire moving bank produces an owned common-prefix proposal.");
    return std::get<b::Advance>(plan);
}
void hold(const b::Plan& plan, const b::State& state, b::Stop reason, std::optional<b::Limit> limit = {}) {
    check(std::holds_alternative<b::Hold>(plan) && std::get<b::Hold>(plan) == b::Hold{state, reason, limit},
          "Holding the bank retains every original position and publishes no per-link trace.");
}
void refuse(const b::Plan& plan, b::Error reason, b::Id subject = 0) {
    check(std::holds_alternative<b::Refusal>(plan) && std::get<b::Refusal>(plan).reason == reason &&
          (subject == 0 || std::get<b::Refusal>(plan).subject == subject), "An invalid bank refuses without a partial branch candidate.");
}
std::vector<b::Link> fixture() { return {{3, {0, 4, 2, 1}}, {7, {-1, 2, 1, 0}}}; }
b::State initial() { return {0, {{3, 0}, {7, 0}}}; }
void literals() {
    auto links = fixture();
    const auto tight = advance(b::prepare(links, initial(), {32}));
    check(tight.next == b::State{2, {{3, 1}, {7, 2}}} && tight.limit == b::Limit{7, {s::Side::positive, {1, 16}}},
          "The second branch stops the common pin before the first branch can complete its independent stroke.");
    check(tight.traces[0].contact == s::Contact{s::Side::positive, {1, 32}} &&
          tight.traces[0].follower_motion == s::Span{{1, 32}, {1, 16}} && !tight.traces[0].endstop &&
          tight.traces[1].endstop == s::Endstop{s::Side::positive, {1, 16}},
          "Recomputed branch times stay in the original command rather than the shortened common prefix.");
    hold(b::prepare(links, tight.next, {32}), tight.next, b::Stop::limit, b::Limit{7, {s::Side::positive, {0, 1}}});
    links[0].slot.front = 3;
    const auto early = advance(b::prepare(links, initial(), {32}));
    check(early.next.followers[0].position == 0 && !early.traces[0].contact && !early.traces[0].follower_motion,
          "An independently predicted late contact disappears when another branch stops the pin first.");
    links = fixture();
    links[1].slot.front = 2;
    const auto delayed = advance(b::prepare(links, initial(), {32}));
    check(delayed.next == b::State{4, {{3, 3}, {7, 2}}} && delayed.limit == b::Limit{7, {s::Side::positive, {1, 8}}} &&
          delayed.traces[1].contact == s::Contact{s::Side::positive, {1, 16}},
          "Extra clearance in the second branch permits a longer coupled stroke.");
    check(advance(b::prepare(links, delayed.next, {0})).next == b::State{0, {{3, 2}, {7, 1}}},
          "The same two followers retain distinct offsets after the common pin returns home.");
    links = fixture();
    links[0].slot.front = 0;
    const auto compact = advance(b::prepare(links, initial(), {32}));
    check(compact.next == b::State{2, {{3, 2}, {7, 2}}} &&
          advance(b::prepare(links, compact.next, {0})).next == b::State{0, {{3, 2}, {7, 1}}},
          "Changing the first branch provides a genuinely different short-stroke solution.");
    links = fixture();
    const auto returned = advance(b::prepare(links, tight.next, {0}));
    const auto service = advance(b::prepare(links, returned.next, {-32}));
    check(service.next == b::State{-2, {{3, 0}, {7, -1}}} && service.limit == b::Limit{3, {s::Side::negative, {1, 16}}} &&
          service.traces[0].endstop && service.traces[1].endstop, "Simultaneous lower stops choose the lowest identity and retain both arrival traces.");
    check(advance(b::prepare(links, service.next, {0})).next == initial(), "A real negative service stroke recovers the wrong kit without replacing any state.");
    auto reordered = links;
    std::reverse(reordered.begin(), reordered.end());
    check(b::prepare(reordered, initial(), {32}) == b::prepare(links, initial(), {32}), "Profile order cannot change identities, times or stop selection.");
    const b::State zero_stop{2, {{3, 1}, {7, 2}}};
    links.push_back({9, {0, 4, -1, 0}});
    auto bad = zero_stop;
    bad.followers.push_back({9, 0});
    const auto refused = b::prepare(links, bad, {32});
    refuse(refused, b::Error::link_refused, 9);
    check(std::get<b::Refusal>(refused).link_error == s::Error::invalid_profile,
          "A later invalid link is checked before an earlier time-zero stop can hold the bank.");
    const s::Profile largest{-g::maximum_coordinate + 2, g::maximum_coordinate - 1, 2, 1};
    const std::array<b::Link, 1> large{{{1, largest}}};
    const b::State low{-g::maximum_coordinate, {{1, largest.lower}}};
    const auto extreme = advance(b::prepare(large, low, {g::maximum_coordinate}));
    check(extreme.next == b::State{g::maximum_coordinate, {{1, largest.upper}}} &&
          extreme.traces[0].contact == s::Contact{s::Side::positive, fraction(3, 2 * g::maximum_coordinate)},
          "Full native coordinate spans preserve small contact fractions without rational product overflow.");
}
void oracle() {
    std::size_t cases{};
    for (I ab = 0; ab <= 2; ++ab) for (I af = 0; af <= 2; ++af)
    for (I bb = 0; bb <= 2; ++bb) for (I bf = 0; bf <= 2; ++bf) {
        const std::array<s::Profile, 2> slots{{{-1, 2, ab, af}, {-1, 2, bb, bf}}};
        std::vector<b::Link> links{{9, slots[1]}, {2, slots[0]}};
        for (I a = -1; a <= 2; ++a) for (I other = -1; other <= 2; ++other) {
            const I low = std::max(a - ab, other - bb), high = std::min(a + af, other + bf);
            for (I pin = low; pin <= high; ++pin) for (I destination = -5; destination <= 5; ++destination)
            for (const bool powered : {false, true}) {
                const b::State state{pin, {{2, a}, {9, other}}};
                if (cases % 2 == 0) std::reverse(links.begin(), links.end());
                const auto actual = b::prepare(links, state, {destination, powered});
                const I direction = destination > pin ? 1 : -1;
                const I count = destination > pin ? destination - pin : pin - destination;
                const auto side = direction > 0 ? s::Side::positive : s::Side::negative;
                auto first_limit = [&](I current, b::Fraction at) -> std::optional<b::Limit> {
                    for (std::size_t index = 0; index < slots.size(); ++index) {
                        const I stop = direction > 0 ? slots[index].upper + slots[index].front : slots[index].lower - slots[index].back;
                        if (current == stop) return b::Limit{index == 0 ? b::Id{2} : b::Id{9}, {side, at}};
                    }
                    return {};
                };
                if (!powered) hold(actual, state, b::Stop::unpowered);
                else if (count == 0) hold(actual, state, b::Stop::rest);
                else if (const auto initial_limit = first_limit(pin, {0, 1})) hold(actual, state, b::Stop::limit, initial_limit);
                else {
                    auto walked = state;
                    std::vector<b::Trace> traces{{2, {}, {}, {}}, {9, {}, {}, {}}};
                    for (std::size_t index = 0; index < slots.size(); ++index) {
                        const I face = walked.followers[index].position + (direction > 0 ? slots[index].front : -slots[index].back);
                        if (walked.pin == face) traces[index].contact = s::Contact{side, {0, 1}};
                    }
                    std::optional<b::Limit> limit;
                    b::Fraction end{1, 1};
                    // Independent joint walk. Every follower uses the SAME next
                    // input point, then the whole walk stops at the first limit.
                    for (I step = 1; step <= count; ++step) {
                        walked.pin += direction;
                        const auto at = fraction(step, count);
                        for (std::size_t index = 0; index < slots.size(); ++index) {
                            auto& follower = walked.followers[index].position;
                            const auto& slot = slots[index];
                            const I face = follower + (direction > 0 ? slot.front : -slot.back);
                            if (!traces[index].contact && walked.pin == face) traces[index].contact = s::Contact{side, at};
                            if (walked.pin > follower + slot.front) ++follower;
                            if (walked.pin < follower - slot.back) --follower;
                            const I stop = direction > 0 ? slot.upper + slot.front : slot.lower - slot.back;
                            if (walked.pin == stop) traces[index].endstop = s::Endstop{side, at};
                        }
                        limit = first_limit(walked.pin, at);
                        if (limit) { end = at; break; }
                    }
                    for (std::size_t index = 0; index < slots.size(); ++index) {
                        if (walked.followers[index].position != state.followers[index].position) {
                            check(traces[index].contact.has_value(), "Every independently moved follower first touches its own wall.");
                            traces[index].follower_motion = s::Span{traces[index].contact->at, end};
                        }
                    }
                    const auto next = advance(actual);
                    check(next.next == walked, "Every follower and the one common pin match the independent stopped joint walk.");
                    check(next.limit == limit && next.traces == traces,
                          "Only jointly reached contacts, positive motion and limit times survive in the original stroke frame.");
                }
                check(state == b::State{pin, {{2, a}, {9, other}}}, "No branch preparation mutates the original shared state.");
                ++cases;
            }
        }
    }
    check(cases == 43560, "The full small shared-pin/clearance-history/power lattice was covered.");
}
void invalid() {
    auto links = fixture();
    auto state = initial();
    refuse(b::prepare({}, state, {0}), b::Error::invalid_profile);
    links[0].id = 0;
    refuse(b::prepare(links, state, {0, false}), b::Error::invalid_id);
    links = fixture(); links[1].id = 3;
    refuse(b::prepare(links, state, {0, false}), b::Error::duplicate_id, 3);
    links = fixture();
    std::reverse(state.followers.begin(), state.followers.end());
    refuse(b::prepare(links, state, {0, false}), b::Error::invalid_state);
    state = initial(); state.followers.pop_back();
    refuse(b::prepare(links, state, {0, false}), b::Error::invalid_state);
    state = initial(); state.followers[1].id = 3;
    refuse(b::prepare(links, state, {0, false}), b::Error::invalid_state);
    state = initial(); state.followers[1].position = 99;
    refuse(b::prepare(links, state, {0, false}), b::Error::link_refused, 7);
    state = initial();
    refuse(b::prepare(links, state, {std::numeric_limits<I>::min(), false}), b::Error::link_refused, 3);
    state.pin = std::numeric_limits<I>::max();
    refuse(b::prepare(links, state, {0, false}), b::Error::link_refused);
    links.clear(); state = {};
    for (b::Id id = 1; id <= b::maximum_links; ++id) { links.push_back({id, {0, 4, 0, 0}}); state.followers.push_back({id, 0}); }
    const auto all = advance(b::prepare(links, state, {4}));
    check(all.traces.size() == b::maximum_links && all.limit == b::Limit{1, {s::Side::positive, {1, 1}}},
          "The full bounded bank admits simultaneous stops with deterministic identity selection.");
    links.clear(); state.followers.clear();
    check(all.next.followers.front() == b::Follower{1, 4} && all.next.followers.back().position == 4,
          "Published positions and event traces outlive the original bank and state containers.");
    links.resize(b::maximum_links + 1);
    refuse(b::prepare(links, state, {0}), b::Error::invalid_profile);
}
struct Output { int code; std::string text; std::string errors; };
Output play(std::initializer_list<std::string_view> args, const std::string& commands) {
    std::istringstream input(commands);
    std::ostringstream out, errors;
    const int code = b::workbench(std::span(args.begin(), args.size()), input, out, errors);
    return {code, out.str(), errors.str()};
}
void caller() {
    const auto tight = play({"play"}, "move 32\nmove 0\nquit\n");
    check(tight.code == 1 && tight.errors.empty() && tight.text.find("Pin 0; A 1; B 1; kit tight") != std::string::npos &&
          tight.text.find("Limit 7 upper at 1/16") != std::string::npos, "The short second link prevents the first follower from reaching its needed offset.");
    const auto corrected = play({"play"}, "move 32\nmove 0\nkit delay\nmove -32\nmove 0\nkit delay\nmove 32\nmove 0\nquit\n");
    check(corrected.code == 0 && corrected.errors.empty() && corrected.text.find("BOTH original followers home") != std::string::npos &&
          corrected.text.find("Pin -2; A 0; B -1") != std::string::npos && corrected.text.find("Pin 0; A 2; B 1; kit delay") != std::string::npos,
          "A same-run service stroke returns both original followers before a compatible kit is installed.");
    check(play({"play"}, "kit compact\nmove 32\nmove 0\n").code == 0, "Changing front clearance in the first link supplies a second solution.");
    const auto delay = play({"play"}, "kit delay\nmove 32\nmove 0\n");
    check(delay.code == 0 && delay.text.find("Limit 7 upper at 1/8") != std::string::npos &&
          delay.text.find("Link 3 motion from 1/32 to 1/8") != std::string::npos, "The longer-clearance solution retains original common-stroke times.");
    const auto paused = play({"play"}, "kit delay\npower off\nmove 32\npower on\nmove 4\nmove 0\n");
    check(paused.code == 0 && paused.text.find("Hold unpowered") != std::string::npos && paused.text.find("Limit 7 upper at 1/1") != std::string::npos,
          "Pause retains no pending move; the newly commanded four-unit stroke has its own unit endpoint.");
    const auto partial = play({"play"}, "kit delay\nmove 4\nmove 1\nstatus\n");
    check(partial.code == 1 && partial.text.find("Pin 1; A 3; B 2") != std::string::npos, "Partial return retains independent follower histories without prematurely completing.");
    check(play({"play"}, "kit compact\nmove 32\nmove 32\n").text.find("Hold limit link 7") != std::string::npos,
          "A branch already at its limit holds the entire bank before another branch can advance.");
    const auto negative = play({"play"}, "kit compact\nmove -32\nmove 32\nmove 0\n");
    check(negative.code == 0 && negative.text.find("Limit 7 upper at 2/17") != std::string::npos,
          "Resuming from a negative pin position preserves the exact original requested travel time.");
    check(play({"play"}, "move nope\nmove 33\nmove 1 extra\nkit unknown\n").code == 1, "Malformed commands create no partial stroke.");
    const auto oversized = play({"play"}, "kit compact" + std::string(600, ' ') + "\nmove 32\nmove 0\n");
    check(oversized.code == 1 && oversized.text.find("command exceeds 512 bytes") != std::string::npos,
          "An oversized kit prefix cannot install a hidden solution.");
    check(play({"missing"}, "").code == 2 && play({"list"}, "").code == 0 && play({"--help"}, "").code == 0 && play({"play"}, "").code == 1,
          "Startup, catalogue and unfinished EOF have their declared outcomes.");
    std::istringstream input;
    input.setstate(std::ios::badbit);
    std::ostringstream out, errors;
    const std::array<std::string_view, 1> args{"play"};
    check(b::workbench(args, input, out, errors) == 2, "Failed input cannot report a completed setup.");
    std::istringstream good; out.setstate(std::ios::badbit);
    check(b::workbench(args, good, out, errors) == 2, "Failed output cannot report success.");
}
}  // namespace
int main() {
    try {
        literals(); oracle(); invalid(); caller();
        std::cout << checks << " slotted-bank assertions passed, including 43560 independent joint-walk cases.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " assertions: " << error.what() << '\n';
        return 1;
    }
}
