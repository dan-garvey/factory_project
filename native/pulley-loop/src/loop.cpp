#include "factory/pulley_loop.hpp"

#include <algorithm>

namespace factory::pulley_loop {
namespace g = mechanics;
namespace c = clearance;
namespace p = pulley_pair;
namespace {
static_assert(g::maximum_coordinate > 0 && g::maximum_coordinate <= 1000000);
static_assert(p::maximum_radius <= 128 && p::maximum_half_width <= 64);
// After complete native validation, coordinate differences are <=2e6.
// The sum of two squared distances is <=8e12, far inside int64.
Integer square(Integer n) { return n * n; }
Integer nearest(Integer low, Integer high, Integer left, Integer right) {
    if (high < left) return left - high;
    if (low > right) return low - right;
    return 0;
}
Integer farthest(Integer low, Integer high, Integer left, Integer right) {
    return std::max({Integer{0}, left - low, high - right});
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_loop: return "invalid_loop";
        case Error::unsupported_layout: return "unsupported_layout";
        case Error::parent_refused: return "parent_refused";
        case Error::representation_limit: return "representation_limit";
        case Error::query_refused: return "query_refused";
    }
    return "unknown";
}

Inspection inspect(const Profile& profile, std::span<const c::Obstacle> obstacles) {
    if (profile.half_thickness < 1 || profile.half_thickness >= p::maximum_radius || profile.half_width < 1 || profile.half_width > p::maximum_half_width)
        return Refusal{Error::invalid_loop};
    const auto parent = p::evaluate(profile.transmission, {});
    if (const auto* refusal = std::get_if<p::Refusal>(&parent)) return Refusal{Error::parent_refused, *refusal};
    const auto& pair = std::get<p::Evaluation>(parent).geometry;
    const auto& first = profile.transmission.pulleys[0]; const auto& second = profile.transmission.pulleys[1];
    if (profile.transmission.layout != p::Layout::open || first.radius != second.radius) return Refusal{Error::unsupported_layout};
    if (profile.half_thickness >= first.radius || profile.half_width > first.half_width || profile.half_width > second.half_width) return Refusal{Error::invalid_loop};
    const auto a = static_cast<std::size_t>(first.axis), u = static_cast<std::size_t>(profile.transmission.span), v = 3 - a - u;
    const Integer inner = first.radius - profile.half_thickness, outer = first.radius + profile.half_thickness;
    c::Box bounds = pair.loop_bounds;
    bounds.minimum[a] = first.center[a] - profile.half_width; bounds.maximum[a] = first.center[a] + profile.half_width;
    for (const auto i : {u, v}) {
        bounds.minimum[i] = std::min(first.center[i], second.center[i]) - outer;
        bounds.maximum[i] = std::max(first.center[i], second.center[i]) + outer;
    }
    const auto body = c::sweep(bounds, {}, {});
    if (body.error != c::Error::none) return Refusal{Error::representation_limit, {}, body.error};
    // This call validates the complete set; its filled enclosure is only a
    // validation carrier, not the actual belt. Do not return its false hit.
    const auto validated = c::sweep(bounds, {}, obstacles);
    if (validated.error != c::Error::none) return Refusal{Error::query_refused, {}, validated.error};
    Geometry result{profile, bounds, square(inner), square(outer), {}};
    const auto left = std::min(first.center[u], second.center[u]), right = std::max(first.center[u], second.center[u]);
    for (const auto& obstacle : obstacles) {
        const auto& box = obstacle.box;
        if (box.maximum[a] <= bounds.minimum[a] || box.minimum[a] >= bounds.maximum[a]) continue;
        const auto near_u = nearest(box.minimum[u], box.maximum[u], left, right), far_u = farthest(box.minimum[u], box.maximum[u], left, right);
        const auto near_v = nearest(box.minimum[v], box.maximum[v], first.center[v], first.center[v]);
        const auto far_v = farthest(box.minimum[v], box.maximum[v], first.center[v], first.center[v]);
        const auto minimum = square(near_u) + square(near_v), maximum = square(far_u) + square(far_v);
        if (minimum < result.outer_squared && maximum > result.inner_squared && (!result.contact || obstacle.id < result.contact->obstacle))
            result.contact = Contact{obstacle.id, minimum, maximum};
    }
    return result;
}
}  // namespace factory::pulley_loop
