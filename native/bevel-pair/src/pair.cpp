#include "factory/bevel_pair.hpp"

#include <algorithm>
#include <limits>
#include <numeric>

namespace factory::bevel_pair {
namespace g = mechanics;
namespace c = clearance;
namespace k = geared_cycle;
namespace {
static_assert(g::maximum_coordinate > 0 && g::maximum_coordinate <= 1000000);
static_assert(g::maximum_dimension > 0 && g::maximum_dimension <= 4096);
// Normalized rates have |n| <= 256*10^6. One mesh multiplies by at most
// 4096/1, so neither the global-axis sign change nor the local solver can
// encounter INT64_MIN. Raw INT64_MIN must be validated/reduced BEFORE this.
static_assert(k::maximum_intervals > 0 && k::maximum_intervals <= 256);
static_assert(k::maximum_denominator > 0 && k::maximum_denominator <= 1000000);
static_assert(k::maximum_intervals * k::maximum_denominator * g::maximum_dimension < std::numeric_limits<Integer>::max());
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
bool valid(const Gear& gear) {
    if (!gear.id || static_cast<std::size_t>(gear.axis) >= 3 || gear.teeth < 1 || gear.teeth > g::maximum_dimension) return false;
    return std::all_of(gear.center.begin(), gear.center.end(), [](auto v) { return v >= -g::maximum_coordinate && v <= g::maximum_coordinate; });
}
c::Box bounds(const Gear& gear, const g::Point& apex) {
    c::Box box{gear.center, gear.center};
    const auto axis = static_cast<std::size_t>(gear.axis);
    for (std::size_t coordinate = 0; coordinate < 3; ++coordinate) {
        if (coordinate == axis) {
            box.minimum[coordinate] = std::min(apex[coordinate], gear.center[coordinate]);
            box.maximum[coordinate] = std::max(apex[coordinate], gear.center[coordinate]);
        } else {
            box.minimum[coordinate] -= gear.teeth;
            box.maximum[coordinate] += gear.teeth;
        }
    }
    return box;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_gear: return "invalid_gear";
        case Error::duplicate_id: return "duplicate_id";
        case Error::not_right_angle: return "not_right_angle";
        case Error::skew_axes: return "skew_axes";
        case Error::pitch_mismatch: return "pitch_mismatch";
        case Error::representation_limit: return "representation_limit";
        case Error::too_many_drives: return "too_many_drives";
        case Error::unknown_gear: return "unknown_gear";
        case Error::duplicate_drive: return "duplicate_drive";
        case Error::invalid_rate: return "invalid_rate";
        case Error::native_refused: return "native_refused";
        case Error::unsupported_result: return "unsupported_result";
    }
    return "unknown";
}

Result evaluate(const Gear& first, const Gear& second, std::span<const Drive> drives) {
    for (const auto* gear : {&first, &second}) if (!valid(*gear)) return Refusal{Error::invalid_gear, gear->id};
    if (first.id == second.id) return Refusal{Error::duplicate_id, second.id};
    const auto a = static_cast<std::size_t>(first.axis), b = static_cast<std::size_t>(second.axis);
    if (a == b) return Refusal{Error::not_right_angle, second.id};
    const auto other = 3 - a - b;
    if (first.center[other] != second.center[other]) return Refusal{Error::skew_axes, second.id};
    const auto axial_first = first.center[a] - second.center[a];
    const auto axial_second = second.center[b] - first.center[b];
    if ((axial_first != second.teeth && axial_first != -second.teeth) ||
        (axial_second != first.teeth && axial_second != -first.teeth)) return Refusal{Error::pitch_mismatch, second.id};
    const Integer outward_first = axial_first > 0 ? 1 : -1, outward_second = axial_second > 0 ? 1 : -1;
    auto apex = first.center;
    apex[a] = second.center[a];
    auto contact = second.center;
    contact[a] = first.center[a];
    Geometry geometry{{first, second}, apex, contact, {bounds(first, apex), bounds(second, apex)},
        reduced({-outward_first * outward_second * first.teeth, second.teeth})};
    for (std::size_t index = 0; index < 2; ++index) {
        const auto admitted = c::sweep(geometry.pitch_bounds[index], {}, {});
        if (admitted.error != c::Error::none) return Refusal{Error::representation_limit, geometry.gears[index].id, {}, {}, admitted.error};
    }
    if (drives.size() > 2) return Refusal{Error::too_many_drives};
    std::array<std::optional<g::Rate>, 2> prescribed;
    std::vector<g::Drive> local_drives;
    for (const auto& drive : drives) {
        const auto index = drive.gear == first.id ? 0U : drive.gear == second.id ? 1U : 2U;
        if (index == 2) return Refusal{Error::unknown_gear, drive.gear};
        if (prescribed[index]) return Refusal{Error::duplicate_drive, drive.gear};
        if (const auto error = rate_error(drive.rate)) return Refusal{Error::invalid_rate, drive.gear, *error};
        const auto rate = reduced(drive.rate);
        prescribed[index] = rate;
        local_drives.push_back({index == 0 ? "first" : "second", {rate.numerator * (index == 0 ? outward_first : outward_second), rate.denominator}});
    }
    // Virtual parallel spur axes are the two LOCAL OUTWARD cone axes. Their
    // external-mesh sign maps to global coordinates through each mounting side.
    // Only this explicit, validated bevel constraint uses the representation.
    const auto separation = first.teeth + second.teeth;
    const std::vector<g::Part> local_parts{
        {"first", g::Kind::hub, {}, g::Axis::z},
        {"first-shaft", g::Kind::shaft, {}, g::Axis::z, 0, 1},
        {"first-gear", g::Kind::gear, {}, g::Axis::z, first.teeth},
        {"second", g::Kind::hub, {separation, 0, 0}, g::Axis::z},
        {"second-shaft", g::Kind::shaft, {separation, 0, 0}, g::Axis::z, 0, 1},
        {"second-gear", g::Kind::gear, {separation, 0, 0}, g::Axis::z, second.teeth},
    };
    const auto native = g::evaluate(local_parts, local_drives);
    if (!native.accepted()) return Refusal{Error::native_refused, 0, {}, native.error};
    Evaluation result{geometry, {native.motion.at("first"), native.motion.at("second")}, prescribed};
    for (std::size_t index = 0; index < 2; ++index) {
        auto& motion = result.motion[index];
        motion.rate.numerator *= index == 0 ? outward_first : outward_second;
        if (const auto error = rate_error(motion.rate)) return Refusal{Error::unsupported_result, geometry.gears[index].id, *error};
    }
    return result;
}
}  // namespace factory::bevel_pair
