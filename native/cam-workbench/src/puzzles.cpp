#include "factory/cam_puzzles.hpp"

namespace factory::cam_puzzles {
namespace m = mechanisms;
namespace {
constexpr std::array<Challenge, 3> challenges{{
    {"dock", "The impatient feeder",
     "Unload completely before the feeder opens. Keep both gates at the dock.",
     {6, 4, 6}, {0, 2}, 2, 3, false, {1, 11, 0}},
    {"ram", "Raise before returning",
     "Fit the entire four-tooth ram stroke inside the short work dwell.",
     {4, 4, 4}, {0, 1}, 2, 4, false, {1, 9, 0}},
    {"paired", "One drive, two workstations",
     "Stagger the second workstation. The common drive supports one pressing ram at a time.",
     {6, 4, 6}, {0, 2}, 2, 4, true, {2, 10, 1}},
}};

Error lane_at(const Challenge& challenge, Keys keys, m::Phase phase, Lane& lane) noexcept {
    lane.phase = phase;
    if (m::sample(challenge.slide, phase, lane.carriage) != m::Error::none ||
        m::cam_active(challenge.slide, phase, challenge.unload, lane.unloading) != m::Error::none ||
        m::cam_active(challenge.slide, phase, {keys.feed, challenge.feed_width}, lane.feeding) != m::Error::none ||
        m::cam_active(challenge.slide, phase, {keys.ram, challenge.ram_width}, lane.pressing) != m::Error::none) {
        return Error::invalid_fixture;
    }
    return Error::none;
}
}  // namespace

std::span<const Challenge> catalogue() noexcept { return challenges; }

const Challenge* find(std::string_view id) noexcept {
    for (const auto& challenge : challenges) if (challenge.id == id) return &challenge;
    return nullptr;
}

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::unknown_challenge: return "unknown_challenge";
        case Error::invalid_key: return "invalid_key";
        case Error::invalid_phase: return "invalid_phase";
        case Error::invalid_fixture: return "invalid_fixture";
    }
    return "unknown";
}

const char* explanation(Fault fault) noexcept {
    switch (fault) {
        case Fault::none: return "Every timing constraint is satisfied.";
        case Fault::unload_offsite: return "The discharge gate is open away from the dock.";
        case Fault::feed_offsite: return "The feeder is open away from the dock.";
        case Fault::ram_offsite: return "The ram is extended outside the work dwell. Clear it before the carriage moves.";
        case Fault::dock_overlap: return "The discharge gate and feeder overlap. Finish unloading before feeding.";
        case Fault::drive_overload: return "Both rams press at once. Rephase the second workstation to share the drive.";
    }
    return "Unknown timing fault.";
}

Error snapshot(std::string_view id, Keys keys, m::Phase phase, Frame& output) noexcept {
    const auto* challenge = find(id);
    if (!challenge) return Error::unknown_challenge;
    Tooth length{};
    if (m::cycle_length(challenge->slide, length) != m::Error::none) return Error::invalid_fixture;
    if (keys.feed >= length || keys.ram >= length || keys.offset >= length ||
        (!challenge->paired && keys.offset != 0)) return Error::invalid_key;
    if (phase.tooth >= length) return Error::invalid_phase;
    Frame frame{};
    frame.lane_count = challenge->paired ? 2 : 1;
    auto error = lane_at(*challenge, keys, phase, frame.lanes[0]);
    if (error != Error::none) return error;
    if (challenge->paired) {
        const Tooth local = phase.tooth >= keys.offset ? phase.tooth - keys.offset
            : length - (keys.offset - phase.tooth);
        error = lane_at(*challenge, keys, {local}, frame.lanes[1]);
        if (error != Error::none) return error;
    }
    output = frame;
    return Error::none;
}

Report inspect(std::string_view id, Keys keys) noexcept {
    Frame frame{};
    const auto error = snapshot(id, keys, {}, frame);
    if (error != Error::none) return {error};
    const auto* challenge = find(id);
    Tooth length{};
    if (m::cycle_length(challenge->slide, length) != m::Error::none) return {Error::invalid_fixture};
    for (Tooth tooth = 0; tooth < length; ++tooth) {
        const auto frame_error = snapshot(id, keys, {tooth}, frame);
        if (frame_error != Error::none) return {frame_error};
        for (unsigned i = 0; i < frame.lane_count; ++i) {
            const auto& lane = frame.lanes[i];
            Fault fault = Fault::none;
            if (lane.unloading && lane.feeding) fault = Fault::dock_overlap;
            else if (lane.unloading && lane.carriage.stage != m::Stage::dock) fault = Fault::unload_offsite;
            else if (lane.feeding && lane.carriage.stage != m::Stage::dock) fault = Fault::feed_offsite;
            else if (lane.pressing && lane.carriage.stage != m::Stage::work) fault = Fault::ram_offsite;
            if (fault != Fault::none) return {Error::none, fault, tooth, i + 1};
        }
        if (challenge->paired && frame.lanes[0].pressing && frame.lanes[1].pressing) {
            return {Error::none, Fault::drive_overload, tooth, 0};
        }
    }
    return {};
}
}  // namespace factory::cam_puzzles
