#include "factory/docked_ports.hpp"
#include "factory/cycle.hpp"

#include <iostream>

namespace p = factory::docked_ports;
namespace m = factory::mechanisms;

int main() {
    const m::Slide slide{3, 2, 2};
    const p::Port receiver{{{"receiver", 3}, 0}, {0, 1, 0}, factory::mechanics::Axis::x, -1, p::Mode::fixed, 0, true};
    auto source_at = [&](m::Phase phase, p::Port& source) {
        m::Pose pose;
        if (m::sample(slide, phase, pose) != m::Error::none) return false;
        source = {{{"carrier", 1}, 0}, {static_cast<factory::mechanics::Integer>(pose.numerator), 1, 0},
                  factory::mechanics::Axis::x, 1, p::Mode::moving, 0, true};
        if (pose.stage == m::Stage::dock) { source.mode = p::Mode::dwell; source.remaining = slide.dock - phase.tooth; }
        return true;
    };
    p::Port source;
    if (!source_at({}, source)) return 1;
    const auto start = p::prepare(source, receiver, {true, true, true, 2});
    const auto* stroke = std::get_if<p::Stroke>(&start);
    if (!stroke || stroke->duration != 2 || stroke->available != 3 || stroke->sender != source.reference) return 1;
    if (!source_at({2}, source) || p::prepare(source, receiver, {true, true, true, 2}) !=
        p::Plan{p::Hold{p::Stop::short_dwell, source.reference, receiver.reference}}) return 1;
    if (!source_at({3}, source) || source.anchor != receiver.anchor ||
        p::prepare(source, receiver, {true, true, true, 2}) !=
        p::Plan{p::Hold{p::Stop::moving, source.reference, receiver.reference}}) return 1;
    if (!source_at({}, source) || p::prepare(source, receiver, {true, true, false, 2}) !=
        p::Plan{p::Hold{p::Stop::full_receiver, source.reference, receiver.reference}}) return 1;
    std::cout << "{\"status\":\"pass\",\"evidence\":\"native_docked_port_metadata_fixture\","
                 "\"stroke_ticks\":2,\"initial_window\":3,\"late_dock\":\"short_dwell\","
                 "\"turning_point\":\"moving\",\"full_receiver\":\"full_receiver\"}\n";
    return std::cout ? 0 : 1;
}
