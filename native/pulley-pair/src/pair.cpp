#include "factory/pulley_pair.hpp"

#include <algorithm>
#include <numeric>

namespace factory::pulley_pair {
namespace g = mechanics;
namespace s = slider_crank;
namespace c = clearance;
namespace k = geared_cycle;
namespace {
static_assert(g::maximum_coordinate <= 1000000 && maximum_separation <= scotch_yoke::maximum_direction_scale);
static_assert(maximum_radius <= 128 && maximum_half_width <= g::maximum_dimension);
static_assert(k::maximum_intervals <= 256 && k::maximum_denominator <= 1000000);
// Raw guards precede products: tangent bases <256.1e6, radicals <=2^30.
// Reduced native prescription numerators <=256e6; virtual mesh factors <=128.
// Native arithmetic and downstream clock validation reject unsupported rates.
std::uint64_t magnitude(Integer n) { const auto bits = static_cast<std::uint64_t>(n); return n < 0 ? std::uint64_t{0} - bits : bits; }
g::Rate reduced(g::Rate rate) {
    const auto divisor = static_cast<Integer>(std::gcd(magnitude(rate.numerator), static_cast<std::uint64_t>(rate.denominator)));
    return {rate.numerator / divisor, rate.denominator / divisor};
}
std::optional<k::Error> rate_error(g::Rate rate) {
    const auto checked = k::prepare(k::maximum_teeth, {}, rate, false);
    if (const auto* error = std::get_if<k::Error>(&checked)) return *error;
    return {};
}
bool valid(const Pulley& p) {
    return p.id && static_cast<std::size_t>(p.axis) < 3 && p.radius >= 1 && p.radius <= maximum_radius &&
        p.half_width >= 1 && p.half_width <= maximum_half_width &&
        std::all_of(p.center.begin(), p.center.end(), [](Integer n) { return n >= -g::maximum_coordinate && n <= g::maximum_coordinate; });
}
c::Box bounds(const Pulley& p) {
    c::Box result{p.center, p.center};
    for (std::size_t i = 0; i < 3; ++i) {
        const auto reach = i == static_cast<std::size_t>(p.axis) ? p.half_width : p.radius;
        result.minimum[i] -= reach; result.maximum[i] += reach;
    }
    return result;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_pulley: return "invalid_pulley";
        case Error::duplicate_id: return "duplicate_id";
        case Error::invalid_layout: return "invalid_layout";
        case Error::invalid_span: return "invalid_span";
        case Error::nonparallel: return "nonparallel";
        case Error::skew: return "skew";
        case Error::spacing_limit: return "spacing_limit";
        case Error::pitch_overlap: return "pitch_overlap";
        case Error::too_many_drives: return "too_many_drives";
        case Error::unknown_pulley: return "unknown_pulley";
        case Error::duplicate_drive: return "duplicate_drive";
        case Error::invalid_rate: return "invalid_rate";
        case Error::representation_limit: return "representation_limit";
        case Error::native_refused: return "native_refused";
        case Error::unsupported_result: return "unsupported_result";
    }
    return "unknown";
}

Result evaluate(const Profile& p, std::span<const Drive> drives) {
    for (const auto& pulley : p.pulleys) if (!valid(pulley)) return Refusal{Error::invalid_pulley, pulley.id};
    const auto& first = p.pulleys[0]; const auto& second = p.pulleys[1];
    if (first.id == second.id) return Refusal{Error::duplicate_id, second.id};
    if (p.layout != Layout::open && p.layout != Layout::crossed) return Refusal{Error::invalid_layout};
    const auto a = static_cast<std::size_t>(first.axis), u = static_cast<std::size_t>(p.span);
    if (u >= 3 || u == a) return Refusal{Error::invalid_span};
    if (drives.size() > 2) return Refusal{Error::too_many_drives};
    std::array<std::optional<g::Rate>, 2> prescribed;
    for (const auto& drive : drives) {
        const auto side = drive.pulley == first.id ? 0U : drive.pulley == second.id ? 1U : 2U;
        if (side == 2) return Refusal{Error::unknown_pulley, drive.pulley};
        if (prescribed[side]) return Refusal{Error::duplicate_drive, drive.pulley};
        if (const auto error = rate_error(drive.rate)) return Refusal{Error::invalid_rate, drive.pulley, *error};
        prescribed[side] = reduced(drive.rate);
    }
    if (first.axis != second.axis) return Refusal{Error::nonparallel, second.id};
    const auto v = 3 - a - u;
    if (first.center[a] != second.center[a] || first.center[v] != second.center[v]) return Refusal{Error::skew, second.id};
    const auto signed_span = second.center[u] - first.center[u];
    if (!signed_span || signed_span < -maximum_separation || signed_span > maximum_separation) return Refusal{Error::spacing_limit, second.id};
    const Integer distance = signed_span > 0 ? signed_span : -signed_span, span_sign = signed_span > 0 ? 1 : -1;
    if (distance <= first.radius + second.radius) return Refusal{Error::pitch_overlap, second.id};
    const Integer normal_second = p.layout == Layout::open ? 1 : -1;
    const auto delta = first.radius - normal_second * second.radius, radical = distance * distance - delta * delta;
    Geometry geometry{p, {}, distance, radical, reduced({normal_second * first.radius, second.radius}), {bounds(first), bounds(second)}, {}};
    for (std::size_t side = 0; side < 2; ++side) {
        if (c::sweep(geometry.pitch_bounds[side], {}, {}).error != c::Error::none) return Refusal{Error::representation_limit, p.pulleys[side].id};
        for (std::size_t i = 0; i < 3; ++i) {
            geometry.loop_bounds.minimum[i] = std::min(geometry.pitch_bounds[0].minimum[i], geometry.pitch_bounds[1].minimum[i]);
            geometry.loop_bounds.maximum[i] = std::max(geometry.pitch_bounds[0].maximum[i], geometry.pitch_bounds[1].maximum[i]);
        }
        const auto& pulley = p.pulleys[side];
        const Integer sign = side ? normal_second : 1, handed = ((a + 1) % 3 == u ? 1 : -1) * span_sign;
        for (std::size_t strand = 0; strand < 2; ++strand) {
            auto& point = geometry.strands[strand][side];
            for (std::size_t i = 0; i < 3; ++i) point[i] = {pulley.center[i], 0, 1};
            point[u] = {pulley.center[u] * distance + span_sign * sign * pulley.radius * delta, 0, distance};
            point[v] = {pulley.center[v] * distance, pulley.radius * pulley.radius * radical, distance,
                sign * handed * (strand ? -1 : 1) > 0 ? s::Branch::positive : s::Branch::negative};
            for (const auto& coordinate : point) if (!std::holds_alternative<s::Order>(s::compare_to_grid(coordinate, 0))) return Refusal{Error::representation_limit, pulley.id};
        }
    }
    std::vector<g::Drive> local_drives;
    // Two virtual EXTERNAL spur gears give a minus sign. Reversing the local
    // second axis for an open belt maps that constraint to SAME global sense.
    // This explicit ideal belt constraint does not connect bare separated Parts.
    for (std::size_t side = 0; side < 2; ++side) if (prescribed[side]) {
        const auto rate = *prescribed[side];
        local_drives.push_back({side ? "second" : "first", {rate.numerator * (side ? -normal_second : 1), rate.denominator}});
    }
    const auto separation = first.radius + second.radius;
    const std::vector<g::Part> local_parts{
        {"first", g::Kind::hub, {}, g::Axis::z}, {"first-shaft", g::Kind::shaft, {}, g::Axis::z, 0, 1}, {"first-gear", g::Kind::gear, {}, g::Axis::z, first.radius},
        {"second", g::Kind::hub, {separation, 0, 0}, g::Axis::z}, {"second-shaft", g::Kind::shaft, {separation, 0, 0}, g::Axis::z, 0, 1}, {"second-gear", g::Kind::gear, {separation, 0, 0}, g::Axis::z, second.radius},
    };
    const auto native = g::evaluate(local_parts, local_drives);
    if (!native.accepted()) return Refusal{Error::native_refused, 0, {}, native.error};
    Evaluation result{geometry, {native.motion.at("first"), native.motion.at("second")}, prescribed};
    result.motion[1].rate.numerator *= -normal_second;
    for (std::size_t side = 0; side < 2; ++side) if (const auto error = rate_error(result.motion[side].rate)) return Refusal{Error::unsupported_result, p.pulleys[side].id, *error};
    return result;
}
}  // namespace factory::pulley_pair
