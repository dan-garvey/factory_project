#include "factory/planetary.hpp"

#include <limits>
#include <numeric>

namespace factory::planetary {
namespace g = mechanics;
namespace k = geared_cycle;
using I = g::Integer;
namespace {
static_assert(g::maximum_dimension > 0 && g::maximum_dimension <= 4096);
static_assert(k::maximum_denominator > 0 && k::maximum_denominator <= 1000000 && k::maximum_intervals > 0 && k::maximum_intervals <= 256);
constexpr I coefficient_bound = 2 * g::maximum_dimension;
// After normalization, each term is <= weight*speed*common_denominator.
// The sum, its negation and denominator*weight all fit int64 under these bounds.
static_assert(2 * coefficient_bound * k::maximum_intervals * k::maximum_denominator * k::maximum_denominator <= std::numeric_limits<I>::max());
std::uint64_t magnitude(I value) noexcept {
    const auto bits = static_cast<std::uint64_t>(value);
    return value < 0 ? std::uint64_t{0} - bits : bits;
}
Fraction reduced(Fraction rate) noexcept {
    const auto divisor = static_cast<I>(std::gcd(magnitude(rate.numerator), static_cast<std::uint64_t>(rate.denominator)));
    return {rate.numerator / divisor, rate.denominator / divisor};
}
std::optional<k::Error> rate_error(Fraction rate) {
    const auto checked = k::prepare(k::maximum_teeth, {}, rate, false);
    if (const auto* error = std::get_if<k::Error>(&checked)) return *error;
    return {};
}
Fraction infer(const std::array<I, 3>& weights, std::size_t missing, std::size_t first, Fraction a, std::size_t second, Fraction b) {
    const I common = a.denominator / std::gcd(a.denominator, b.denominator) * b.denominator;
    I numerator = -(weights[first] * a.numerator * (common / a.denominator) +
                    weights[second] * b.numerator * (common / b.denominator));
    I denominator = common * weights[missing];
    if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
    return reduced({numerator, denominator});
}
g::Motion motion(Fraction rate) { return {rate.numerator ? g::MotionState::rotating : g::MotionState::stopped, rate}; }
}  // namespace

const char* port_name(Port port) noexcept {
    switch (port) {
        case Port::sun: return "sun";
        case Port::carrier: return "carrier";
        case Port::ring: return "ring";
        case Port::planet: return "planet";
    }
    return "invalid";
}
const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::too_many_constraints: return "too_many_constraints";
        case Error::invalid_port: return "invalid_port";
        case Error::duplicate_port: return "duplicate_port";
        case Error::invalid_rate: return "invalid_rate";
        case Error::underdetermined: return "underdetermined";
        case Error::unsupported_result: return "unsupported_result";
    }
    return "unknown";
}

Result evaluate(const Profile& profile, std::span<const Constraint> constraints) {
    if (profile.sun < 1 || profile.sun > g::maximum_dimension || profile.planet < 1 || profile.planet > g::maximum_dimension ||
        profile.ring < 1 || profile.ring > g::maximum_dimension || profile.ring != profile.sun + 2 * profile.planet)
        return Refusal{Error::invalid_profile, Port::carrier, {}};
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
    std::size_t first = 0;
    while (!prescribed[first]) ++first;
    std::size_t second = first + 1;
    while (!prescribed[second]) ++second;
    const std::size_t missing = 3 - first - second;
    const std::array<I, 3> weights{-profile.sun, profile.sun + profile.ring, -profile.ring};
    const auto derived = infer(weights, missing, first, *prescribed[first], second, *prescribed[second]);
    Evaluation result{Outcome::solved, {}, prescribed};
    // Compare canonical fractions, avoiding a three-denominator product.
    if (prescribed[missing] && *prescribed[missing] != derived) {
        result.outcome = Outcome::stalled;
        for (auto& value : result.motion) value = {g::MotionState::stalled, {0, 1}};
        return result;
    }
    if (const auto error = rate_error(derived)) return Refusal{Error::unsupported_result, static_cast<Port>(missing), *error};
    for (std::size_t index = 0; index < 3; ++index) result.motion[index] = motion(prescribed[index].value_or(derived));
    const std::array<I, 3> planet_mesh{profile.sun, -(profile.sun + profile.planet), profile.planet};
    const auto planet = infer(planet_mesh, 2, 0, result.motion[0].rate, 1, result.motion[1].rate);
    if (const auto error = rate_error(planet)) return Refusal{Error::unsupported_result, Port::planet, *error};
    result.motion[3] = motion(planet);
    return result;
}
}  // namespace factory::planetary
