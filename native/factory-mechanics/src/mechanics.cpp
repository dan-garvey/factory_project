#include "factory/mechanics.hpp"

#include <algorithm>
#include <deque>
#include <limits>
#include <numeric>
#include <optional>
#include <utility>

namespace factory::mechanics {
namespace {

std::size_t coordinate(Axis axis) noexcept {
    switch (axis) {
        case Axis::x: return 0;
        case Axis::y: return 1;
        case Axis::z: return 2;
    }
    return 3;
}

bool valid_identity(const std::string& value) noexcept {
    return !value.empty() && value.size() <= 128 &&
           value.find('\0') == std::string::npos;
}

Result failure(Error error, const std::string& subject = {}) {
    Result result;
    result.error = error;
    // Never allocate a diagnostic copy of an already rejected identifier.
    if (valid_identity(subject)) result.subject = subject;
    return result;
}

std::uint64_t magnitude(Integer number) noexcept {
    const auto bits = static_cast<std::uint64_t>(number);
    return number < 0 ? std::uint64_t{0} - bits : bits;
}

Rate normalized(Rate rate) noexcept {
    const auto divisor = std::gcd(magnitude(rate.numerator),
                                  static_cast<std::uint64_t>(rate.denominator));
    const auto signed_divisor = static_cast<Integer>(divisor);
    return {rate.numerator / signed_divisor, rate.denominator / signed_divisor};
}

bool multiply_integer(Integer a, Integer b, Integer& result) noexcept {
    constexpr auto low = std::numeric_limits<Integer>::min();
    constexpr auto high = std::numeric_limits<Integer>::max();
    if (a == 0 || b == 0) { result = 0; return true; }
    if (a > 0) {
        if ((b > 0 && a > high / b) || (b < 0 && b < low / a)) return false;
    } else {
        if ((b > 0 && a < low / b) || (b < 0 && a < high / b)) return false;
    }
    result = a * b;
    return true;
}

bool multiply(Rate a, Rate b, Rate& result) noexcept {
    if (a.numerator == 0 || b.numerator == 0) { result = {}; return true; }
    // Cross-cancel before either multiplication. Never negate INT64_MIN.
    const auto first = static_cast<Integer>(
        std::gcd(magnitude(a.numerator), static_cast<std::uint64_t>(b.denominator)));
    const auto second = static_cast<Integer>(
        std::gcd(magnitude(b.numerator), static_cast<std::uint64_t>(a.denominator)));
    a.numerator /= first;
    b.denominator /= first;
    b.numerator /= second;
    a.denominator /= second;
    Integer numerator{}, denominator{};
    if (!multiply_integer(a.numerator, b.numerator, numerator) ||
        !multiply_integer(a.denominator, b.denominator, denominator)) return false;
    result = normalized({numerator, denominator});
    return true;
}

bool valid(const Part& part) noexcept {
    if (!valid_identity(part.id) || coordinate(part.axis) >= 3) return false;
    for (const auto value : part.center)
        if (value < -maximum_coordinate || value > maximum_coordinate) return false;
    switch (part.kind) {
        case Kind::hub: return part.teeth == 0 && part.half_span == 0;
        case Kind::gear:
            return part.teeth > 0 && part.teeth <= maximum_dimension && part.half_span == 0;
        case Kind::shaft: {
            if (part.teeth != 0 || part.half_span < 1 ||
                part.half_span > maximum_dimension) return false;
            const auto axial = part.center[coordinate(part.axis)];
            return axial >= -maximum_coordinate + part.half_span &&
                   axial <= maximum_coordinate - part.half_span;
        }
    }
    return false;
}

bool coaxial(const Part& a, const Part& b) noexcept {
    if (a.axis != b.axis) return false;
    const auto axis = coordinate(a.axis);
    for (std::size_t i = 0; i < 3; ++i)
        if (i != axis && a.center[i] != b.center[i]) return false;
    return true;
}

bool shaft_contact(const Part& a, const Part& b) noexcept {
    if (a.kind != Kind::shaft && b.kind != Kind::shaft) return false;
    if (!coaxial(a, b)) return false;
    const auto axis = coordinate(a.axis);
    const auto a_span = a.kind == Kind::shaft ? a.half_span : 0;
    const auto b_span = b.kind == Kind::shaft ? b.half_span : 0;
    return a.center[axis] - a_span <= b.center[axis] + b_span &&
           b.center[axis] - b_span <= a.center[axis] + a_span;
}

// Create-style large cogwheels meet across one construction cell on each of
// their two perpendicular axes. The sign is expressed in the shared positive
// coordinate-axis convention, so it is independent of which cog is visited first.
std::optional<Rate> corner_cog_contact(const Part& a, const Part& b) noexcept {
    constexpr Integer large_cog = 4;
    constexpr Integer cell = 4;
    if (a.kind != Kind::gear || b.kind != Kind::gear || a.teeth != large_cog ||
        b.teeth != large_cog || a.axis == b.axis) return std::nullopt;
    const auto axis_a = coordinate(a.axis);
    const auto axis_b = coordinate(b.axis);
    const auto da = b.center[axis_a] - a.center[axis_a];
    const auto db = b.center[axis_b] - a.center[axis_b];
    if ((da != cell && da != -cell) || (db != cell && db != -cell)) return std::nullopt;
    const auto other_axis = 3 - axis_a - axis_b;
    if (a.center[other_axis] != b.center[other_axis]) return std::nullopt;
    return Rate{(da > 0) == (db > 0) ? 1 : -1, 1};
}

Integer radial_squared(const Part& a, const Part& b) noexcept {
    Integer result = 0;
    const auto axis = coordinate(a.axis);
    for (std::size_t i = 0; i < 3; ++i) {
        if (i == axis) continue;
        const auto difference = a.center[i] - b.center[i];
        result += difference * difference;
    }
    return result;
}

struct Link {
    std::size_t to;
    Rate multiplier;
};

}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::too_many_parts: return "too_many_parts";
        case Error::invalid_part: return "invalid_part";
        case Error::duplicate_identity: return "duplicate_identity";
        case Error::invalid_drive: return "invalid_drive";
        case Error::overlapping_gears: return "overlapping_gears";
        case Error::rate_overflow: return "rate_overflow";
    }
    return "unknown";
}

const char* motion_state_name(MotionState state) noexcept {
    switch (state) {
        case MotionState::unpowered: return "unpowered";
        case MotionState::stopped: return "stopped";
        case MotionState::rotating: return "rotating";
        case MotionState::stalled: return "stalled";
    }
    return "unknown";
}

Result evaluate(const std::vector<Part>& input, const std::vector<Drive>& sources) {
    if (input.size() > maximum_parts) return failure(Error::too_many_parts);
    if (sources.size() > maximum_parts) return failure(Error::invalid_drive);

    std::vector<const Part*> parts;
    parts.reserve(input.size());
    for (const auto& part : input) {
        if (!valid(part)) return failure(Error::invalid_part, part.id);
        parts.push_back(&part);
    }
    std::sort(parts.begin(), parts.end(),
              [](const Part* a, const Part* b) { return a->id < b->id; });
    std::map<std::string, std::size_t> indices;
    for (std::size_t i = 0; i < parts.size(); ++i)
        if (!indices.emplace(parts[i]->id, i).second)
            return failure(Error::duplicate_identity, parts[i]->id);

    std::map<std::size_t, Rate> drives;
    for (const auto& source : sources) {
        if (!valid_identity(source.hub)) return failure(Error::invalid_drive);
        const auto found = indices.find(source.hub);
        if (found == indices.end() || parts[found->second]->kind != Kind::hub ||
            source.rate.denominator <= 0)
            return failure(Error::invalid_drive, source.hub);
        if (!drives.emplace(found->second, normalized(source.rate)).second)
            return failure(Error::invalid_drive, source.hub);
    }

    Result result;
    std::vector<std::vector<Link>> adjacent(parts.size());
    for (std::size_t a = 0; a < parts.size(); ++a) {
        for (std::size_t b = a + 1; b < parts.size(); ++b) {
            const auto& left = *parts[a];
            const auto& right = *parts[b];
            Rate forward{1, 1}, backward{1, 1};
            auto kind = EngagementKind::coaxial_shaft;
            bool connected = shaft_contact(left, right);
            if (const auto corner = corner_cog_contact(left, right)) {
                connected = true;
                kind = EngagementKind::external_mesh;
                forward = backward = *corner;
            }
            if (left.kind == Kind::gear && right.kind == Kind::gear &&
                left.axis == right.axis &&
                left.center[coordinate(left.axis)] == right.center[coordinate(right.axis)]) {
                const auto sum = left.teeth + right.teeth;
                const auto distance = radial_squared(left, right);
                if (distance < sum * sum)
                    return failure(Error::overlapping_gears, left.id);
                if (distance == sum * sum) {
                    connected = true;
                    kind = EngagementKind::external_mesh;
                    forward = normalized({-left.teeth, right.teeth});
                    backward = normalized({-right.teeth, left.teeth});
                }
            }
            if (!connected) continue;
            result.engagements.push_back({left.id, right.id, kind, forward});
            adjacent[a].push_back({b, forward});
            adjacent[b].push_back({a, backward});
        }
    }

    std::vector<bool> visited(parts.size(), false);
    for (std::size_t root = 0; root < parts.size(); ++root) {
        if (visited[root]) continue;
        std::deque<std::size_t> pending{root};
        std::vector<std::size_t> component;
        visited[root] = true;
        while (!pending.empty()) {
            const auto at = pending.front();
            pending.pop_front();
            component.push_back(at);
            for (const auto& link : adjacent[at]) {
                if (visited[link.to]) continue;
                visited[link.to] = true;
                pending.push_back(link.to);
            }
        }
        std::sort(component.begin(), component.end());
        std::optional<std::size_t> source;
        for (const auto at : component) {
            if (drives.contains(at)) { source = at; break; }
        }
        std::vector<std::optional<Rate>> rates(parts.size());
        bool conflict = false;
        auto state = MotionState::unpowered;
        if (source) {
            rates[*source] = drives.at(*source);
            pending.push_back(*source);
            while (!pending.empty()) {
                const auto at = pending.front();
                pending.pop_front();
                for (const auto& link : adjacent[at]) {
                    Rate expected;
                    if (!multiply(*rates[at], link.multiplier, expected))
                        return failure(Error::rate_overflow, parts[link.to]->id);
                    if (rates[link.to]) {
                        conflict = conflict || *rates[link.to] != expected;
                    } else {
                        rates[link.to] = expected;
                        pending.push_back(link.to);
                    }
                }
            }
            for (const auto at : component) {
                const auto drive = drives.find(at);
                if (drive != drives.end() && drive->second != *rates[at]) conflict = true;
            }
            state = conflict ? MotionState::stalled
                  : drives.at(*source).numerator == 0 ? MotionState::stopped
                  : MotionState::rotating;
        }
        Component summary;
        summary.state = state;
        for (const auto at : component) {
            summary.parts.push_back(parts[at]->id);
            const auto rate = state == MotionState::rotating ? *rates[at] : Rate{};
            result.motion.emplace(parts[at]->id, Motion{state, rate});
        }
        result.components.push_back(std::move(summary));
    }
    return result;
}

}  // namespace factory::mechanics
