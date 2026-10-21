#include "factory/worm_pair.hpp"

#include <algorithm>
#include <limits>
#include <numeric>

namespace factory::worm_pair {
namespace g = mechanics;
namespace c = clearance;
namespace k = geared_cycle;
namespace {
static_assert(g::maximum_coordinate > 0 && g::maximum_coordinate <= 1000000);
static_assert(g::maximum_dimension > 0 && g::maximum_dimension <= 4096);
static_assert(k::maximum_intervals > 0 && k::maximum_intervals <= 256);
static_assert(k::maximum_denominator > 0 && k::maximum_denominator <= 1000000);
// Raw coordinates are bounded before differences; all envelope sums fit.
// After native clock admission/reduction, a single starts/teeth mesh keeps
// numerators <= 256*10^6*4096. Neither axis-sign conversion can negate MIN.
static_assert(k::maximum_intervals * k::maximum_denominator * g::maximum_dimension < std::numeric_limits<Integer>::max());
bool bounded(const g::Point& point) {
    return std::all_of(point.begin(), point.end(), [](auto v) { return v >= -g::maximum_coordinate && v <= g::maximum_coordinate; });
}
bool dimension(Integer value) { return value > 0 && value <= g::maximum_dimension; }
std::uint64_t magnitude(Integer value) noexcept {
    const auto bits = static_cast<std::uint64_t>(value);
    return value < 0 ? std::uint64_t{0} - bits : bits;
}
g::Rate reduced(g::Rate rate) noexcept {
    const auto divisor = static_cast<Integer>(std::gcd(magnitude(rate.numerator), static_cast<std::uint64_t>(rate.denominator)));
    return {rate.numerator / divisor, rate.denominator / divisor};
}
std::optional<k::Error> rate_error(g::Rate rate) {
    const auto checked = k::prepare(k::maximum_teeth, {}, rate, false);
    if (const auto* error = std::get_if<k::Error>(&checked)) return *error;
    return {};
}
c::Box bounds(const g::Point& center, std::size_t axis, Integer radius, Integer half_span) {
    c::Box result{center, center};
    for (std::size_t coordinate = 0; coordinate < 3; ++coordinate) {
        const auto extent = coordinate == axis ? half_span : radius;
        result.minimum[coordinate] -= extent;
        result.maximum[coordinate] += extent;
    }
    return result;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_worm: return "invalid_worm";
        case Error::invalid_wheel: return "invalid_wheel";
        case Error::duplicate_id: return "duplicate_id";
        case Error::not_perpendicular: return "not_perpendicular";
        case Error::pitch_gap: return "pitch_gap";
        case Error::outside_worm_face: return "outside_worm_face";
        case Error::outside_wheel_face: return "outside_wheel_face";
        case Error::representation_limit: return "representation_limit";
        case Error::too_many_drives: return "too_many_drives";
        case Error::unknown_part: return "unknown_part";
        case Error::duplicate_drive: return "duplicate_drive";
        case Error::invalid_rate: return "invalid_rate";
        case Error::native_refused: return "native_refused";
        case Error::unsupported_result: return "unsupported_result";
    }
    return "unknown";
}

Result evaluate(const Worm& worm, const Wheel& wheel, std::span<const Drive> drives) {
    if (!worm.id || static_cast<std::size_t>(worm.axis) >= 3 || !bounded(worm.center) || !dimension(worm.radius) ||
        !dimension(worm.half_span) || !dimension(worm.starts) || (worm.pattern != Pattern::positive && worm.pattern != Pattern::negative))
        return Refusal{Error::invalid_worm, worm.id};
    if (!wheel.id || static_cast<std::size_t>(wheel.axis) >= 3 || !bounded(wheel.center) || !dimension(wheel.teeth) || !dimension(wheel.half_width))
        return Refusal{Error::invalid_wheel, wheel.id};
    if (worm.id == wheel.id) return Refusal{Error::duplicate_id, wheel.id};
    const auto a = static_cast<std::size_t>(worm.axis), b = static_cast<std::size_t>(wheel.axis);
    if (a == b) return Refusal{Error::not_perpendicular, wheel.id};
    const auto normal = 3 - a - b;
    const auto gap = wheel.center[normal] - worm.center[normal];
    const auto pitch_gap = worm.radius + wheel.teeth;
    if (gap != pitch_gap && gap != -pitch_gap) return Refusal{Error::pitch_gap, wheel.id};
    const auto worm_offset = wheel.center[a] - worm.center[a], wheel_offset = worm.center[b] - wheel.center[b];
    if (worm_offset <= -worm.half_span || worm_offset >= worm.half_span) return Refusal{Error::outside_worm_face, worm.id};
    if (wheel_offset <= -wheel.half_width || wheel_offset >= wheel.half_width) return Refusal{Error::outside_wheel_face, wheel.id};
    const Integer side = gap > 0 ? 1 : -1;
    auto contact = worm.center;
    contact[a] = wheel.center[a];
    contact[normal] += side * worm.radius;
    g::Point wheel_axis{}, inward_radius{};
    wheel_axis[b] = 1; inward_radius[normal] = -side;
    const auto tangent_sign = wheel_axis[(a + 1) % 3] * inward_radius[(a + 2) % 3] - wheel_axis[(a + 2) % 3] * inward_radius[(a + 1) % 3];
    const auto pattern = static_cast<Integer>(worm.pattern);
    const auto wheel_frame = -pattern * tangent_sign;
    Geometry geometry{worm, wheel, contact,
        {bounds(worm.center, a, worm.radius, worm.half_span), bounds(wheel.center, b, wheel.teeth, wheel.half_width)},
        reduced({pattern * tangent_sign * worm.starts, wheel.teeth})};
    for (std::size_t index = 0; index < 2; ++index) {
        const auto admitted = c::sweep(geometry.pitch_bounds[index], {}, {});
        if (admitted.error != c::Error::none) return Refusal{Error::representation_limit, index == 0 ? worm.id : wheel.id, {}, {}, admitted.error};
    }
    if (drives.size() > 2) return Refusal{Error::too_many_drives};
    std::array<std::optional<g::Rate>, 2> prescribed;
    std::vector<g::Drive> local_drives;
    for (const auto& drive : drives) {
        const auto index = drive.part == worm.id ? 0U : drive.part == wheel.id ? 1U : 2U;
        if (index == 2) return Refusal{Error::unknown_part, drive.part};
        if (prescribed[index]) return Refusal{Error::duplicate_drive, drive.part};
        if (const auto error = rate_error(drive.rate)) return Refusal{Error::invalid_rate, drive.part, *error};
        const auto rate = reduced(drive.rate);
        prescribed[index] = rate;
        local_drives.push_back({index == 0 ? "worm" : "wheel", {rate.numerator * (index == 0 ? 1 : wheel_frame), rate.denominator}});
    }
    // Arithmetic representation only: worm starts, NOT its cylinder radius,
    // occupy the virtual spur tooth count. Real pitch contact was checked above.
    const auto separation = worm.starts + wheel.teeth;
    const std::vector<g::Part> local_parts{
        {"worm", g::Kind::hub, {}, g::Axis::z}, {"worm-shaft", g::Kind::shaft, {}, g::Axis::z, 0, 1},
        {"worm-starts", g::Kind::gear, {}, g::Axis::z, worm.starts},
        {"wheel", g::Kind::hub, {separation, 0, 0}, g::Axis::z}, {"wheel-shaft", g::Kind::shaft, {separation, 0, 0}, g::Axis::z, 0, 1},
        {"wheel-teeth", g::Kind::gear, {separation, 0, 0}, g::Axis::z, wheel.teeth},
    };
    const auto native = g::evaluate(local_parts, local_drives);
    if (!native.accepted()) return Refusal{Error::native_refused, 0, {}, native.error};
    Evaluation result{geometry, {native.motion.at("worm"), native.motion.at("wheel")}, prescribed};
    result.motion[1].rate.numerator *= wheel_frame;
    for (std::size_t index = 0; index < 2; ++index) if (const auto error = rate_error(result.motion[index].rate))
        return Refusal{Error::unsupported_result, index == 0 ? worm.id : wheel.id, *error};
    return result;
}
}  // namespace factory::worm_pair
