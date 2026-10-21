#pragma once

#include "factory/geared_cycle.hpp"

#include <iosfwd>
#include <optional>
#include <span>
#include <string_view>

namespace factory::geared_cycle {
struct Fixture {
    std::vector<mechanics::Part> parts;
    std::vector<mechanics::Drive> sources;
};
[[nodiscard]] std::optional<Fixture> fixture(std::string_view);

// Fixed gear geometry supplies the actual native output rate. The standalone
// caller prints exact phase/tooth events and samples the existing carriage/cam
// at reached integer stops. It neither continuously animates the carriage nor
// processes material. Exit 0 is a valid trace/list, 2 is refusal or stream failure.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::geared_cycle
