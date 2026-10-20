#include "factory/metering.hpp"

#include <array>
#include <iostream>
#include <limits>

namespace m = factory::metering;
namespace {
int checks{};
int failures{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) { ++failures; std::cerr << "FAIL: " << message << '\n'; }
}

const std::array<m::Port, 3> pattern{{0, 0, 1}};
const m::Wheel wheel{pattern, 2};
const std::array<m::Capacity, 2> open{{1, 1}};

void literal_sequences() {
    const std::array<m::Port, 9> expected{{0, 0, 1, 0, 0, 1, 0, 0, 1}};
    m::Phase phase;
    for (std::size_t i = 0; i < expected.size(); ++i) {
        const auto proposal = m::prepare(wheel, phase, {true, true, open});
        const auto* dispatch = std::get_if<m::Dispatch>(&proposal);
        check(dispatch && dispatch->destination == expected[i] && dispatch->next == m::Phase{(i + 1) % 3},
              "Every literal 2:1 stroke selects its declared port and exact next pocket.");
        check(m::prepare(wheel, phase, {true, true, open}) == proposal,
              "Repeated quoting cannot advance a wheel or consume another item.");
        if (dispatch) phase = dispatch->next;
    }
    check(phase == m::Phase{}, "Three complete revolutions return to the original physical index.");
    const std::array<m::Port, 4> three_ports{{0, 1, 0, 2}};
    const std::array<m::Capacity, 3> room{{1, 1, 1}};
    const std::array<m::Port, 8> expected_three{{0, 1, 0, 2, 0, 1, 0, 2}};
    for (std::size_t i = 0; i < expected_three.size(); ++i) {
        const auto proposal = m::prepare({three_ports, 3}, {i % 4}, {true, true, room});
        check(std::holds_alternative<m::Dispatch>(proposal) &&
              std::get<m::Dispatch>(proposal) == m::Dispatch{expected_three[i], {(i + 1) % 4}},
              "A three-port wheel preserves the literal 2:1:1 physical stroke ordering.");
    }
    std::array<std::uint32_t, 3> counts{{99, 99, 99}};
    check(m::histogram({three_ports, 3}, counts) == m::Error::none &&
          counts == std::array<std::uint32_t, 3>{{2, 1, 1}}, "A full revolution exposes the exact per-port ratio.");
}

void stopped_and_resumed() {
    for (std::uint64_t pocket = 0; pocket < 3; ++pocket) {
        const m::Phase phase{pocket};
        const auto target = pattern[static_cast<std::size_t>(pocket)];
        auto blocked = open;
        blocked[target] = 0;
        for (int i = 0; i < 5; ++i) {
            check(m::prepare(wheel, phase, {false, true, open}) == m::Plan{m::Hold{m::Stop::unpowered, target, phase}},
                  "Power loss holds every phase without introducing catch-up strokes.");
            check(m::prepare(wheel, phase, {true, false, open}) == m::Plan{m::Hold{m::Stop::empty_source, target, phase}},
                  "An empty feeder preserves the next destination rather than indexing an empty pocket.");
            check(m::prepare(wheel, phase, {true, true, blocked}) == m::Plan{m::Hold{m::Stop::blocked_receiver, target, phase}},
                  "A full indexed receiver cannot be skipped in favor of another free port.");
        }
        check(m::prepare(wheel, phase, {true, true, open}) ==
              m::Plan{m::Dispatch{target, {pocket == 2 ? 0 : pocket + 1}}},
              "After draining, replenishing or restoring power, the exact held stroke resumes.");
    }
}

void refusals_and_limits() {
    const std::array<m::Port, 1> invalid_port{{2}};
    const std::array<m::Port, m::maximum_pockets + 1> oversized{};
    const std::array<m::Wheel, 5> invalid{{{{}, 2}, {pattern, 0}, {pattern, m::maximum_ports + 1},
                                         {invalid_port, 2}, {oversized, 1}}};
    for (const auto bad : invalid) {
        std::array<std::uint32_t, 2> counts{{7, 9}};
        check(m::prepare(bad, {}, {false, false, {}}) == m::Plan{m::Error::invalid_wheel},
              "Paused or missing observations cannot hide invalid physical wheel configuration.");
        check(m::histogram(bad, counts) == m::Error::invalid_wheel &&
              counts == std::array<std::uint32_t, 2>{{7, 9}}, "An invalid wheel leaves histogram output unchanged.");
    }
    for (const auto pocket : {std::uint64_t{3}, std::numeric_limits<std::uint64_t>::max()}) {
        check(m::prepare(wheel, {pocket}, {true, true, open}) == m::Plan{m::Error::invalid_phase},
              "A malformed imported pocket index is refused without normalization.");
    }
    const std::array<m::Capacity, 2> negative{{1, -1}};
    check(m::prepare(wheel, {}, {false, false, negative}) == m::Plan{m::Error::invalid_receivers},
          "A negative nonselected receiver is still invalid when the wheel is stopped.");
    check(m::prepare(wheel, {}, {true, true, {}}) == m::Plan{m::Error::invalid_receivers},
          "Missing receiver observations cannot become unlimited free space.");
    std::array<std::uint32_t, 1> short_output{{99}};
    check(m::histogram(wheel, short_output) == m::Error::invalid_output && short_output[0] == 99,
          "A wrong-sized histogram cannot be partly overwritten.");
    std::array<m::Port, m::maximum_pockets> maximum_pattern{};
    std::array<m::Capacity, m::maximum_ports> maximum_room{};
    for (std::size_t i = 0; i < maximum_pattern.size(); ++i) maximum_pattern[i] = i % m::maximum_ports;
    maximum_room.fill(std::numeric_limits<m::Capacity>::max());
    std::array<std::uint32_t, m::maximum_ports> counts{};
    const m::Wheel maximum{maximum_pattern, m::maximum_ports};
    check(m::histogram(maximum, counts) == m::Error::none, "The declared maximum pattern and port count are supported.");
    for (const auto count : counts) check(count == 8, "Maximum-size histogram counters remain exact.");
    check(m::prepare(maximum, {255}, {true, true, maximum_room}) == m::Plan{m::Dispatch{31, {0}}},
          "The last maximum-size pocket wraps safely even with maximum integer receiver capacities.");
}

void finite_custody() {
    m::Capacity source = 12;
    std::array<m::Capacity, 2> held{}, delivered{};
    m::Phase phase;
    unsigned accepted{};
    for (int tick = 0; tick < 48 && source > 0; ++tick) {
        const std::array<m::Capacity, 2> free{{1 - held[0], 1 - held[1]}};
        const auto proposal = m::prepare(wheel, phase, {true, true, free});
        if (const auto* dispatch = std::get_if<m::Dispatch>(&proposal)) {
            const std::array<m::Port, 12> literal{{0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1}};
            check(dispatch->destination == literal[accepted], "Actual accepted transfers keep their full literal 2:1 sequence.");
            --source;
            ++held[dispatch->destination];
            phase = dispatch->next;
            ++accepted;
        } else if (const auto* hold = std::get_if<m::Hold>(&proposal)) {
            check(hold->reason == m::Stop::blocked_receiver && hold->phase == phase && held[hold->destination] == 1,
                  "Backpressure retains the same indexed full receiver and original item.");
            delivered[hold->destination] += held[hold->destination];
            held[hold->destination] = 0;
        } else check(false, "A valid finite consumer cannot receive a malformed-input refusal.");
        check(source + held[0] + held[1] + delivered[0] + delivered[1] == 12,
              "Every accepted, blocked and drained step preserves the one fixture quantity owner.");
    }
    check(source == 0 && accepted == 12 && phase == m::Phase{}, "The finite source ends after four complete metering revolutions.");
    check(held[0] + delivered[0] == 8 && held[1] + delivered[1] == 4,
          "Twelve original items produce the exact eight/four distribution without a refill or lost item.");
    const auto dry = m::prepare(wheel, phase, {true, false, open});
    check(dry == m::Plan{m::Hold{m::Stop::empty_source, 0, phase}}, "Exhaustion preserves the next full-cycle boundary.");
}
}  // namespace

int main() {
    literal_sequences();
    stopped_and_resumed();
    refusals_and_limits();
    finite_custody();
    std::cout << checks << " metering planner checks, " << failures << " failures.\n";
    return failures == 0 ? 0 : 1;
}
