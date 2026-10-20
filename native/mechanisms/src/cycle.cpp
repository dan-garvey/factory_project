#include "factory/cycle.hpp"

#include <limits>

namespace factory::mechanisms {
namespace {
Pose at(const Slide& slide, Tooth tooth) noexcept {
    if (tooth < slide.dock) return {Stage::dock, 0, slide.travel};
    tooth -= slide.dock;
    if (tooth < slide.travel) return {Stage::outward, tooth, slide.travel};
    tooth -= slide.travel;
    if (tooth < slide.work) return {Stage::work, slide.travel, slide.travel};
    tooth -= slide.work;
    return {Stage::homeward, slide.travel - tooth, slide.travel};
}

Error validate(const Slide& slide, Phase phase, Tooth& length) noexcept {
    const auto error = cycle_length(slide, length);
    if (error != Error::none) return error;
    return phase.tooth < length ? Error::none : Error::invalid_phase;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::invalid_slide: return "invalid_slide";
        case Error::invalid_phase: return "invalid_phase";
        case Error::invalid_cam: return "invalid_cam";
        case Error::obstructed: return "obstructed";
    }
    return "unknown";
}

const char* stage_name(Stage stage) noexcept {
    switch (stage) {
        case Stage::dock: return "dock";
        case Stage::outward: return "outward";
        case Stage::work: return "work";
        case Stage::homeward: return "homeward";
    }
    return "unknown";
}

Error cycle_length(const Slide& slide, Tooth& result) noexcept {
    constexpr auto limit = std::numeric_limits<Tooth>::max();
    if (slide.dock == 0 || slide.travel == 0 || slide.work == 0 ||
        slide.travel > limit / 2) return Error::invalid_slide;
    const Tooth travel = slide.travel * 2;
    if (slide.dock > limit - travel) return Error::invalid_slide;
    const Tooth partial = slide.dock + travel;
    if (slide.work > limit - partial) return Error::invalid_slide;
    result = partial + slide.work;
    return Error::none;
}

Error sample(const Slide& slide, Phase phase, Pose& result) noexcept {
    Tooth length{};
    const auto error = validate(slide, phase, length);
    if (error != Error::none) return error;
    result = at(slide, phase.tooth);
    return Error::none;
}

Error cam_active(const Slide& slide, Phase phase, Cam cam, bool& result) noexcept {
    Tooth length{};
    const auto error = validate(slide, phase, length);
    if (error != Error::none) return error;
    if (cam.start >= length || cam.width > length) return Error::invalid_cam;
    const Tooth elapsed = phase.tooth >= cam.start
        ? phase.tooth - cam.start : length - (cam.start - phase.tooth);
    result = elapsed < cam.width;
    return Error::none;
}

Error advance(const Slide& slide, Phase& phase, bool powered,
              bool travel_obstructed) noexcept {
    Tooth length{};
    const auto error = validate(slide, phase, length);
    if (error != Error::none) return error;
    if (!powered) return Error::none;
    const Tooth next = phase.tooth == length - 1 ? 0 : phase.tooth + 1;
    if (travel_obstructed &&
        at(slide, phase.tooth).numerator != at(slide, next).numerator) {
        return Error::obstructed;
    }
    phase.tooth = next;
    return Error::none;
}
}  // namespace factory::mechanisms
