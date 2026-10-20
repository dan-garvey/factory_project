#include "factory/metering.hpp"

#include <array>
#include <iostream>

namespace m = factory::metering;

int main() {
    const std::array<m::Port, 3> pattern{{0, 0, 1}};
    const m::Wheel wheel{pattern, 2};
    m::Phase phase;
    m::Capacity source = 12;
    std::array<m::Capacity, 2> held{}, delivered{};
    unsigned pauses{};
    // This isolated consumer is the sole owner of its literal fixture holdings.
    // It is not a live World adapter, network command or physical mechanism.
    while (source > 0) {
        const std::array<m::Capacity, 2> free{{1 - held[0], 1 - held[1]}};
        const auto plan = m::prepare(wheel, phase, {true, true, free});
        if (const auto* hold = std::get_if<m::Hold>(&plan)) {
            if (hold->reason != m::Stop::blocked_receiver || hold->phase != phase ||
                held[hold->destination] != 1) return 1;
            ++pauses;
            // A real drain moves the retained item; no reset or free capacity.
            ++delivered[hold->destination];
            --held[hold->destination];
        } else if (const auto* dispatch = std::get_if<m::Dispatch>(&plan)) {
            --source;
            ++held[dispatch->destination];
            phase = dispatch->next;
        } else return 1;
        if (source + held[0] + held[1] + delivered[0] + delivered[1] != 12) return 1;
    }
    for (std::size_t i = 0; i < held.size(); ++i) { delivered[i] += held[i]; held[i] = 0; }
    if (delivered != std::array<m::Capacity, 2>{{8, 4}} || phase != m::Phase{} || pauses == 0) return 1;
    std::cout << "{\"status\":\"pass\",\"evidence\":\"native_headless_metering_fixture\","
                 "\"initial_items\":12,\"port_A_items\":8,\"port_B_items\":4,"
                 "\"source_remaining\":0,\"blocked_strokes\":" << pauses << "}\n";
    return std::cout ? 0 : 1;
}
