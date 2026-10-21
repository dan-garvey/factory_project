#include "factory/cardan_pair.hpp"

#include <limits>
#include <numeric>

namespace factory::cardan_pair {
namespace g = mechanics;
namespace k = geared_cycle;
namespace {
static_assert(maximum_dial_component > 0 && maximum_dial_component <= 64);
static_assert(maximum_bend_component > 0 && maximum_bend_component <= 32);
static_assert(k::maximum_intervals > 0 && k::maximum_intervals <= 256);
static_assert(k::maximum_denominator > 0 && k::maximum_denominator <= 1000000);
constexpr Integer intermediate_component = maximum_bend_component * maximum_dial_component;
constexpr Integer derivative_bound = 2 * maximum_bend_component * maximum_bend_component * intermediate_component * intermediate_component;
// The first derived primitive dial is at most 32*64 per component. At either
// stage the unreduced derivative numerator/denominator is <= 2*32^2*2048^2.
// Admission/reduction puts |rate.n| <= 256*10^6 BEFORE multiplication. The
// largest product is 2.20e18, within int64; no unchecked raw MIN is negated.
static_assert(derivative_bound <= std::numeric_limits<Integer>::max() / (k::maximum_intervals * k::maximum_denominator));
std::uint64_t magnitude(Integer value) noexcept {
    const auto bits = static_cast<std::uint64_t>(value);
    return value < 0 ? std::uint64_t{0} - bits : bits;
}
g::Rate reduced(g::Rate rate) noexcept {
    const auto divisor = static_cast<Integer>(std::gcd(magnitude(rate.numerator), static_cast<std::uint64_t>(rate.denominator)));
    return {rate.numerator / divisor, rate.denominator / divisor};
}
Dial primitive(Dial dial) noexcept {
    const auto divisor = std::gcd(dial.x, dial.y);
    return {dial.x / divisor, dial.y / divisor};
}
AxisDirection direction(Integer y, Integer z, Integer scale) noexcept {
    const auto divisor = std::gcd(std::gcd(y, z), scale);
    return {y / divisor, z / divisor, scale / divisor};
}
std::optional<k::Error> rate_error(g::Rate rate) {
    const auto checked = k::prepare(k::maximum_teeth, {}, rate, false);
    if (const auto* error = std::get_if<k::Error>(&checked)) return *error;
    return {};
}
bool valid(Bend bend) {
    return bend.cosine > 0 && bend.cosine <= maximum_bend_component && bend.scale > 0 && bend.scale <= maximum_bend_component &&
        bend.sine >= -maximum_bend_component && bend.sine <= maximum_bend_component &&
        bend.cosine * bend.cosine + bend.sine * bend.sine == bend.scale * bend.scale;
}
Diagonal coefficients(const Joint& joint) {
    return joint.mount == Mount::forward ? Diagonal{joint.bend.scale, joint.bend.cosine} : Diagonal{joint.bend.cosine, joint.bend.scale};
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_mount: return "invalid_mount";
        case Error::invalid_dial: return "invalid_dial";
        case Error::invalid_motion: return "invalid_motion";
        case Error::invalid_rate: return "invalid_rate";
        case Error::unsupported_result: return "unsupported_result";
    }
    return "unknown";
}

Result evaluate(const Profile& profile, Dial dial, g::Motion input) {
    for (std::size_t stage = 0; stage < 2; ++stage) {
        const auto& joint = profile.joints[stage];
        if (!valid(joint.bend)) return Refusal{Error::invalid_profile, stage};
        if (joint.mount != Mount::forward && joint.mount != Mount::compensating) return Refusal{Error::invalid_mount, stage};
    }
    if (dial.x < -maximum_dial_component || dial.x > maximum_dial_component || dial.y < -maximum_dial_component || dial.y > maximum_dial_component ||
        (dial.x == 0 && dial.y == 0) || std::gcd(dial.x, dial.y) != 1) return Refusal{Error::invalid_dial};
    if (input.state != g::MotionState::unpowered && input.state != g::MotionState::stopped && input.state != g::MotionState::rotating && input.state != g::MotionState::stalled)
        return Refusal{Error::invalid_motion};
    if (const auto error = rate_error(input.rate)) return Refusal{Error::invalid_rate, 0, *error};
    input.rate = reduced(input.rate);
    if ((input.state == g::MotionState::rotating) != (input.rate.numerator != 0)) return Refusal{Error::invalid_motion};
    const auto& a = profile.joints[0].bend;
    const auto& b = profile.joints[1].bend;
    Evaluation result{profile, {dial, {}, {}}, {input, {}, {}}, {}, direction(a.sine, a.cosine, a.scale),
        direction(a.sine * b.cosine + a.cosine * b.sine, a.cosine * b.cosine - a.sine * b.sine, a.scale * b.scale), {}};
    Diagonal composite;
    for (std::size_t stage = 0; stage < 2; ++stage) {
        const auto map = coefficients(profile.joints[stage]);
        const auto pose = result.dial[stage];
        const Integer numerator = map.x * map.y * (pose.x * pose.x + pose.y * pose.y);
        const Integer denominator = map.x * map.x * pose.x * pose.x + map.y * map.y * pose.y * pose.y;
        result.factors[stage] = reduced({numerator, denominator});
        result.dial[stage + 1] = primitive({map.x * pose.x, map.y * pose.y});
        const auto rate = result.motion[stage].rate;
        const auto next = reduced({rate.numerator * numerator, rate.denominator * denominator});
        if (const auto error = rate_error(next)) return Refusal{Error::unsupported_result, stage + 1, *error};
        result.motion[stage + 1] = {input.state, next};
        composite.x *= map.x;
        composite.y *= map.y;
    }
    const auto divisor = std::gcd(composite.x, composite.y);
    result.composite = {composite.x / divisor, composite.y / divisor};
    return result;
}
}  // namespace factory::cardan_pair
