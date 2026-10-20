#include "factory/docked_ports.hpp"

#include <algorithm>

namespace factory::docked_ports {
namespace {
std::optional<Error> invalid(const Port& port) noexcept {
    if (port.reference.entity.id.empty() || port.reference.entity.generation <= 0) return Error::invalid_reference;
    if (static_cast<unsigned>(port.normal_axis) > 2 || (port.normal_sign != 1 && port.normal_sign != -1)) {
        return Error::invalid_geometry;
    }
    for (const auto coordinate : port.anchor) {
        if (coordinate < -mechanics::maximum_coordinate || coordinate > mechanics::maximum_coordinate) return Error::invalid_geometry;
    }
    if (static_cast<unsigned>(port.mode) > static_cast<unsigned>(Mode::moving)) return Error::invalid_phase;
    if ((port.mode == Mode::dwell) != (port.remaining > 0)) return Error::invalid_phase;
    return std::nullopt;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_request: return "invalid_request";
        case Error::invalid_reference: return "invalid_reference";
        case Error::invalid_geometry: return "invalid_geometry";
        case Error::invalid_phase: return "invalid_phase";
        case Error::identity_conflict: return "identity_conflict";
        case Error::same_port: return "same_port";
    }
    return "unknown";
}

const char* stop_name(Stop stop) noexcept {
    switch (stop) {
        case Stop::unpowered: return "unpowered";
        case Stop::moving: return "moving";
        case Stop::misaligned: return "misaligned";
        case Stop::wrong_facing: return "wrong_facing";
        case Stop::closed_gate: return "closed_gate";
        case Stop::short_dwell: return "short_dwell";
        case Stop::empty_source: return "empty_source";
        case Stop::full_receiver: return "full_receiver";
    }
    return "unknown";
}

Plan prepare(const Port& sender, const Port& receiver, const Observation& observation) {
    if (observation.stroke_ticks == 0) return Error::invalid_request;
    if (const auto error = invalid(sender)) return *error;
    if (const auto error = invalid(receiver)) return *error;
    if (sender.reference.entity.id == receiver.reference.entity.id) {
        if (sender.reference.entity.generation != receiver.reference.entity.generation) return Error::identity_conflict;
        if (sender.reference.port == receiver.reference.port) return Error::same_port;
    }
    auto hold = [&](Stop reason) -> Plan { return Hold{reason, sender.reference, receiver.reference}; };
    if (!observation.powered) return hold(Stop::unpowered);
    if (sender.mode == Mode::moving || receiver.mode == Mode::moving) return hold(Stop::moving);
    if (sender.anchor != receiver.anchor) return hold(Stop::misaligned);
    if (sender.normal_axis != receiver.normal_axis || sender.normal_sign != -receiver.normal_sign) return hold(Stop::wrong_facing);
    if (!sender.gate_open || !receiver.gate_open) return hold(Stop::closed_gate);
    std::optional<Tick> available;
    if (sender.mode == Mode::dwell) available = sender.remaining;
    if (receiver.mode == Mode::dwell) available = available ? std::min(*available, receiver.remaining) : receiver.remaining;
    if (available && *available < observation.stroke_ticks) return hold(Stop::short_dwell);
    if (!observation.source_ready) return hold(Stop::empty_source);
    if (!observation.receiver_room) return hold(Stop::full_receiver);
    return Stroke{sender.reference, receiver.reference, observation.stroke_ticks, available};
}
}  // namespace factory::docked_ports
