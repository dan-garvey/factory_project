#include "factory/cam_windows.hpp"
#include "factory/cam_windows_workbench.hpp"

#include <algorithm>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>
#include <stdexcept>

namespace w = factory::cam_windows;
namespace k = factory::geared_cycle;
namespace m = factory::mechanisms;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
w::Prepared accepted(w::Plan plan) {
    check(std::holds_alternative<w::Prepared>(plan), "The complete representable geometric bank is accepted.");
    return std::get<w::Prepared>(std::move(plan));
}
void refused(const w::Plan& plan, w::Error reason, w::Id id = 0) {
    check(std::holds_alternative<w::Refusal>(plan), "Invalid input returns no phase or partial follower schedules.");
    const auto& actual = std::get<w::Refusal>(plan);
    check(actual.reason == reason && actual.subject == id, "The exact refusal category and opaque subject are preserved.");
}
g::Rate fraction(I n, I d) { const I divisor = std::gcd(n, d); return {n / divisor, d / divisor}; }
const m::Slide slide{2, 3, 2};
const w::Cam work{1, {5, 2}};
void literals() {
    const auto turn = accepted(w::prepare(slide, {}, {10, 1}, true, {&work, 1}));
    check(turn.motion.next == k::Phase{} && turn.shaft_advances && turn.motion.crossings.size() == 10,
          "A complete revolution advances the shaft even when its endpoint equals its start.");
    check(turn.windows == std::vector<w::Window>{{1, false, false, {{{1, 2}, {7, 10}}}, {1, 5}}},
          "The entire geometric opening between two off endpoints is retained at literal half through seven-tenths.");
    const auto reverse = accepted(w::prepare(slide, {}, {-10, 1}, true, {&work, 1}));
    check(reverse.windows == std::vector<w::Window>{{1, false, false, {{{3, 10}, {1, 2}}}, {1, 5}}},
          "Reverse traversal has the same exact coverage with its own chronological opening.");
    const auto arrive = accepted(w::prepare(slide, {4, 1}, {1, 1}, true, {&work, 1}));
    check(arrive.windows == std::vector<w::Window>{{1, false, true, {}, {0, 1}}},
          "An on-state only at the destination instant contributes no duration.");
    const auto leave = accepted(w::prepare(slide, {5, 1}, {-1, 1}, true, {&work, 1}));
    check(leave.windows == std::vector<w::Window>{{1, true, false, {}, {0, 1}}},
          "Reverse departure from the lower edge does not turn its initial on instant into work time.");
    const auto enter_reverse = accepted(w::prepare(slide, {7, 1}, {-1, 1}, true, {&work, 1}));
    check(enter_reverse.windows == std::vector<w::Window>{{1, false, true, {{{0, 1}, {1, 1}}}, {1, 1}}},
          "Reverse entry immediately after t=0 can fill the open interval while the initial point is off.");
    const auto held = accepted(w::prepare(slide, {5, 1}, {5, 2}, false, {&work, 1}));
    check(!held.shaft_advances && held.motion.next == k::Phase{5, 1} && held.motion.crossings.empty() &&
          held.windows == std::vector<w::Window>{{1, true, true, {{{0, 1}, {1, 1}}}, {1, 1}}},
          "A paused open follower stays geometrically open without advancing or granting work.");
    const w::Cam wrapping{7, {9, 3}};
    check(accepted(w::prepare(slide, {}, {10, 1}, true, {&wrapping, 1})).windows ==
        std::vector<w::Window>{{7, true, true, {{{0, 1}, {1, 5}}, {{9, 10}, {1, 1}}}, {3, 10}}},
        "A wrapping lobe retains two chronological spans instead of bridging its closed gap.");
    const w::Cam pair[]{{9, {3, 4}}, {2, {5, 4}}};
    const auto overlapping = accepted(w::prepare(slide, {}, {10, 1}, true, pair));
    check(overlapping.windows[0].id == 2 && overlapping.windows[1].id == 9 &&
          overlapping.overlaps == std::vector<w::Overlap>{{2, 9, {{{1, 2}, {7, 10}}}, {1, 5}}},
          "Positive-duration follower overlap is exact and canonical, while the bank remains accepted.");
    const w::Cam touching[]{{1, {4, 1}}, {2, {5, 1}}};
    check(accepted(w::prepare(slide, {}, {10, 1}, true, touching)).overlaps.empty(),
          "Two windows touching only at an endpoint have no positive-duration overlap.");
    const auto fractional = accepted(w::prepare(slide, {9, 2}, {5, 2}, true, {&work, 1}));
    check(fractional.windows == std::vector<w::Window>{{1, false, false, {{{1, 5}, {1, 1}}}, {4, 5}}},
          "Fractional starting phase preserves the literal four-fifths opening despite two off endpoints.");
}

I wrap(I n, I period) { const I r = n % period; return r < 0 ? r + period : r; }
bool geometry(m::Cam cam, I position24, I period) {
    const I distance = wrap(position24 - static_cast<I>(cam.start) * 24, period * 24);
    return distance < static_cast<I>(cam.width) * 24;
}
std::vector<w::Span> runs(const std::vector<bool>& on) {
    std::vector<w::Span> result;
    const I count = static_cast<I>(on.size());
    for (I start = 0; start < count;) {
        if (!on[static_cast<std::size_t>(start)]) { ++start; continue; }
        I end = start + 1;
        while (end < count && on[static_cast<std::size_t>(end)]) ++end;
        result.push_back({fraction(start, count), fraction(end, count)});
        start = end;
    }
    return result;
}
g::Rate covered(const std::vector<bool>& mask) {
    return fraction(static_cast<I>(std::count(mask.begin(), mask.end(), true)), static_cast<I>(mask.size()));
}
void oracle() {
    std::size_t cases{};
    for (const I period : {I{4}, I{10}}) {
        const m::Slide timing = period == 4 ? m::Slide{1, 1, 1} : slide;
        for (I initial = 0; initial < period * 12; ++initial) {
            const auto initial_fraction = fraction(initial, 12);
            const k::Phase phase{initial_fraction.numerator, initial_fraction.denominator};
            for (const I quanta : {I{-120}, I{-25}, I{-5}, I{-1}, I{0}, I{1}, I{5}, I{25}, I{120}, I{30}}) {
                const bool powered = quanta != 30;
                const bool moving = powered && quanta != 0;
                const I direction = quanta < 0 ? -1 : 1;
                const I count = moving ? (quanta < 0 ? -quanta : quanta) : 1;
                for (I key = 0; key < period; ++key) {
                    for (I width = 0; width <= period; ++width) {
                        const w::Cam first{5, {static_cast<m::Tooth>(key), static_cast<m::Tooth>(width)}};
                        const w::Cam second{2, {static_cast<m::Tooth>((key + period / 2) % period), static_cast<m::Tooth>((width + 1) % (period + 1))}};
                        const w::Cam bank[]{first, second};
                        std::vector<bool> a, b, both;
                        I grid = initial;
                        std::size_t visits{};
                        // Walk independent twelfth-tooth quanta and inspect the
                        // midpoint of each tiny interval in a doubled lattice.
                        // No native clock crossing or cam sampler is reused.
                        for (I tick = 0; tick < count; ++tick) {
                            const I midpoint = wrap(grid * 2 + (moving ? direction : 0), period * 24);
                            a.push_back(geometry(first.lobe, midpoint, period));
                            b.push_back(geometry(second.lobe, midpoint, period));
                            both.push_back(a.back() && b.back());
                            if (moving) {
                                grid = wrap(grid + direction, period * 12);
                                if (grid % 12 == 0) ++visits;
                            }
                        }
                        const auto final_fraction = fraction(grid, 12);
                        const auto actual = accepted(w::prepare(timing, phase, {quanta, 12}, powered, bank));
                        check(actual.shaft_advances == moving && actual.motion.next == k::Phase{final_fraction.numerator, final_fraction.denominator} &&
                              actual.motion.crossings.size() == visits, "The sole phase and every reached tooth agree with the independent lattice walk.");
                        const w::Window expected_first{5, geometry(first.lobe, initial * 2, period), geometry(first.lobe, grid * 2, period), runs(a), covered(a)};
                        const w::Window expected_second{2, geometry(second.lobe, initial * 2, period), geometry(second.lobe, grid * 2, period), runs(b), covered(b)};
                        check(actual.windows == std::vector<w::Window>{expected_second, expected_first},
                              "Every open span, exact endpoint state and coverage matches independent midpoint masks in canonical ID order.");
                        const auto overlap = runs(both);
                        const auto expected_overlap = overlap.empty() ? std::vector<w::Overlap>{}
                            : std::vector<w::Overlap>{{2, 5, overlap, covered(both)}};
                        check(actual.overlaps == expected_overlap, "Pairwise durations and open spans agree with independently intersected masks.");
                        ++cases;
                    }
                }
            }
        }
    }
    check(cases == 141600, "The oracle covers all declared phases, signs, stationary cases and lobe configurations.");
}

void bounds_and_ownership() {
    std::vector<w::Cam> bank;
    for (w::Id id = 16; id > 0; --id) bank.push_back({id, {0, 10}});
    const auto all = accepted(w::prepare(slide, {}, {0, 1}, false, bank));
    check(all.windows.size() == 16 && all.overlaps.size() == 120 && !all.shaft_advances,
          "The complete sixteen-follower bank and all 120 positive-duration pairs are representable.");
    for (const auto& window : all.windows) check(window.coverage == g::Rate{1, 1} && window.active == std::vector<w::Span>{{{0, 1}, {1, 1}}},
        "Every held-open follower retains full geometric coverage.");
    std::reverse(bank.begin(), bank.end());
    const auto reordered = accepted(w::prepare(slide, {}, {0, 1}, false, bank));
    check(all.windows == reordered.windows && all.overlaps == reordered.overlaps, "Changing bank order cannot select a different schedule or pair order.");
    bank.clear();
    check(all.windows.front().id == 1 && all.overlaps.back().first == 15 && all.overlaps.back().second == 16,
          "Output identities and spans stay owned after the input bank is destroyed.");
    const w::Cam disabled{1, {0, 0}};
    const auto empty = accepted(w::prepare(slide, {}, {10, 1}, true, {&disabled, 1}));
    check(empty.windows.front() == w::Window{1, false, false, {}, {0, 1}}, "A disabled lobe contributes neither point geometry nor intervals.");
    const auto none = accepted(w::prepare(slide, {}, {10, 1}, true, {}));
    check(none.motion.crossings.size() == 10 && none.windows.empty() && none.overlaps.empty(), "An empty bank does not disable its independent phase proposal.");
    std::vector<w::Cam> oversized(17, {1, {0, 0}});
    refused(w::prepare(slide, {}, {0, 1}, false, oversized), w::Error::too_many_cams);
    const w::Cam zero{0, {0, 1}};
    refused(w::prepare(slide, {}, {0, 1}, false, {&zero, 1}), w::Error::invalid_id);
    const w::Cam duplicates[]{{7, {0, 0}}, {7, {5, 2}}};
    refused(w::prepare(slide, {}, {1, 1}, true, duplicates), w::Error::duplicate_id, 7);
    const w::Cam invalid[]{{1, {0, 10}}, {99, {0, 11}}};
    refused(w::prepare(slide, {}, {0, 1}, false, invalid), w::Error::invalid_cam, 99);
    const w::Cam invalid_disabled{8, {10, 0}};
    refused(w::prepare(slide, {}, {0, 1}, false, {&invalid_disabled, 1}), w::Error::invalid_cam, 8);
    refused(w::prepare({0, 1, 1}, {}, {1, 1}, true, {}), w::Error::invalid_profile);
    const auto limited = w::prepare(slide, {1, 999983}, {1, 999979}, true, {&work, 1});
    refused(limited, w::Error::clock_refused);
    check(std::get<w::Refusal>(limited).clock_error == k::Error::phase_limit, "The original unsupported phase denominator is preserved without rounding.");
    refused(w::prepare(slide, {}, {1, 0}, false, {&work, 1}), w::Error::clock_refused);
    refused(w::prepare(slide, {2, 4}, {1, 1}, true, {}), w::Error::clock_refused);
    const auto large = accepted(w::prepare(slide, {999999, 1000000}, {255999999, 1000000}, true, {&work, 1}));
    check(large.windows.front().active.size() == 26 && large.windows.front().coverage == fraction(51999998, 255999999) &&
          large.windows.front().active.front() == w::Span{fraction(4000001, 255999999), fraction(6000001, 255999999)},
          "Large native time denominators use a bounded common grid instead of overflowing fraction cross-products.");
    const auto extreme = accepted(w::prepare(slide, {5, 1}, {std::numeric_limits<I>::min(), I{1} << 62}, true, {&work, 1}));
    check(extreme.motion.next == k::Phase{3, 1} && extreme.windows.front().coverage == g::Rate{0, 1},
          "A normalized extreme negative input retains reverse edge semantics without signed negation.");
    const w::Cam last{17, {65535, 1}};
    const auto maximum = accepted(w::prepare({65533, 1, 1}, {65535, 1}, {256, 1}, true, {&last, 1}));
    check(maximum.motion.next == k::Phase{255, 1} && maximum.windows.front().coverage == g::Rate{1, 256},
          "Largest supported cycle and speed preserve the final-cell opening through wrap.");
}
struct Output { int code; std::string text; std::string errors; };
Output run(std::vector<std::string_view> args) {
    std::ostringstream out, errors;
    const int code = w::workbench(args, out, errors);
    return {code, out.str(), errors.str()};
}
void caller() {
    const auto burst = run({"burst", "5", "2", "1"});
    check(burst.code == 0 && burst.errors.empty() && burst.text.find("Native output rotating 10/1.") != std::string::npos &&
          burst.text.find("Cam 1 start off end off coverage 1/5; open (1/2,7/10).") != std::string::npos &&
          burst.text.find("Overlap 1+2 coverage 1/5") != std::string::npos,
          "Actual native gears expose a complete between-samples opening and accepted overlap.");
    const auto fast = run({"fast", "5", "2", "3"});
    check(fast.code == 0 && fast.text.find("Cam 1 start off end on coverage 0/1; open none.") != std::string::npos &&
          fast.text.find("Cam 1 start on end off coverage 4/5; open (0/1,4/5).") != std::string::npos,
          "The actual caller distinguishes an endpoint-only opening from the later finite interval.");
    const auto reverse = run({"reverse", "5", "2", "8"});
    check(reverse.code == 0 && reverse.text.find("Cam 1 start off end on coverage 1/1; open (0/1,1/1).") != std::string::npos,
          "Reverse entry retains separate instant and interval states in the real trace.");
    for (const auto& args : {std::vector<std::string_view>{"fast", "0", "2", "1", "--paused"}, {"stalled", "0", "2", "1"}}) {
        const auto held = run(args);
        check(held.code == 0 && held.text.find("shaft advances no") != std::string::npos &&
              held.text.find("Cam 1 start on end on coverage 1/1; open (0/1,1/1).") != std::string::npos,
              "Paused/stalled gears preserve held-open geometry without claiming shaft motion or work.");
    }
    check(run({"burst", "4", "1", "1"}).text.find("\nOverlap ") == std::string::npos,
          "A mere boundary meeting is not printed as simultaneous follower coverage.");
    check(run({"burst", "9", "3", "1"}).text.find("coverage 3/10; open (0/1,1/5) (9/10,1/1).") != std::string::npos,
          "The actual caller preserves both pieces of a wrapping opening.");
    for (const auto& args : {std::vector<std::string_view>{"missing", "1", "1", "1"}, {"fast", "10", "1", "1"}, {"fast", "0", "11", "1"},
             {"fast", "0", "1", "257"}, {"fast", "-1", "1", "1"}, {"fast", "0", "1x", "1"}, {"fast", "0", "1", "1", "--other"}})
        check(run(args).code == 2, "Unknown, malformed and out-of-bound startup data refuse.");
    check(run({"list"}).code == 0 && run({"--help"}).code == 0 && run({"slow", "0", "0", "0"}).code == 0,
          "Catalogue, help and a zero-tick trace remain valid.");
    std::ostringstream out, errors;
    out.setstate(std::ios::badbit);
    const std::vector<std::string_view> args{"burst", "5", "2", "1"};
    check(w::workbench(args, out, errors) == 2, "Output failure cannot become a successful schedule trace.");
}
}  // namespace
int main() {
    try {
        literals(); oracle(); bounds_and_ownership(); caller();
        std::cout << checks << " cam-window assertions passed, including 141600 independent lattice cases.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " assertions: " << error.what() << '\n';
        return 1;
    }
}
