#include "factory/coupling_puzzles.hpp"

#include <algorithm>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>

namespace g = factory::mechanics;
namespace s = factory::sliding_couplings;
namespace p = factory::coupling_puzzles;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
s::Prepared accepted(s::Plan plan) {
    check(std::holds_alternative<s::Prepared>(plan), "The legal shaft proposal is accepted.");
    return std::get<s::Prepared>(std::move(plan));
}
void refused(const s::Plan& plan, s::Error error, g::Error kernel = g::Error::none) {
    check(std::holds_alternative<s::Refusal>(plan), "A refusal returns no partial parts or motion candidate.");
    check(std::get<s::Refusal>(plan) == s::Refusal{error, kernel}, "The refusal retains its precise local/kernel reason.");
}
const g::Motion& motion(const g::Result& result, const char* hub) {
    return result.motion.at(hub);
}
s::Shift shift(const p::Puzzle& puzzle, std::size_t slot, bool out) {
    const auto& item = puzzle.slots.at(slot);
    return {item.shaft, out ? item.withdrawn : item.engaged};
}
void original_parts(const std::vector<g::Part>& original, const std::vector<g::Part>& proposed) {
    check(original.size() == proposed.size(), "No shaft is removed, refunded or issued by a shift.");
    for (std::size_t i = 0; i < original.size(); ++i) {
        auto at_old_position = proposed[i];
        at_old_position.center = original[i].center;
        check(at_old_position == original[i], "Identity, kind, axis, span, teeth and caller ordering are retained.");
    }
}
void layouts() {
    for (const std::string id : {"branch", "bypass", "selector"}) {
        auto puzzle = *p::make(id);
        const auto original = puzzle.parts;
        const auto sources = puzzle.sources;
        const auto initial = g::evaluate(original, sources);
        check(initial.accepted() && !p::solved(puzzle, initial), "Each original layout is a valid unfinished puzzle.");
        check(motion(initial, id == "selector" ? "output" : "useful").state == g::MotionState::stalled,
              "The actual initial connected component stalls, rather than merely hiding output.");
        for (unsigned mask = 0; mask < (1U << puzzle.slots.size()); ++mask) {
            std::vector<s::Shift> moves;
            for (std::size_t i = 0; i < puzzle.slots.size(); ++i) moves.push_back(shift(puzzle, i, mask & (1U << i)));
            const auto result = accepted(s::prepare(original, sources, moves));
            original_parts(original, result.parts);
            check(puzzle.parts == original && puzzle.sources == sources, "Pure preparation leaves every input unchanged.");
            if (id == "selector") {
                const auto actual = motion(result.motion, "output");
                const g::Motion expected = mask == 0 ? g::Motion{g::MotionState::stalled, {0, 1}}
                    : mask == 3 ? g::Motion{g::MotionState::unpowered, {0, 1}}
                    : g::Motion{g::MotionState::rotating, {mask == 2 ? 1 : -1, 1}};
                check(actual == expected, "Both drives conflict; neither drive leaves output unpowered; a sole drive sets its literal sign.");
                check(p::solved(puzzle, result.motion) == (mask == 2), "Only the forward source with the reverse coupling withdrawn meets the target.");
            } else {
                const bool isolated = mask == (1U << puzzle.slots.size()) - 1;
                check(motion(result.motion, "useful") == (isolated
                    ? g::Motion{g::MotionState::rotating, {-1, 1}}
                    : g::Motion{g::MotionState::stalled, {0, 1}}),
                    "The useful branch runs only after every real path to the held branch is open.");
                check(motion(result.motion, "held") == g::Motion{isolated ? g::MotionState::stopped : g::MotionState::stalled, {0, 1}},
                    "The isolated held hub remains stopped instead of receiving invented motion.");
                check(p::solved(puzzle, result.motion) == isolated, "A single withdrawn bypass coupling is insufficient.");
            }
            check(result.motion == g::evaluate(result.parts, sources), "The proposal exposes the unchanged canonical kernel derivation.");
        }
        std::vector<s::Shift> moves;
        for (std::size_t i = 0; i < puzzle.slots.size(); ++i) moves.push_back(shift(puzzle, i, true));
        auto first = accepted(s::prepare(original, sources, moves));
        puzzle.parts = first.parts;
        moves.clear();
        for (std::size_t i = 0; i < puzzle.slots.size(); ++i) moves.push_back(shift(puzzle, i, false));
        auto restored = accepted(s::prepare(puzzle.parts, sources, moves));
        check(restored.parts == original && restored.motion == initial, "Re-engaging the original shafts restores the original real stall without a reset.");
    }
    check(!p::make("unknown"), "An unknown fixture cannot silently select a different puzzle.");
    auto empty = *p::make("branch");
    empty.goals.clear();
    check(!p::solved(empty, g::evaluate(empty.parts, empty.sources)), "An empty target list is never vacuously solved.");
}
void axis_and_order() {
    for (std::size_t axis = 0; axis < 3; ++axis) {
        auto puzzle = *p::make("bypass");
        auto convert = [axis](g::Point& point) { std::swap(point[axis], point[2]); };
        for (auto& part : puzzle.parts) { convert(part.center); part.axis = static_cast<g::Axis>(axis); }
        for (auto& slot : puzzle.slots) { convert(slot.engaged); convert(slot.withdrawn); }
        const std::vector<s::Shift> moves{shift(puzzle, 0, true), shift(puzzle, 1, true)};
        auto result = accepted(s::prepare(puzzle.parts, puzzle.sources, moves));
        check(p::solved(puzzle, result.motion), "The same literal isolation works on all three native shaft axes.");
        std::reverse(puzzle.parts.begin(), puzzle.parts.end());
        std::reverse(puzzle.sources.begin(), puzzle.sources.end());
        auto reversed_moves = moves;
        std::reverse(reversed_moves.begin(), reversed_moves.end());
        const auto reversed = accepted(s::prepare(puzzle.parts, puzzle.sources, reversed_moves));
        check(result.motion == reversed.motion, "Part, source and atomic-shift request order do not select a hidden mechanical answer.");
        puzzle.parts.clear(); puzzle.sources.clear();
        check(motion(result.motion, "useful") == g::Motion{g::MotionState::rotating, {-1, 1}} && !result.parts.empty(),
              "Prepared identities and motion remain owned after every original input is destroyed.");
    }
}
void refusals() {
    auto puzzle = *p::make("branch");
    const auto original = puzzle.parts;
    const auto sources = puzzle.sources;
    auto attempt = [&](std::vector<s::Shift> moves, s::Error error, g::Error kernel = g::Error::none) {
        refused(s::prepare(puzzle.parts, puzzle.sources, moves), error, kernel);
        check(puzzle.parts == original && puzzle.sources == sources, "A refused batch leaves geometry and registered sources unchanged.");
    };
    const auto legal = shift(puzzle, 0, true);
    attempt({legal, {"absent", {0, 0, 0}}}, s::Error::unknown_shaft);
    attempt({legal, legal}, s::Error::duplicate_shift);
    attempt({{"", {0, 0, 0}}}, s::Error::invalid_identity);
    attempt({{std::string(129, 'x'), {0, 0, 0}}}, s::Error::invalid_identity);
    attempt({{std::string("lower\0tail", 10), {4, 0, 1}}}, s::Error::invalid_identity);
    attempt({{"wheel", {0, 0, 1}}}, s::Error::not_a_shaft);
    attempt({{"wheel-gear", {0, 0, 1}}}, s::Error::not_a_shaft);
    attempt({{"lower", {5, 0, 1}}}, s::Error::off_axis);
    attempt({{"lower", {4, 1, 1}}}, s::Error::off_axis);
    for (const auto endpoint : {g::maximum_coordinate, -g::maximum_coordinate,
                               std::numeric_limits<g::Integer>::max(), std::numeric_limits<g::Integer>::min()})
        attempt({{"lower", {4, 0, endpoint}}}, s::Error::invalid_candidate, g::Error::invalid_part);
    auto still = accepted(s::prepare(puzzle.parts, puzzle.sources, {}));
    check(still.parts == original && still.motion == g::evaluate(original, sources), "An empty batch is a validated no-op, even when the layout stalls.");
    const std::vector<s::Shift> no_op{{"lower", {4, 0, 4}}};
    check(accepted(s::prepare(puzzle.parts, puzzle.sources, no_op)).parts == original, "Requesting the current endpoint is a legal no-op.");

    puzzle.parts[0].id = std::string(129, 'x');
    refused(s::prepare(puzzle.parts, puzzle.sources, {}), s::Error::invalid_scene, g::Error::invalid_part);
    puzzle.parts = original;
    puzzle.parts[0].axis = static_cast<g::Axis>(8);
    refused(s::prepare(puzzle.parts, puzzle.sources, {&legal, 1}), s::Error::invalid_scene, g::Error::invalid_part);
    puzzle.parts = original;
    puzzle.parts.push_back(original.front());
    refused(s::prepare(puzzle.parts, puzzle.sources, {}), s::Error::invalid_scene, g::Error::duplicate_identity);
    puzzle.parts = original;
    puzzle.sources[0].rate.denominator = 0;
    refused(s::prepare(puzzle.parts, puzzle.sources, {}), s::Error::invalid_scene, g::Error::invalid_drive);
    puzzle.sources = sources;
    puzzle.parts.push_back({"overlap", g::Kind::gear, {1, 0, 0}, g::Axis::z, 2});
    refused(s::prepare(puzzle.parts, puzzle.sources, {}), s::Error::invalid_scene, g::Error::overlapping_gears);

    std::vector<g::Part> parts;
    std::vector<s::Shift> moves;
    for (std::size_t i = 0; i < g::maximum_parts; ++i) {
        const auto id = "shaft-" + std::to_string(i);
        const auto x = static_cast<g::Integer>(i * 4);
        parts.push_back({id, g::Kind::shaft, {x, 0, 0}, g::Axis::z, 0, 1});
        moves.push_back({id, {x, 0, 1}});
    }
    check(accepted(s::prepare(parts, {}, moves)).parts.size() == g::maximum_parts, "The exact native part/shift bound remains usable.");
    moves.push_back(moves.front());
    refused(s::prepare(parts, {}, moves), s::Error::too_many_shifts);
    parts.push_back({"extra", g::Kind::shaft, {0, 4, 0}, g::Axis::z, 0, 1});
    refused(s::prepare(parts, {}, {}), s::Error::invalid_scene, g::Error::too_many_parts);
}
void candidate_overflow() {
    const std::vector<g::Part> parts{
        {"source", g::Kind::hub, {0, 0, 8}, g::Axis::z},
        {"source-shaft", g::Kind::shaft, {0, 0, 8}, g::Axis::z, 0, 1},
        {"coupler", g::Kind::shaft, {0, 0, 5}, g::Axis::z, 0, 3},
        {"large-shaft", g::Kind::shaft, {0, 0, 0}, g::Axis::z, 0, 1},
        {"large", g::Kind::gear, {0, 0, 0}, g::Axis::z, 3},
        {"small", g::Kind::gear, {4, 0, 0}, g::Axis::z, 1},
    };
    const std::vector<g::Drive> sources{{"source", {g::Integer{1} << 62, 1}}};
    check(g::evaluate(parts, sources).accepted(), "The disconnected original high-rate source is representable.");
    const s::Shift connect{"coupler", {0, 0, 4}};
    refused(s::prepare(parts, sources, {&connect, 1}), s::Error::invalid_candidate, g::Error::rate_overflow);
    check(g::evaluate(parts, sources).accepted() && parts[2].center == g::Point{0, 0, 5},
          "Refusing the newly connected threefold speed increase preserves the original disconnected source.");
}
struct Output { int code; std::string text; std::string errors; };
Output play(std::vector<std::string_view> args, const std::string& commands) {
    std::istringstream input(commands);
    std::ostringstream out, errors;
    const auto code = p::workbench(args, input, out, errors);
    return {code, out.str(), errors.str()};
}
void caller() {
    const auto branch = play({"play", "branch"}, "shift lower out\nstatus\nshift lower in\nstatus\nshift lower out\nquit\n");
    check(branch.code == 0 && branch.errors.empty() && branch.text.find("Hub useful: rotating -1/1.") != std::string::npos,
          "A person can isolate, re-engage and correct the same shaft in one terminal run.");
    const auto bypass = play({"play", "bypass"}, "shift lower out\nstatus\nquit\n");
    check(bypass.code == 1 && bypass.text.find("Hub useful: rotating") == std::string::npos,
          "The actual caller never calls a single-open bypass solved.");
    check(play({"play", "bypass"}, "shift lower out\nshift upper out\n").code == 0, "Opening both actual paths solves the bypass at EOF.");
    check(play({"play", "selector"}, "shift front out\nshift back out\nstatus\n").code == 1,
          "Opening both source couplings is unfinished rather than a free solution.");
    const auto selector = play({"play", "selector"}, "shift front out\nstatus\nshift back out\nstatus\nshift front in\nquit\n");
    check(selector.code == 0 && selector.text.find("Hub output: rotating -1/1.") != std::string::npos &&
          selector.text.find("Hub output: unpowered 0/1.") != std::string::npos &&
          selector.text.find("Hub output: rotating 1/1.") != std::string::npos,
          "The caller exposes wrong direction, disconnected output and corrected forward drive in the same retained layout.");
    const auto malformed = play({"play", "branch"}, "shift lower out extra\nshift lower sideways\nshift wheel out\nquit extra\nstatus\n");
    check(malformed.code == 1 && malformed.text.find("Shifted") == std::string::npos &&
          malformed.text.find("Coupling lower is in at 4,0,4.") != std::string::npos,
          "Malformed/foreign commands cannot change the original coupled layout.");
    const auto long_line = play({"play", "branch"}, "shift lower out" + std::string(600, ' ') + "\nstatus\nshift lower out\n");
    check(long_line.code == 0 && long_line.text.find("command exceeds 512 bytes") != std::string::npos,
          "The caller drains an oversized command and permits an explicit later correction.");
    check(play({"play", "branch"}, "shift lower out").code == 0, "A final command without a newline is executed once.");
    check(play({"play", "branch"}, "").code == 1, "EOF does not invent a solved layout.");
    check(play({"play", "unknown"}, "shift lower out\n").code == 2, "Unknown startup refuses before consuming construction commands.");
    check(play({"play", "branch", "extra"}, "").code == 2, "Extra startup arguments refuse.");
    check(play({"list"}, "").code == 0 && play({"--help"}, "").code == 0, "Catalogue and help remain accessible without a run.");
    std::istringstream input;
    input.setstate(std::ios::badbit);
    std::ostringstream out, errors;
    const std::vector<std::string_view> args{"play", "branch"};
    check(p::workbench(args, input, out, errors) == 2, "An input failure is distinct from unfinished EOF.");
    std::istringstream good;
    out.setstate(std::ios::badbit);
    check(p::workbench(args, good, out, errors) == 2, "An output failure cannot become successful completion.");
}
}  // namespace

int main() {
    try {
        layouts(); axis_and_order(); refusals(); candidate_overflow(); caller();
        std::cout << checks << " sliding-coupling controls passed.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " controls: " << error.what() << '\n';
        return 1;
    }
}
