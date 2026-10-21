#include "factory/geared_cycle.hpp"

#include <numeric>

namespace factory::geared_cycle {
namespace {
std::uint64_t magnitude(Integer value) noexcept {
    const auto bits = static_cast<std::uint64_t>(value);
    return value < 0 ? std::uint64_t{0} - bits : bits;
}
mechanics::Rate reduced(mechanics::Rate rate) noexcept {
    const auto divisor = static_cast<Integer>(std::gcd(magnitude(rate.numerator),
        static_cast<std::uint64_t>(rate.denominator)));
    return {rate.numerator / divisor, rate.denominator / divisor};
}
Integer wrapped(Integer value, Integer period) noexcept {
    const auto remainder = value % period;
    return remainder < 0 ? remainder + period : remainder;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_phase: return "invalid_phase";
        case Error::invalid_rate: return "invalid_rate";
        case Error::rate_limit: return "rate_limit";
        case Error::phase_limit: return "phase_limit";
    }
    return "unknown";
}

Plan prepare(Integer teeth, Phase phase, mechanics::Rate input, bool powered) {
    if (teeth < 1 || teeth > maximum_teeth) return Error::invalid_profile;
    if (phase.denominator < 1 || phase.denominator > maximum_denominator ||
        phase.numerator < 0 || phase.numerator >= teeth * phase.denominator ||
        std::gcd(phase.numerator, phase.denominator) != 1) return Error::invalid_phase;
    if (input.denominator <= 0) return Error::invalid_rate;
    const auto rate = reduced(input);
    if (rate.denominator > maximum_denominator ||
        magnitude(rate.numerator) > static_cast<std::uint64_t>(maximum_intervals * rate.denominator))
        return Error::rate_limit;
    if (!powered || rate.numerator == 0) return Prepared{phase, {}};

    // Validated bounds put every product/sum below 6.6e16, safely inside int64.
    // Reduce only after wrapping; intermediate denominators may exceed the
    // persistent representation bound while the final phase still fits.
    const Integer denominator = phase.denominator * rate.denominator;
    const Integer start = phase.numerator * rate.denominator;
    const Integer distance = rate.numerator * phase.denominator;
    const Integer end = start + distance;
    const auto next = reduced({wrapped(end, teeth * denominator), denominator});
    if (next.denominator > maximum_denominator) return Error::phase_limit;
    Prepared result{{next.numerator, next.denominator}, {}};
    const int direction = distance > 0 ? 1 : -1;
    Integer boundary = direction > 0 ? phase.numerator / phase.denominator + 1
        : (phase.numerator + phase.denominator - 1) / phase.denominator - 1;
    while (direction > 0 ? boundary * denominator <= end : boundary * denominator >= end) {
        const Integer elapsed = direction * (boundary * denominator - start);
        result.crossings.push_back({wrapped(boundary, teeth), direction,
            reduced({elapsed, direction * distance})});
        boundary += direction;
    }
    return result;
}
}  // namespace factory::geared_cycle
