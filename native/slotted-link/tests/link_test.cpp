#include "factory/slotted_link.hpp"
#include "factory/slotted_link_workbench.hpp"

#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace s = factory::slotted_link;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
s::Fraction fraction(I numerator, I denominator) {
    const auto divisor = std::gcd(numerator, denominator);
    return {numerator / divisor, denominator / divisor};
}
s::Advance advance(const s::Plan& plan) {
    check(std::holds_alternative<s::Advance>(plan), "A nonempty pin stroke publishes an owned proposal.");
    return std::get<s::Advance>(plan);
}
void hold(const s::Plan& plan, const s::State& state, s::Stop reason) {
    check(std::holds_alternative<s::Hold>(plan) && std::get<s::Hold>(plan).state == state && std::get<s::Hold>(plan).reason == reason,
          "A held stroke retains both original positions without contact or motion events.");
}
void refuse(const s::Plan& plan, s::Error reason) {
    check(std::holds_alternative<s::Error>(plan) && std::get<s::Error>(plan) == reason,
          "Invalid data refuses the complete proposal.");
}
void literals() {
    const s::Profile profile;
    const auto outward = advance(s::prepare(profile, {}, {3}));
    check(outward.next == s::State{3, 2} && outward.contact == s::Contact{s::Side::positive, {1, 3}} &&
          outward.follower_motion == s::Span{{1, 3}, {1, 1}} && !outward.endstop,
          "The drive pin takes up front clearance before pushing the same follower.");
    const auto home = advance(s::prepare(profile, outward.next, {0}));
    check(home.next == s::State{0, 2} && home.contact == s::Contact{s::Side::negative, {1, 1}} && !home.follower_motion,
          "Return touches the back wall at the endpoint without undoing the follower offset.");
    const auto remembered = advance(s::prepare(profile, home.next, {2}));
    const auto fresh = advance(s::prepare(profile, {}, {2}));
    check(remembered.next == s::State{2, 2} && fresh.next == s::State{2, 1},
          "Equal initial pin positions with different slot histories cannot substitute a mirrored follower pose.");
    const auto clipped = advance(s::prepare(profile, {}, {8}));
    check(clipped.next == s::State{5, 4} && clipped.contact == s::Contact{s::Side::positive, {1, 8}} &&
          clipped.endstop == s::Endstop{s::Side::positive, {5, 8}} && clipped.follower_motion == s::Span{{1, 8}, {5, 8}},
          "The first declared travel stop clips both positions and retains original command times.");
    hold(s::prepare(profile, clipped.next, {32}), clipped.next, s::Stop::upper_end);
    const auto reverse = advance(s::prepare(profile, clipped.next, {-8}));
    check(reverse.next == s::State{-2, 0} && reverse.contact == s::Contact{s::Side::negative, {3, 13}} &&
          reverse.endstop == s::Endstop{s::Side::negative, {7, 13}} && reverse.follower_motion == s::Span{{3, 13}, {7, 13}},
          "Reversal consumes the opposite clearance and clips at the exact lower stop.");
    const auto touching = advance(s::prepare(profile, {}, {1}));
    check(touching.next == s::State{1, 0} && touching.contact == s::Contact{s::Side::positive, {1, 1}} && !touching.follower_motion,
          "An isolated endpoint touch is not a positive-duration follower interval.");
    const auto push = advance(s::prepare(profile, touching.next, {3}));
    check(push.contact == s::Contact{s::Side::positive, {0, 1}} && push.follower_motion == s::Span{{0, 1}, {1, 1}},
          "A stroke beginning on its pushing face starts motion at time zero.");
    const auto withdraw = advance(s::prepare(profile, touching.next, {0}));
    check(!withdraw.contact && !withdraw.follower_motion && withdraw.next == s::State{},
          "Withdrawing from a wall does not count it as another incoming contact.");
    const auto rigid = advance(s::prepare({0, 4, 0, 0}, {}, {4}));
    check(rigid.next == s::State{4, 4} && rigid.contact == s::Contact{s::Side::positive, {0, 1}} &&
          rigid.endstop == s::Endstop{s::Side::positive, {1, 1}}, "The zero-clearance limit is a rigid follower with an exact endpoint stop.");
    const s::Profile largest{-g::maximum_coordinate + 2, g::maximum_coordinate - 1, 2, 1};
    const auto extreme = advance(s::prepare(largest, {-g::maximum_coordinate, largest.lower}, {g::maximum_coordinate}));
    check(extreme.next == s::State{g::maximum_coordinate, largest.upper} &&
          extreme.contact == s::Contact{s::Side::positive, fraction(3, 2 * g::maximum_coordinate)} &&
          extreme.endstop == s::Endstop{s::Side::positive, {1, 1}}, "The full native coordinate span preserves exact small contact times without overflow.");
}
void oracle() {
    std::size_t cases{};
    for (I back = 0; back <= 2; ++back) for (I front = 0; front <= 2; ++front) {
        const s::Profile profile{-2, 2, back, front};
        for (I follower = -2; follower <= 2; ++follower) for (I pin = follower - back; pin <= follower + front; ++pin) {
            for (I destination = -6; destination <= 6; ++destination) for (const bool powered : {false, true}) {
                const s::State initial{pin, follower};
                const auto actual = s::prepare(profile, initial, {destination, powered});
                const I direction = destination > pin ? 1 : -1;
                const I boundary = direction > 0 ? 2 + front : -2 - back;
                const I count = destination > pin ? destination - pin : pin - destination;
                if (!powered) hold(actual, initial, s::Stop::unpowered);
                else if (count == 0) hold(actual, initial, s::Stop::rest);
                else if (pin == boundary) hold(actual, initial, direction > 0 ? s::Stop::upper_end : s::Stop::lower_end);
                else {
                    s::State walked = initial;
                    std::optional<s::Contact> contact;
                    std::optional<s::Endstop> end;
                    const auto side = direction > 0 ? s::Side::positive : s::Side::negative;
                    if (pin == follower + (direction > 0 ? front : -back)) contact = s::Contact{side, {0, 1}};
                    // Independent unit-step walk: take up clearance, touch the
                    // current wall, then shift the follower one grid unit.
                    for (I step = 1; step <= count; ++step) {
                        walked.pin += direction;
                        const I wall = walked.follower + (direction > 0 ? front : -back);
                        if (!contact && walked.pin == wall) contact = s::Contact{side, fraction(step, count)};
                        if (walked.pin > walked.follower + front) ++walked.follower;
                        if (walked.pin < walked.follower - back) --walked.follower;
                        if (walked.pin == boundary) { end = s::Endstop{side, fraction(step, count)}; break; }
                    }
                    std::optional<s::Span> moving;
                    if (walked.follower != follower) {
                        check(contact.has_value(), "Every independent follower shift has a prior wall touch.");
                        moving = s::Span{contact->at, end ? end->at : s::Fraction{1, 1}};
                    }
                    const auto next = advance(actual);
                    check(next.next == walked, "Both proposed positions match the independent clearance-and-push walk.");
                    check(next.contact == contact && next.endstop == end && next.follower_motion == moving,
                          "Original-time contact, positive follower duration and clipped stop match the independent walk.");
                }
                check(initial == s::State{pin, follower}, "Preparing a stroke never edits the caller-owned state.");
                ++cases;
            }
        }
    }
    check(cases == 3510, "Every declared small clearance history, destination and power case was covered.");
}
void invalid() {
    const s::State state;
    for (const auto profile : {s::Profile{1, 1, 0, 0}, {2, 1, 0, 0}, {0, 4, -1, 1}, {0, 4, 1, -1},
                               {0, 4, g::maximum_dimension, 1}, {-g::maximum_coordinate, 4, 1, 0},
                               {0, g::maximum_coordinate, 0, 1}, {std::numeric_limits<I>::min(), 4, 0, 0},
                               {0, std::numeric_limits<I>::max(), 0, 0}})
        refuse(s::prepare(profile, state, {0, false}), s::Error::invalid_profile);
    for (const auto bad : {s::State{-3, 0}, {2, 0}, {0, -1}, {0, 5}, {std::numeric_limits<I>::min(), 0}, {0, std::numeric_limits<I>::max()}})
        refuse(s::prepare({}, bad, {0, false}), s::Error::invalid_state);
    for (const I destination : {-g::maximum_coordinate - 1, g::maximum_coordinate + 1, std::numeric_limits<I>::min(), std::numeric_limits<I>::max()})
        refuse(s::prepare({}, state, {destination, false}), s::Error::invalid_destination);
    hold(s::prepare({}, {3, 2}, {32, false}), {3, 2}, s::Stop::unpowered);
    hold(s::prepare({}, {3, 2}, {3}), {3, 2}, s::Stop::rest);
}
struct Output { int code; std::string text; std::string errors; };
Output play(std::initializer_list<std::string_view> args, const std::string& commands) {
    std::istringstream input(commands);
    std::ostringstream out, errors;
    const int code = s::workbench(std::span(args.begin(), args.size()), input, out, errors);
    return {code, out.str(), errors.str()};
}
void caller() {
    const auto tight = play({"play"}, "move 3\nmove 0\nquit\n");
    check(tight.code == 1 && tight.errors.empty() && tight.text.find("Pin 0; follower 0; kit tight") != std::string::npos,
          "The wrong slot cannot keep the follower offset when returning its pin home.");
    const auto corrected = play({"play"}, "move 3\nkit return\nmove 0\nkit return\nmove 3\nmove 0\nquit\n");
    check(corrected.code == 0 && corrected.errors.empty() && corrected.text.find("return BOTH original positions home") != std::string::npos &&
          corrected.text.find("Contact negative at 1/1") != std::string::npos,
          "The same-run correction returns both original positions before replacing the link, then preserves the follower.");
    check(play({"play"}, "kit compact\nmove 2\nmove 0\n").code == 0, "A zero-front-clearance link is a distinct valid configuration.");
    const auto overdrive = play({"play"}, "kit return\nmove 32\nmove 0\n");
    check(overdrive.code == 0 && overdrive.text.find("Travel upper at 5/32") != std::string::npos,
          "A larger stroke also solves the geometric problem after a real clipped upper stop.");
    const auto paused = play({"play"}, "kit return\npower off\nmove 32\npower on\nmove 3\nmove 0\n");
    check(paused.code == 0 && paused.text.find("Hold unpowered") != std::string::npos && paused.text.find("Travel upper") == std::string::npos,
          "A paused destination is discarded without motion debt on resumption.");
    const auto partial = play({"play"}, "kit return\nmove 3\nmove 1\nstatus\n");
    check(partial.code == 1 && partial.text.find("Pin 1; follower 2") != std::string::npos,
          "A partial return retains follower position but cannot finish before the pin is home.");
    const auto endpoint = play({"play"}, "kit return\nmove 32\nmove 32\n");
    check(endpoint.code == 1 && endpoint.text.find("Hold upper_end") != std::string::npos,
          "Another outward command at the stop holds both positions.");
    check(play({"play"}, "kit return\nmove -32\nmove 3\nmove 0\n").code == 0,
          "The lower stop is recoverable without resetting either original position.");
    check(play({"play"}, "move nope\nmove 33\nmove 1 extra\nkit unknown\n").code == 1,
          "Malformed and out-of-bound commands cannot become motion.");
    const auto oversized = play({"play"}, "kit compact" + std::string(600, ' ') + "\nmove 2\nmove 0\n");
    check(oversized.code == 1 && oversized.text.find("command exceeds 512 bytes") != std::string::npos,
          "An oversized kit prefix cannot secretly install the compatible link.");
    check(play({"missing"}, "").code == 2 && play({"list"}, "").code == 0 && play({"--help"}, "").code == 0 && play({"play"}, "").code == 1,
          "Catalogue, startup refusal and unfinished EOF have distinct outcomes.");
    std::istringstream input;
    input.setstate(std::ios::badbit);
    std::ostringstream out, errors;
    const std::vector<std::string_view> args{"play"};
    check(s::workbench(args, input, out, errors) == 2, "Input failure cannot be reported as a completed puzzle.");
    std::istringstream good;
    out.setstate(std::ios::badbit);
    check(s::workbench(args, good, out, errors) == 2, "Output failure cannot be reported as success.");
}
}  // namespace
int main() {
    try {
        literals(); oracle(); invalid(); caller();
        std::cout << checks << " slotted-link assertions passed, including 3510 independent clearance-history cases.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " assertions: " << error.what() << '\n';
        return 1;
    }
}
