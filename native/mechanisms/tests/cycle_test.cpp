#include "factory/cycle.hpp"

#include <array>
#include <iostream>
#include <limits>
#include <string_view>

namespace m = factory::mechanisms;
namespace {
int checks{};
int failures{};

void check(bool condition, std::string_view message) {
    ++checks;
    if (!condition) {
        ++failures;
        std::cerr << "FAIL: " << message << '\n';
    }
}

void literal_cycle() {
    const m::Slide slide{3, 4, 2};
    using enum m::Stage;
    const std::array<m::Pose, 13> expected{{
        {dock, 0, 4}, {dock, 0, 4}, {dock, 0, 4},
        {outward, 0, 4}, {outward, 1, 4}, {outward, 2, 4}, {outward, 3, 4},
        {work, 4, 4}, {work, 4, 4},
        {homeward, 4, 4}, {homeward, 3, 4}, {homeward, 2, 4}, {homeward, 1, 4},
    }};
    m::Phase phase;
    for (int cycle = 0; cycle < 3; ++cycle) {
        for (m::Tooth tooth = 0; tooth < expected.size(); ++tooth) {
            m::Pose pose;
            check(phase.tooth == tooth && m::sample(slide, phase, pose) == m::Error::none &&
                  pose == expected[tooth], "Every literal pose repeats, including finite endpoint dwells.");
            check(m::advance(slide, phase, true) == m::Error::none,
                  "An unobstructed powered tooth advances.");
        }
        check(phase == m::Phase{}, "A complete revolution returns to exactly the same phase.");
    }
}

void stop_and_resume() {
    const m::Slide slide{3, 4, 2};
    for (m::Tooth tooth = 0; tooth < 13; ++tooth) {
        m::Phase phase{tooth};
        const auto saved = phase;
        for (int i = 0; i < 7; ++i) {
            check(m::advance(slide, phase, false, true) == m::Error::none && phase == saved,
                  "Loss of power preserves exact phase, even with an obstruction.");
        }
        auto uninterrupted = saved;
        check(m::advance(slide, uninterrupted, true) == m::Error::none &&
              m::advance(slide, phase, true) == m::Error::none && phase == uninterrupted,
              "A restored phase resumes the same next tooth without catching up lost time.");
    }
    const std::array<m::Tooth, 8> movement{{3, 4, 5, 6, 9, 10, 11, 12}};
    for (const auto tooth : movement) {
        m::Phase phase{tooth};
        for (int i = 0; i < 3; ++i) {
            check(m::advance(slide, phase, true, true) == m::Error::obstructed &&
                  phase == m::Phase{tooth}, "An obstructed move cannot creep or lose cycle phase.");
        }
        check(m::advance(slide, phase, true) == m::Error::none &&
              phase.tooth == (tooth == 12 ? 0 : tooth + 1),
              "Clearing an obstruction resumes the exact refused move.");
    }
    for (const auto tooth : {0ULL, 1ULL, 2ULL, 7ULL, 8ULL}) {
        m::Phase phase{tooth};
        check(m::advance(slide, phase, true, true) == m::Error::none && phase.tooth == tooth + 1,
              "A travel-only obstruction cannot stall a dwell interval.");
    }
}

void keyed_cams() {
    const m::Slide slide{3, 4, 2};
    const std::array<bool, 13> wrapped{{true, true, false, false, false, false,
                                     false, false, false, false, false, true, true}};
    for (m::Tooth tooth = 0; tooth < 13; ++tooth) {
        bool active{};
        check(m::cam_active(slide, {tooth}, {11, 4}, active) == m::Error::none &&
              active == wrapped[tooth], "A wrapping lobe is active at exactly its four declared teeth.");
        check(m::cam_active(slide, {tooth}, {7, 2}, active) == m::Error::none &&
              active == (tooth == 7 || tooth == 8), "A press lobe fits exactly in work dwell.");
        check(m::cam_active(slide, {tooth}, {12, 0}, active) == m::Error::none && !active,
              "An empty cam disables the follower at every phase.");
        check(m::cam_active(slide, {tooth}, {12, 13}, active) == m::Error::none && active,
              "A full-circle lobe remains active across its key boundary.");
    }
}

void refusals_and_boundaries() {
    constexpr auto maximum = std::numeric_limits<m::Tooth>::max();
    for (const auto slide : {m::Slide{0, 4, 2}, m::Slide{3, 0, 2}, m::Slide{3, 4, 0},
                             m::Slide{1, maximum, 1}, m::Slide{maximum, 1, 1},
                             m::Slide{1, 1, maximum}, m::Slide{1, maximum / 2, 2}}) {
        m::Tooth length = 77;
        m::Pose pose{m::Stage::homeward, 5, 9};
        m::Phase phase{2};
        bool active = true;
        check(m::cycle_length(slide, length) == m::Error::invalid_slide && length == 77,
              "A missing dwell or overflowing cycle is refused without touching the output.");
        check(m::sample(slide, phase, pose) == m::Error::invalid_slide &&
              pose == m::Pose{m::Stage::homeward, 5, 9}, "Invalid sampling preserves the prior pose.");
        check(m::advance(slide, phase, false) == m::Error::invalid_slide && phase == m::Phase{2},
              "Stopped power cannot hide invalid configuration.");
        check(m::cam_active(slide, phase, {}, active) == m::Error::invalid_slide && active,
              "Invalid cam sampling preserves the caller's result.");
    }
    for (const auto tooth : {m::Tooth{13}, maximum}) {
        m::Phase phase{tooth};
        m::Pose pose{m::Stage::work, 9, 9};
        bool active = true;
        check(m::advance({3, 4, 2}, phase, true) == m::Error::invalid_phase && phase.tooth == tooth,
              "A malformed imported phase cannot be normalized into an accepted state.");
        check(m::sample({3, 4, 2}, phase, pose) == m::Error::invalid_phase &&
              pose == m::Pose{m::Stage::work, 9, 9}, "Out-of-cycle sampling preserves its result.");
        check(m::cam_active({3, 4, 2}, phase, {}, active) == m::Error::invalid_phase && active,
              "A cam cannot hide a malformed imported phase.");
    }
    for (const auto cam : {m::Cam{13, 1}, m::Cam{0, 14}, m::Cam{maximum, maximum}}) {
        bool active = true;
        check(m::cam_active({3, 4, 2}, {}, cam, active) == m::Error::invalid_cam && active,
              "Invalid lobe dimensions are refused atomically.");
    }
    const m::Slide widest{1, (maximum - 3) / 2, 2};
    m::Tooth length{};
    m::Phase phase{maximum - 1};
    m::Pose pose;
    check(m::cycle_length(widest, length) == m::Error::none && length == maximum,
          "The largest representable full cycle is accepted without an arbitrary cap.");
    check(m::sample(widest, phase, pose) == m::Error::none &&
          pose == m::Pose{m::Stage::homeward, 1, widest.travel},
          "The last position remains exact at the integer limit.");
    bool active{};
    check(m::cam_active(widest, {}, {maximum - 1, 2}, active) == m::Error::none && active,
          "A lobe may cross the integer-limit seam without adding overflowing endpoints.");
    check(m::advance(widest, phase, true, true) == m::Error::obstructed && phase.tooth == maximum - 1,
          "The final return step remains obstruction-sensitive at the integer limit.");
    check(m::advance(widest, phase, true) == m::Error::none && phase == m::Phase{},
          "A maximum-length cycle wraps without counter overflow.");
}
}  // namespace

int main() {
    literal_cycle();
    stop_and_resume();
    keyed_cams();
    refusals_and_boundaries();
    std::cout << checks << " mechanism checks, " << failures << " failures.\n";
    return failures == 0 ? 0 : 1;
}
