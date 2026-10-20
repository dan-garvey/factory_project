#include "factory/lift_transfer.hpp"
#include "factory/gravity.hpp"

#include <array>
#include <charconv>
#include <istream>
#include <optional>
#include <ostream>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace factory::lift {
namespace m = mechanisms;
namespace {
constexpr Profile profile{};
constexpr std::array<unsigned, 4> tags{7, 8, 9, 10};
struct Fixture {
    m::Phase phase;
    m::Cam receiver{8, 2};
    bool powered{true};
    std::size_t next_tag{};
    std::optional<unsigned> carried;
    std::vector<unsigned> delivered;
};

bool valid(const Fixture& fixture) {
    Pose at;
    bool receiver{};
    if (sample(profile, fixture.phase, at) != Error::none ||
        m::cam_active(profile.timing, fixture.phase, fixture.receiver, receiver) != m::Error::none ||
        fixture.next_tag > tags.size() || fixture.delivered.size() + fixture.carried.has_value() != fixture.next_tag)
        return false;
    for (std::size_t i = 0; i < fixture.delivered.size(); ++i) if (fixture.delivered[i] != tags[i]) return false;
    if (fixture.carried && *fixture.carried != tags[fixture.delivered.size()]) return false;
    // The only fixture custody transitions are lower load and upper unload.
    if (at.cycle.numerator > 0 && at.cycle.numerator < at.cycle.denominator &&
        ((at.cycle.stage == m::Stage::outward) != fixture.carried.has_value())) return false;
    return true;
}

bool complete(const Fixture& fixture) {
    return valid(fixture) && fixture.next_tag == tags.size() && !fixture.carried && fixture.phase.tooth == 0;
}

void inspect(const Fixture& fixture, std::ostream& out) {
    Pose at;
    bool open{};
    if (sample(profile, fixture.phase, at) != Error::none ||
        m::cam_active(profile.timing, fixture.phase, fixture.receiver, open) != m::Error::none) return;
    out << "Phase " << fixture.phase.tooth << ", " << m::stage_name(at.cycle.stage)
        << ", platform top y=" << at.platform.maximum[1] << ", power " << (fixture.powered ? "on" : "off")
        << ", receiver " << (open ? "open" : "closed") << " (cam " << fixture.receiver.start << "+2).\n"
           "Tags pending:";
    if (fixture.next_tag == tags.size()) out << " none";
    for (std::size_t i = fixture.next_tag; i < tags.size(); ++i) out << ' ' << tags[i];
    out << "; carried: ";
    if (fixture.carried) out << *fixture.carried; else out << "none";
    out << "; delivered:";
    if (fixture.delivered.empty()) out << " none";
    for (const auto tag : fixture.delivered) out << ' ' << tag;
    out << ".\n";
}

bool step(Fixture& fixture, std::ostream& out, std::ostream& errors) {
    if (!valid(fixture)) { errors << "Invalid fixture state.\n"; return false; }
    bool open{};
    if (m::cam_active(profile.timing, fixture.phase, fixture.receiver, open) != m::Error::none) return false;
    const auto plan = prepare(profile, fixture.phase,
        {fixture.powered, fixture.carried.has_value(), fixture.next_tag < tags.size(), open, {}});
    auto next = fixture;
    if (const auto* error = std::get_if<Error>(&plan)) {
        errors << "Planner refused: " << error_name(*error) << ".\n";
        return false;
    }
    if (const auto* hold = std::get_if<Hold>(&plan)) {
        out << "Held: " << stop_name(hold->reason) << "; phase and tagged load preserved.\n";
        return false;
    }
    if (const auto* handoff = std::get_if<Handoff>(&plan)) {
        if (handoff->direction == Direction::load) {
            if (next.carried || next.next_tag == tags.size()) return false;
            next.carried = tags[next.next_tag++];
        } else {
            if (!next.carried) return false;
            next.delivered.push_back(*next.carried);
            next.carried.reset();
        }
    } else next.phase = std::get<Step>(plan).next;
    if (!valid(next)) { errors << "Refused inconsistent tag custody.\n"; return false; }
    fixture = std::move(next);
    return true;
}

bool number(std::string_view text, m::Tooth& result) {
    const auto parsed = std::from_chars(text.data(), text.data() + text.size(), result);
    return parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size();
}

void help(std::ostream& out) {
    out << "Commands: step [1..64], gate START (0..11; width stays 2), power on|off, compare, inspect, help, quit.\n"
           "Each step applies one proposal. Handoffs hold phase; blocked input stops a step batch.\n"
           "The gate shares the held shaft. A cam keyed after arrival cannot open by waiting.\n";
}
}  // namespace

int compare(std::ostream& out) {
    namespace g = gravity;
    constexpr std::array<g::Point, 5> lower{{{0, 4, 0}, {1, 3, 0}, {2, 2, 0}, {3, 1, 0}, {4, 0, 0}}};
    constexpr std::array<g::Point, 5> uphill{{{0, 4, 0}, {1, 3, 0}, {2, 2, 0}, {3, 1, 0}, {4, 4, 0}}};
    constexpr std::array<g::Point, 3> feed{{{0, 4, 0}, {1, 3, 0}, {2, 2, 0}}};
    constexpr std::array<g::Point, 3> output{{{2, 6, 0}, {3, 5, 0}, {4, 4, 0}}};
    const std::array<g::Route, 1> a{{{lower, lower.front(), lower.back()}}};
    const std::array<g::Route, 1> b{{{uphill, uphill.front(), uphill.back()}}};
    const std::array<g::Route, 2> c{{{feed, feed.front(), feed.back()}, {output, output.front(), output.back()}}};
    const g::Site site{{0, 0, -1}, {4, 6, 1}, {}, 5};
    const auto low = g::inspect(site, a), high = g::inspect(site, b), lifted = g::inspect(site, c);
    Pose at;
    const auto at_port = [](const Pose& pose, g::Point port) {
        return pose.platform.minimum[0] + pose.platform.maximum[0] == 2 * port.x &&
            pose.platform.minimum[2] + pose.platform.maximum[2] == 2 * port.z && pose.platform.maximum[1] == port.y;
    };
    const bool connects = sample(profile, {}, at) == Error::none && at_port(at, feed.back()) &&
        sample(profile, {6}, at) == Error::none && at_port(at, output.front());
    if (!low.solved() || high.solved() || !lifted.solved() || !connects) return 2;
    out << "Lowered cell: source (0,4,0) -> processor (4,0,0), four descending chute pieces, no lift.\n"
           "Raised cell: source and processor both y=4; gravity alone refuses: " << g::explanation(high.fault) << '\n'
        << "Raised solution: two chute pieces to (2,2,0), lift four levels to (2,6,0), two chute pieces to (4,4,0).\n"
           "These are centerline/layout and lift-envelope checks, not body contacts, throughput or World transfers.\n";
    return out ? 0 : 2;
}

int play(std::istream& input, std::ostream& out, std::ostream& errors) {
    Fixture fixture;
    out << "Fixed lift: four tagged loads to the raised cell, then return the empty carrier.\n"
           "Tags 7, 8, 9 and 10 are finite fixture metadata, not World goods. No reset is available.\n";
    help(out);
    inspect(fixture, out);
    std::string line;
    while (std::getline(input, line)) {
        if (line.size() > 256) { errors << "Command exceeds 256 bytes.\n"; continue; }
        std::istringstream tokens(line);
        std::string command, argument, extra;
        if (!(tokens >> command)) continue;
        tokens >> argument;
        if (tokens >> extra) { errors << "Use one command per line.\n"; continue; }
        if (command == "step") {
            m::Tooth count{1};
            if ((!argument.empty() && !number(argument, count)) || count < 1 || count > 64) {
                errors << "Step count must be 1..64.\n"; continue;
            }
            for (m::Tooth i = 0; i < count && !complete(fixture); ++i) if (!step(fixture, out, errors)) break;
        } else if (command == "gate") {
            m::Tooth start{};
            bool active{};
            if (!number(argument, start) || m::cam_active(profile.timing, fixture.phase, {start, 2}, active) != m::Error::none) {
                errors << "Gate start must be 0..11.\n"; continue;
            }
            fixture.receiver.start = start;
        } else if (command == "power" && (argument == "on" || argument == "off")) fixture.powered = argument == "on";
        else if (command == "compare" && argument.empty()) { if (compare(out) != 0) return 2; }
        else if (command == "help" && argument.empty()) help(out);
        else if (command == "quit" && argument.empty()) break;
        else if (command != "inspect" || !argument.empty()) { errors << "Unknown command. Use help.\n"; continue; }
        inspect(fixture, out);
        if (complete(fixture)) {
            out << "Complete: tags 7 8 9 10 delivered; the empty carrier is back at the lower dock.\n";
            return out ? 0 : 2;
        }
    }
    if (!input.eof() && input.fail()) { errors << "Input failed.\n"; return 2; }
    out << "Unfinished: retained tags and carrier phase have not been reset.\n";
    return out ? 1 : 2;
}
}  // namespace factory::lift
