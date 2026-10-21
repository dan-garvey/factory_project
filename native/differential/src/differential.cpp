#include "factory/differential.hpp"

#include <numeric>

namespace factory::differential {
namespace g = mechanics;
namespace k = geared_cycle;
namespace {
using I = g::Integer;
constexpr std::array<I, 3> weights{-1, 2, -1};
static_assert(k::maximum_denominator <= 1000000 && k::maximum_intervals <= 256);
std::uint64_t magnitude(I value) noexcept {
    const auto bits = static_cast<std::uint64_t>(value);
    return value < 0 ? std::uint64_t{0} - bits : bits;
}
Fraction reduced(Fraction value) noexcept {
    const auto divisor = static_cast<I>(std::gcd(magnitude(value.numerator), static_cast<std::uint64_t>(value.denominator)));
    return {value.numerator / divisor, value.denominator / divisor};
}
std::optional<k::Error> rate_error(Fraction rate) {
    const auto checked = k::prepare(k::maximum_teeth, {}, rate, false);
    if (const auto* error = std::get_if<k::Error>(&checked)) return *error;
    return std::nullopt;
}
Fraction infer(std::size_t missing, std::size_t first, Fraction a, std::size_t second, Fraction b) {
    // Inputs are normalized and within the existing rate bounds. The common
    // denominator is <= 1e12; the weighted numerator is <= 1.024e15. Dividing
    // by the missing coefficient adds at most a factor two to the denominator.
    const I denominator = a.denominator / std::gcd(a.denominator, b.denominator) * b.denominator;
    I numerator = -(weights[first] * a.numerator * (denominator / a.denominator)
                  + weights[second] * b.numerator * (denominator / b.denominator));
    I divisor = denominator * weights[missing];
    if (divisor < 0) { numerator = -numerator; divisor = -divisor; }
    return reduced({numerator, divisor});
}
}  // namespace

const char* port_name(Port port) noexcept {
    switch (port) {
        case Port::left: return "left";
        case Port::carrier: return "carrier";
        case Port::right: return "right";
    }
    return "invalid";
}
const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::too_many_constraints: return "too_many_constraints";
        case Error::invalid_port: return "invalid_port";
        case Error::duplicate_port: return "duplicate_port";
        case Error::invalid_rate: return "invalid_rate";
        case Error::underdetermined: return "underdetermined";
        case Error::unsupported_result: return "unsupported_result";
    }
    return "unknown";
}
Result evaluate(std::span<const Constraint> constraints) {
    if (constraints.size() > 3) return Refusal{Error::too_many_constraints, Port::carrier, {}};
    std::array<std::optional<Fraction>, 3> prescribed;
    for (const auto& constraint : constraints) {
        const auto index = static_cast<std::size_t>(constraint.port);
        if (index >= 3) return Refusal{Error::invalid_port, constraint.port, {}};
        if (prescribed[index]) return Refusal{Error::duplicate_port, constraint.port, {}};
        if (const auto error = rate_error(constraint.rate)) return Refusal{Error::invalid_rate, constraint.port, *error};
        prescribed[index] = reduced(constraint.rate);
    }
    if (constraints.size() < 2) return Refusal{Error::underdetermined, Port::carrier, {}};
    // Canonical port order chooses a stable pair. For three inputs, compare the
    // inferred canonical fraction directly to the third prescription, avoiding
    // a three-denominator product or overflowing rational cross multiplication.
    std::size_t first = 0;
    while (!prescribed[first]) ++first;
    std::size_t second = first + 1;
    while (!prescribed[second]) ++second;
    const std::size_t missing = 3 - first - second;
    const auto derived = infer(missing, first, *prescribed[first], second, *prescribed[second]);
    Evaluation result{Outcome::solved, {}, prescribed};
    if (prescribed[missing] && *prescribed[missing] != derived) {
        result.outcome = Outcome::stalled;
        for (auto& motion : result.motion) motion = {g::MotionState::stalled, {0, 1}};
        return result;
    }
    if (const auto error = rate_error(derived)) return Refusal{Error::unsupported_result, static_cast<Port>(missing), *error};
    for (std::size_t index = 0; index < 3; ++index) {
        const auto rate = prescribed[index].value_or(derived);
        result.motion[index] = {rate.numerator == 0 ? g::MotionState::stopped : g::MotionState::rotating, rate};
    }
    return result;
}
}  // namespace factory::differential
