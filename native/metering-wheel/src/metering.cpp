#include "factory/metering.hpp"

#include <algorithm>
#include <array>

namespace factory::metering {
namespace {
Error validate(const Wheel& wheel) noexcept {
    if (wheel.ports == 0 || wheel.ports > maximum_ports || wheel.pattern.empty() ||
        wheel.pattern.size() > maximum_pockets) return Error::invalid_wheel;
    for (const auto port : wheel.pattern) if (port >= wheel.ports) return Error::invalid_wheel;
    return Error::none;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::invalid_wheel: return "invalid_wheel";
        case Error::invalid_phase: return "invalid_phase";
        case Error::invalid_receivers: return "invalid_receivers";
        case Error::invalid_output: return "invalid_output";
    }
    return "unknown";
}

const char* stop_name(Stop stop) noexcept {
    switch (stop) {
        case Stop::unpowered: return "unpowered";
        case Stop::empty_source: return "empty_source";
        case Stop::blocked_receiver: return "blocked_receiver";
    }
    return "unknown";
}

Plan prepare(const Wheel& wheel, Phase phase, const Observation& observation) noexcept {
    const auto error = validate(wheel);
    if (error != Error::none) return error;
    if (phase.pocket >= wheel.pattern.size()) return Error::invalid_phase;
    if (observation.free_slots.size() != wheel.ports) return Error::invalid_receivers;
    for (const auto free : observation.free_slots) if (free < 0) return Error::invalid_receivers;
    const auto destination = wheel.pattern[static_cast<std::size_t>(phase.pocket)];
    if (!observation.powered) return Hold{Stop::unpowered, destination, phase};
    if (!observation.item_available) return Hold{Stop::empty_source, destination, phase};
    if (observation.free_slots[destination] == 0) return Hold{Stop::blocked_receiver, destination, phase};
    const Phase next{phase.pocket == wheel.pattern.size() - 1 ? 0 : phase.pocket + 1};
    return Dispatch{destination, next};
}

Error histogram(const Wheel& wheel, std::span<std::uint32_t> output) noexcept {
    const auto error = validate(wheel);
    if (error != Error::none) return error;
    if (output.size() != wheel.ports) return Error::invalid_output;
    std::array<std::uint32_t, maximum_ports> counts{};
    for (const auto port : wheel.pattern) ++counts[port];
    std::copy_n(counts.begin(), wheel.ports, output.begin());
    return Error::none;
}
}  // namespace factory::metering
