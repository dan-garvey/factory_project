#include "factory/cam_windows.hpp"

#include <algorithm>
#include <numeric>
#include <utility>

namespace factory::cam_windows {
namespace k = geared_cycle;
namespace m = mechanisms;
using I = mechanics::Integer;
namespace {
static_assert(k::maximum_denominator <= 1000000 && k::maximum_intervals <= 256);
// All reduced boundary-time denominators divide the native clock's unreduced
// distance, at most rate-numerator * initial phase-denominator. A common grid
// therefore fits this explicit bound; all interval sums stay inside that grid.
constexpr I maximum_grid = k::maximum_intervals * k::maximum_denominator * k::maximum_denominator;
struct GridSpan { I begin, end; };
struct Segment { GridSpan time; I cell; };

Fraction fraction(I numerator, I denominator) noexcept {
    const I divisor = std::gcd(numerator, denominator);
    return {numerator / divisor, denominator / divisor};
}
void append(std::vector<GridSpan>& output, GridSpan span) {
    if (span.begin == span.end) return;
    if (!output.empty() && output.back().end == span.begin) output.back().end = span.end;
    else output.push_back(span);
}
std::optional<bool> active(const m::Slide& slide, I cell, I teeth, m::Cam cam) {
    I wrapped = cell % teeth;
    if (wrapped < 0) wrapped += teeth;
    bool result{};
    if (m::cam_active(slide, {static_cast<m::Tooth>(wrapped)}, cam, result) != m::Error::none) return std::nullopt;
    return result;
}
std::vector<Span> spans(const std::vector<GridSpan>& input, I grid) {
    std::vector<Span> output;
    for (const auto span : input) output.push_back({fraction(span.begin, grid), fraction(span.end, grid)});
    return output;
}
Fraction coverage(const std::vector<GridSpan>& input, I grid) noexcept {
    I total{};
    for (const auto span : input) total += span.end - span.begin;
    return fraction(total, grid);
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::too_many_cams: return "too_many_cams";
        case Error::invalid_id: return "invalid_id";
        case Error::duplicate_id: return "duplicate_id";
        case Error::invalid_cam: return "invalid_cam";
        case Error::clock_refused: return "clock_refused";
        case Error::arithmetic_limit: return "arithmetic_limit";
    }
    return "unknown";
}

Plan prepare(const m::Slide& slide, k::Phase phase, mechanics::Rate rate,
             bool powered, std::span<const Cam> input) {
    m::Tooth count{};
    if (m::cycle_length(slide, count) != m::Error::none || count > static_cast<m::Tooth>(k::maximum_teeth))
        return Refusal{Error::invalid_profile, {}, 0};
    if (input.size() > maximum_cams) return Refusal{Error::too_many_cams, {}, 0};
    std::vector<Cam> cams(input.begin(), input.end());
    for (const auto& cam : cams) {
        if (cam.id == 0) return Refusal{Error::invalid_id, {}, 0};
        bool ignored{};
        if (m::cam_active(slide, {}, cam.lobe, ignored) != m::Error::none)
            return Refusal{Error::invalid_cam, {}, cam.id};
    }
    std::sort(cams.begin(), cams.end(), [](const auto& a, const auto& b) { return a.id < b.id; });
    for (std::size_t i = 1; i < cams.size(); ++i)
        if (cams[i - 1].id == cams[i].id) return Refusal{Error::duplicate_id, {}, cams[i].id};
    auto clock = k::prepare(static_cast<I>(count), phase, rate, powered);
    if (const auto* error = std::get_if<k::Error>(&clock)) return Refusal{Error::clock_refused, *error, 0};
    auto motion = std::get<k::Prepared>(std::move(clock));
    I grid{1};
    for (const auto& crossing : motion.crossings) {
        const I factor = crossing.at.denominator / std::gcd(grid, crossing.at.denominator);
        if (grid > maximum_grid / factor) return Refusal{Error::arithmetic_limit, {}, 0};
        grid *= factor;
    }
    const bool advances = powered && rate.numerator != 0;
    const I direction = rate.numerator < 0 ? -1 : 1;
    I cell = phase.numerator / phase.denominator;
    if (advances && direction < 0 && phase.numerator % phase.denominator == 0) --cell;
    std::vector<Segment> segments;
    I previous{};
    for (const auto& crossing : motion.crossings) {
        const I time = crossing.at.numerator * (grid / crossing.at.denominator);
        segments.push_back({{previous, time}, cell});
        cell += direction;
        previous = time;
    }
    if (previous < grid) segments.push_back({{previous, grid}, cell});
    Prepared result{std::move(motion), advances, {}, {}};
    std::vector<std::vector<GridSpan>> windows;
    for (const auto& cam : cams) {
        const auto start = active(slide, phase.numerator / phase.denominator, static_cast<I>(count), cam.lobe);
        const auto end = active(slide, result.motion.next.numerator / result.motion.next.denominator, static_cast<I>(count), cam.lobe);
        if (!start || !end) return Refusal{Error::invalid_cam, {}, cam.id};
        std::vector<GridSpan> open;
        for (const auto& segment : segments) {
            const auto on = active(slide, segment.cell, static_cast<I>(count), cam.lobe);
            if (!on) return Refusal{Error::invalid_cam, {}, cam.id};
            if (*on) append(open, segment.time);
        }
        result.windows.push_back({cam.id, *start, *end, spans(open, grid), coverage(open, grid)});
        windows.push_back(std::move(open));
    }
    for (std::size_t a = 0; a < windows.size(); ++a) {
        for (std::size_t b = a + 1; b < windows.size(); ++b) {
            std::vector<GridSpan> common;
            std::size_t i{}, j{};
            while (i < windows[a].size() && j < windows[b].size()) {
                const auto first = windows[a][i];
                const auto second = windows[b][j];
                const GridSpan overlap{std::max(first.begin, second.begin), std::min(first.end, second.end)};
                if (overlap.begin < overlap.end) append(common, overlap);
                if (first.end <= second.end) ++i;
                if (second.end <= first.end) ++j;
            }
            if (!common.empty()) result.overlaps.push_back({cams[a].id, cams[b].id, spans(common, grid), coverage(common, grid)});
        }
    }
    return result;
}
}  // namespace factory::cam_windows
