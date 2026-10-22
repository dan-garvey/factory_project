#include "factory/mechanics.hpp"

#include <algorithm>
#include <deque>
#include <limits>
#include <numeric>
#include <optional>
#include <set>
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
    if (part.kind != Kind::chain_drive && part.relay_axis != Axis::x) return false;
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
        case Kind::gearbox:
            return part.teeth == 0 && part.half_span == 0;
        case Kind::chain_drive:
            return part.teeth == 0 && part.half_span == 0 &&
                   coordinate(part.relay_axis) < 3 && part.relay_axis != part.axis;
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
    if (a.kind == Kind::gearbox || b.kind == Kind::gearbox) return false;
    if (!coaxial(a, b)) return false;
    const auto axis = coordinate(a.axis);
    if (a.kind != Kind::shaft && b.kind != Kind::shaft) {
        // Hubs and cogs have opposing axle faces one construction cell apart.
        // They touch only at the adjacent face, not through a longer gap.
        constexpr Integer cell = 4;
        const auto distance = b.center[axis] - a.center[axis];
        return distance == cell || distance == -cell;
    }
    const auto a_span = a.kind == Kind::shaft ? a.half_span : 0;
    const auto b_span = b.kind == Kind::shaft ? b.half_span : 0;
    // A one-tile shaft and an adjacent hub or cog meet at their tile faces.
    // Existing shaft-to-shaft contact remains based on their literal spans.
    if ((a.kind == Kind::shaft) != (b.kind == Kind::shaft)) {
        const auto shaft_span = a.kind == Kind::shaft ? a_span : b_span;
        const auto distance = b.center[axis] - a.center[axis];
        if (shaft_span == 2 && (distance == 4 || distance == -4)) return true;
    }
    return a.center[axis] - a_span <= b.center[axis] + b_span &&
           b.center[axis] - b_span <= a.center[axis] + a_span;
}

// The canonical gearbox rate is viewed from the positive face of its first
// available axis. Opposing faces reverse, as do positive faces on the second
// available axis. This reproduces Create's directional gearbox modifiers while
// keeping one exact signed rate per placed block.
std::optional<Integer> port_factor(const Part& part, std::size_t face_axis,
                                   Integer face_sign) noexcept {
    if (part.kind == Kind::gearbox) {
        if (face_axis == coordinate(part.axis)) return std::nullopt;
        std::size_t first = 0;
        if (first == coordinate(part.axis)) ++first;
        const Integer axis_factor = face_axis == first ? 1 : -1;
        return axis_factor * face_sign;
    }
    if (part.kind == Kind::chain_drive && face_axis != coordinate(part.axis))
        return std::nullopt;
    if (face_axis != coordinate(part.axis)) return std::nullopt;
    return 1;
}

std::optional<Rate> relay_contact(const Part& a, const Part& b) noexcept {
    std::size_t face_axis = 3;
    Integer face_sign = 0;
    for (std::size_t i = 0; i < 3; ++i) {
        const auto delta = b.center[i] - a.center[i];
        if (delta == 0) continue;
        if (face_axis != 3 || (delta != 4 && delta != -4)) return std::nullopt;
        face_axis = i;
        face_sign = delta > 0 ? 1 : -1;
    }
    if (face_axis == 3) return std::nullopt;
    if (a.kind == Kind::gearbox || b.kind == Kind::gearbox) {
        const auto from = port_factor(a, face_axis, face_sign);
        const auto to = port_factor(b, face_axis, -face_sign);
        if (!from || !to) return std::nullopt;
        return Rate{*from * *to, 1};
    }
    if (a.kind == Kind::chain_drive && b.kind == Kind::chain_drive &&
        a.axis == b.axis && a.relay_axis == b.relay_axis &&
        face_axis == coordinate(a.relay_axis)) return Rate{1, 1};
    return std::nullopt;
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

std::optional<BeltPath> belt_path(const Part& first, const Part& last) {
    constexpr Integer cell = 4;
    constexpr Integer max_tiles = 20;
    if (!valid(first) || !valid(last) || first.kind != Kind::shaft || last.kind != Kind::shaft ||
        first.half_span != 2 || last.half_span != 2 || first.axis != last.axis) return std::nullopt;
    Point delta{}, step{};
    Integer distance = 0;
    std::size_t changed = 0;
    for (std::size_t i = 0; i < 3; ++i) {
        if (first.center[i] % cell != 0 || last.center[i] % cell != 0) return std::nullopt;
        delta[i] = last.center[i] - first.center[i];
        const auto magnitude = delta[i] < 0 ? -delta[i] : delta[i];
        if (magnitude != 0) {
            if (distance != 0 && magnitude != distance) return std::nullopt;
            distance = magnitude;
            ++changed;
            step[i] = delta[i] > 0 ? cell : -cell;
        }
    }
    if (delta[coordinate(first.axis)] != 0 || changed == 0 || changed > 2 ||
        distance / cell + 1 > max_tiles || (first.axis == Axis::y && changed != 1)) return std::nullopt;
    BeltPathKind kind = BeltPathKind::horizontal;
    if (first.axis == Axis::y) kind = BeltPathKind::sideways;
    else if (delta[1] != 0) kind = changed == 1 ? BeltPathKind::vertical : BeltPathKind::inclined;
    BeltPath path{kind, {}};
    for (Integer n = 0; n <= distance / cell; ++n) {
        Point point{};
        for (std::size_t i = 0; i < 3; ++i) point[i] = first.center[i] + n * step[i];
        path.tiles.push_back(point);
    }
    return path;
}

std::optional<int> belt_cargo_direction(const Part& first, const Part& last, Rate rate) {
    const auto path = belt_path(first, last);
    if (!path || rate.denominator <= 0 || path->kind == BeltPathKind::vertical ||
        path->kind == BeltPathKind::sideways) return std::nullopt;
    if (rate.numerator == 0) return 0;
    const auto travel = first.axis == Axis::x ? std::size_t{2} : std::size_t{0};
    const bool positive_world = first.axis == Axis::x ? rate.numerator > 0 : rate.numerator < 0;
    return positive_world == (last.center[travel] > first.center[travel]) ? 1 : -1;
}

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::too_many_parts: return "too_many_parts";
        case Error::invalid_part: return "invalid_part";
        case Error::duplicate_identity: return "duplicate_identity";
        case Error::invalid_drive: return "invalid_drive";
        case Error::invalid_belt: return "invalid_belt";
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

Result evaluate(const std::vector<Part>& input, const std::vector<Drive>& sources,
                const std::vector<BeltSpan>& belts, SourcePolicy source_policy) {
    if (input.size() > maximum_parts) return failure(Error::too_many_parts);
    if (sources.size() > maximum_parts) return failure(Error::invalid_drive);
    if (belts.size() > maximum_parts) return failure(Error::invalid_belt);

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
            if (const auto relay = relay_contact(left, right)) {
                connected = true;
                kind = EngagementKind::relay;
                forward = backward = *relay;
            }
            if (const auto corner = corner_cog_contact(left, right)) {
                connected = true;
                kind = EngagementKind::external_mesh;
                forward = backward = *corner;
            }
            if (left.kind == Kind::gear && right.kind == Kind::gear &&
                left.axis == right.axis &&
                left.center[coordinate(left.axis)] == right.center[coordinate(right.axis)]) {
                // Starter cogs occupy one tile regardless of their ratio label.
                // Their engagement geometry follows Create's cog connections,
                // while adjacent, nonmeshing tiles remain legal to place.
                const bool large_pair = left.teeth == 4 && right.teeth == 4;
                const bool small_pair = left.teeth == 2 && right.teeth == 2;
                const auto distance = radial_squared(left, right);
                const bool mixed_starter_cogs =
                    (left.teeth == 2 && right.teeth == 4) ||
                    (left.teeth == 4 && right.teeth == 2);
                const bool starter_pair = large_pair || small_pair || mixed_starter_cogs;
                const auto sum = starter_pair ? Integer{4} : left.teeth + right.teeth;
                bool diagonal = mixed_starter_cogs;
                for (std::size_t i = 0; i < 3 && diagonal; ++i) {
                    if (i == coordinate(left.axis)) continue;
                    const auto d = right.center[i] - left.center[i];
                    diagonal = d == 4 || d == -4;
                }
                if (distance < sum * sum)
                    return failure(Error::overlapping_gears, left.id);
                if (diagonal || (!large_pair && !mixed_starter_cogs && distance == sum * sum)) {
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

    // Horizontal prototype spans use complete, unobstructed world tiles. A
    // shaft under the belt acts as a pulley; an empty tile carries the belt
    // but does not fabricate a shaft. Shared tiles cannot belong to two belts.
    std::vector<const BeltSpan*> ordered_belts;
    for (const auto& belt : belts) ordered_belts.push_back(&belt);
    std::sort(ordered_belts.begin(), ordered_belts.end(),
              [](const BeltSpan* a, const BeltSpan* b) { return a->id < b->id; });
    std::set<std::string> belt_ids;
    std::set<Point> belt_tiles;
    for (const auto* belt : ordered_belts) {
        if (!valid_identity(belt->id) || !belt_ids.insert(belt->id).second ||
            !indices.contains(belt->first_shaft) || !indices.contains(belt->last_shaft) ||
            belt->first_shaft == belt->last_shaft) return failure(Error::invalid_belt, belt->id);
        const auto* first = parts[indices.at(belt->first_shaft)];
        const auto* last = parts[indices.at(belt->last_shaft)];
        auto path = belt_path(*first, *last);
        if (!path) return failure(Error::invalid_belt, belt->id);
        // Canonical endpoint order keeps engagements stable on every path.
        if (path->tiles.front() > path->tiles.back()) std::reverse(path->tiles.begin(), path->tiles.end());
        std::vector<std::size_t> pulleys;
        for (const auto& point : path->tiles) {
            if (!belt_tiles.insert(point).second) return failure(Error::invalid_belt, belt->id);
            std::optional<std::size_t> pulley;
            for (std::size_t i = 0; i < parts.size(); ++i) {
                if (parts[i]->center != point) continue;
                if (pulley || parts[i]->kind != Kind::shaft || parts[i]->axis != first->axis || parts[i]->half_span != 2)
                    return failure(Error::invalid_belt, belt->id);
                pulley = i;
            }
            if (pulley) pulleys.push_back(*pulley);
        }
        for (std::size_t i = 1; i < pulleys.size(); ++i) {
            const auto a = pulleys[i - 1], b = pulleys[i];
            result.engagements.push_back({parts[a]->id, parts[b]->id, EngagementKind::belt, {1, 1}});
            adjacent[a].push_back({b, {1, 1}});
            adjacent[b].push_back({a, {1, 1}});
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
            const auto drive = drives.find(at);
            if (drive == drives.end()) continue;
            if (source_policy == SourcePolicy::prescribed) { source = at; break; }
            if (!source || drive->second.numerator != 0) source = at;
            if (drive->second.numerator != 0) break;
        }
        std::vector<std::optional<Rate>> rates(parts.size());
        bool conflict = false;
        auto state = MotionState::unpowered;
        if (source) {
            const auto propagate = [&](std::size_t driver) -> std::optional<std::size_t> {
                std::fill(rates.begin(), rates.end(), std::nullopt);
                rates[driver] = drives.at(driver);
                pending.clear();
                pending.push_back(driver);
                while (!pending.empty()) {
                    const auto at = pending.front();
                    pending.pop_front();
                    for (const auto& link : adjacent[at]) {
                        Rate expected;
                        if (!multiply(*rates[at], link.multiplier, expected)) return link.to;
                        if (rates[link.to]) {
                            conflict = conflict || *rates[link.to] != expected;
                        } else {
                            rates[link.to] = expected;
                            pending.push_back(link.to);
                        }
                    }
                }
                return std::nullopt;
            };
            if (const auto overflow = propagate(*source)) return failure(Error::rate_overflow, parts[*overflow]->id);
            // Compare each source with the rate required at its own shaft. A
            // stronger source in the same direction drives the entire train;
            // zero-speed sources can be back-driven. Cross products are exact.
            __extension__ using Wide = unsigned __int128;
            for (const auto at : component) {
                const auto drive = drives.find(at);
                if (drive == drives.end()) continue;
                if (source_policy == SourcePolicy::prescribed) {
                    conflict = conflict || drive->second != *rates[at];
                    continue;
                }
                if (drive->second.numerator == 0) continue;
                const auto expected = *rates[at];
                if ((drive->second.numerator < 0) != (expected.numerator < 0)) {
                    conflict = true;
                    continue;
                }
                if (Wide{magnitude(drive->second.numerator)} * static_cast<Wide>(expected.denominator) >
                    Wide{magnitude(expected.numerator)} * static_cast<Wide>(drive->second.denominator)) {
                    source = at;
                    if (const auto overflow = propagate(at)) return failure(Error::rate_overflow, parts[*overflow]->id);
                }
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
