#include "factory/index_workbench.hpp"

#include <istream>
#include <ostream>
#include <sstream>
#include <string>

namespace factory::indexing {
namespace {
constexpr std::array<Challenge, 3> challenges{{
    {"opposites", "Two opposite flanges", "Mark Z+ and Z- using the x-axis cradle, then return home.", 0x30, {true, false, false}},
    {"corner", "Three faces, one tool", "Mark X+, Y+ and Z+ using x/z indexing, then return home.", 0x15, {true, false, true}},
    {"all_faces", "The complete inspection block", "Mark all six original faces and return the same holder home.", all_faces, {true, true, true}},
}};

void mask(std::ostream& out, FaceMask bits) {
    bool any{};
    for (unsigned face = 0; face < 6; ++face) {
        if ((bits & (1U << face)) == 0) continue;
        if (any) out << ' ';
        out << face_name(static_cast<Face>(face));
        any = true;
    }
    if (!any) out << "none";
}

void state(std::ostream& out, const Job& job) {
    Face up{};
    const auto error = local_face(job.orientation, Face::positive_y, up);
    out << "Workpiece " << job.id << ", upward face " << (error == Error::none ? face_name(up) : "?") << ", marked ";
    mask(out, job.marked);
    out << "; local axes point to " << face_name(job.orientation.positive_axes[0]) << ' '
        << face_name(job.orientation.positive_axes[1]) << ' ' << face_name(job.orientation.positive_axes[2]) << ".\n";
}

void usage(std::ostream& out) {
    out << "Indexed work-face fixture\n"
           "Usage: index_workbench list | <puzzle> [x+|x-|y+|y-|z+|z-|stamp|release ...]\n"
           "       index_workbench play <puzzle>\n"
           "Turns are right-hand quarter turns around fixed world axes.\n"
           "The shared tool stamps the original local face currently pointing upward.\n"
           "One workpiece is supplied for each fresh fixture run; marks survive indexing.\n\n";
    for (const auto& challenge : challenges) out << challenge.id << ": " << challenge.title << '\n';
}

const Challenge* find(std::string_view id) noexcept {
    for (const auto& challenge : challenges) if (challenge.id == id) return &challenge;
    return nullptr;
}

void introduce(std::ostream& out, const Challenge& challenge, const Job& job) {
    out << challenge.title << '\n' << challenge.goal << "\nRequired faces: "; mask(out, job.required); out << '\n';
    state(out, job);
}

enum class Applied { okay, refused, released, invalid };

Applied apply(const Challenge& challenge, std::string_view token, Job& job,
              std::ostream& out, std::ostream& errors) {
    Error error{};
    Job next = job;
    if (token == "stamp") error = plan_stamp(job, Face::positive_y, next);
    else if (token == "release") error = release_ready(job);
    else if (token.size() == 2 && token[0] >= 'x' && token[0] <= 'z' && (token[1] == '+' || token[1] == '-')) {
        const auto axis = static_cast<unsigned>(token[0] - 'x');
        if (!challenge.allowed_axes[axis]) {
            out << "Refused: that axis is locked by this fixture.\n";
            state(out, job);
            return Applied::refused;
        }
        error = plan_turn(job, static_cast<Axis>(axis), token[1] == '+' ? 1 : -1, next);
    } else {
        errors << "Unknown action. Use quarter turns, stamp or release.\n";
        state(out, job);
        return Applied::invalid;
    }
    if (error != Error::none) {
        out << "Refused: " << explanation(error) << '\n';
        state(out, job);
        return Applied::refused;
    }
    job = next;
    out << token << ": "; state(out, job);
    return token == "release" ? Applied::released : Applied::okay;
}

void solved(std::ostream& out, const Job& job) {
    out << "Solved: original workpiece " << job.id << " released complete at home.\n";
}
}  // namespace

std::span<const Challenge> catalogue() noexcept { return challenges; }

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        usage(out);
        return out ? 0 : 2;
    }
    const auto* challenge = find(args[0]);
    if (!challenge) { errors << "Unknown puzzle. Use index_workbench list.\n"; return 2; }
    Job job{7, {}, challenge->required, 0};
    introduce(out, *challenge, job);
    bool released{};
    for (std::size_t i = 1; i < args.size(); ++i) {
        if (released) { errors << "No actions may follow release.\n"; return 2; }
        const auto result = apply(*challenge, args[i], job, out, errors);
        if (result == Applied::invalid) return 2;
        released = result == Applied::released;
    }
    if (released) solved(out, job);
    else out << (release_ready(job) == Error::none ? "Ready at home. Use release to finish.\n" : "Complete the required faces, return home, then release.\n");
    return out ? (released ? 0 : 1) : 2;
}

int play(std::string_view puzzle, std::istream& input, std::ostream& out, std::ostream& errors) {
    const auto* challenge = find(puzzle);
    if (!challenge) { errors << "Unknown puzzle. Use index_workbench list.\n"; return 2; }
    Job job{7, {}, challenge->required, 0};
    introduce(out, *challenge, job);
    out << "Enter inspect, help, quarter turns, stamp or release. quit leaves this fixture.\n";
    std::string line;
    while (out && errors) {
        out << "> " << std::flush;
        if (!std::getline(input, line)) {
            if (input.bad() || !input.eof() || !out || !errors) return 2;
            out << "Fixture ended before a completed release.\n";
            return out ? 1 : 2;
        }
        std::istringstream commands(line);
        std::string token;
        while (commands >> token) {
            if (token == "help") { usage(out); continue; }
            if (token == "inspect") { state(out, job); continue; }
            if (token == "quit") { out << "Leaving the indexing fixture.\n"; return out ? 1 : 2; }
            const auto result = apply(*challenge, token, job, out, errors);
            if (result == Applied::released) {
                solved(out, job);
                return out && errors ? 0 : 2;
            }
        }
    }
    return 2;
}
}  // namespace factory::indexing
