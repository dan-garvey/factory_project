#include "factory/slotted_shuttle.hpp"

#include <algorithm>

namespace factory::slotted_shuttle {
namespace b = slotted_bank;
namespace p = slotted_pairs;

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_cursor: return "invalid_cursor";
        case Error::invalid_bound: return "invalid_bound";
        case Error::parent_refused: return "parent_refused";
    }
    return "unknown";
}
const char* stop_name(Stop stop) noexcept {
    switch (stop) {
        case Stop::unpowered: return "unpowered";
        case Stop::obstructed: return "obstructed";
        case Stop::endstop: return "endstop";
    }
    return "unknown";
}

Plan prepare(const Profile& profile, std::span<const b::Link> links, const State& state,
             const slotted_clearance::Rig& rig, std::span<const p::Pair> pairs, bool powered) {
    if (profile.stops.empty() || profile.stops.size() > maximum_stops)
        return Refusal{Error::invalid_profile, {}};
    for (const auto stop : profile.stops)
        if (stop < -mechanics::maximum_coordinate || stop > mechanics::maximum_coordinate)
            return Refusal{Error::invalid_profile, {}};
    if (state.cursor >= profile.stops.size()) return Refusal{Error::invalid_cursor, {}};
    const auto destination = profile.stops[state.cursor];
    const auto candidate = p::prepare(links, state.bank, rig, {destination, powered}, pairs);
    if (const auto* error = std::get_if<p::Refusal>(&candidate))
        return Refusal{Error::parent_refused, *error};
    if (const auto* blocked = std::get_if<p::Blocked>(&candidate))
        return Hold{state, Stop::obstructed, Conflict{blocked->pair, blocked->time, blocked->initially_overlapping}, {}};
    if (const auto* advancing = std::get_if<b::Advance>(&candidate)) {
        const bool reached = advancing->next.pin == destination;
        const auto cursor = reached ? (state.cursor + 1) % profile.stops.size() : state.cursor;
        return Step{{advancing->next, cursor}, advancing->traces, advancing->limit, reached};
    }
    const auto& hold = std::get<b::Hold>(candidate);
    if (hold.reason == b::Stop::unpowered) return Hold{state, Stop::unpowered, {}, hold.limit};
    if (hold.state.pin == destination)
        return Step{{hold.state, (state.cursor + 1) % profile.stops.size()}, {}, hold.limit, true};
    return Hold{state, Stop::endstop, {}, hold.limit};
}

Report inspect(const Profile& profile, std::span<const b::Link> links, const State& state,
               const slotted_clearance::Rig& rig, std::span<const p::Pair> pairs,
               std::size_t steps, bool powered) {
    Report report;
    report.path.push_back(state);
    if (steps == 0 || steps > maximum_steps) {
        report.outcome = Outcome::refused;
        report.refusal = Refusal{Error::invalid_bound, {}};
        return report;
    }
    for (std::size_t step = 0; step < steps; ++step) {
        const auto proposal = prepare(profile, links, report.path.back(), rig, pairs, powered);
        if (const auto* error = std::get_if<Refusal>(&proposal)) {
            report.outcome = Outcome::refused;
            report.refusal = *error;
            return report;
        }
        if (const auto* hold = std::get_if<Hold>(&proposal)) {
            report.outcome = Outcome::held;
            report.hold = *hold;
            return report;
        }
        report.path.push_back(std::get<Step>(proposal).next);
        const auto end = report.path.end() - 1;
        const auto previous = std::find(report.path.begin(), end, report.path.back());
        if (previous == end) continue;
        const auto begin = static_cast<std::size_t>(previous - report.path.begin());
        const auto finish = report.path.size() - 1;
        Loop loop{begin, finish - begin, false, {}};
        for (std::size_t index = begin + 1; index <= finish; ++index)
            if (report.path[index].bank.pin != report.path[begin].bank.pin) loop.pin_moves = true;
        for (std::size_t follower = 0; follower < report.path[begin].bank.followers.size(); ++follower) {
            bool moved = false;
            const auto& original = report.path[begin].bank.followers[follower];
            for (std::size_t index = begin + 1; index <= finish; ++index)
                if (report.path[index].bank.followers[follower].position != original.position) moved = true;
            if (!moved) loop.unmoved_followers.push_back(original.id);
        }
        report.outcome = Outcome::recurrent;
        report.loop = std::move(loop);
        return report;
    }
    return report;
}
}  // namespace factory::slotted_shuttle
