#include "factory/gantry_workbench.hpp"
#include "factory/gantries.hpp"

#include <charconv>
#include <exception>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace factory::gantries {
namespace {
template<class T> bool integer(const std::string& text, T& value) {
    const auto parsed = std::from_chars(text.data(), text.data() + text.size(), value);
    return parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size();
}

void inspect(const Definition& definition, Settings settings, std::ostream& out) {
    out << "Settings offset=" << settings.offset << " height=" << settings.height << '\n';
    for (const auto* track : {&definition.first, &definition.second}) {
        const auto& slide = track->slide;
        const auto& a = track->dock;
        const auto& b = track->work;
        const auto height = track == &definition.first ? 0 : settings.height;
        out << (track == &definition.first ? "A" : "B") << ": (" << a[0] << ',' << a[1] + height << ',' << a[2]
            << ") -> (" << b[0] << ',' << b[1] + height << ',' << b[2] << "), dock=" << slide.dock
            << " travel=" << slide.travel << " work=" << slide.work << " return=" << slide.travel << '\n';
    }
    mechanisms::Tooth length{};
    if (mechanisms::cycle_length(definition.second.slide, length) == mechanisms::Error::none)
        out << "Height raises B by 0.." << definition.maximum_height << "; B phase "
            << (definition.phase_adjustable ? "may be keyed to 0.." : "is fixed at ")
            << (definition.phase_adjustable ? length - 1 : 0) << ".\n";
}

void help(std::ostream& out) {
    out << "inspect | hint | help | offset <tooth> | height <units> | run | quit\n"
           "Two 2x2x2 carriages follow fixed rails. Their boxes extend one unit\n"
           "either side of x/z and two units above the rail. Grazing is clear.\n"
           "Find a repeating layout with no interior overlap. Run checks the\n"
           "whole common cycle, including travel between endpoints.\n";
}
}  // namespace

int workbench(std::span<const std::string_view> arguments, std::istream& input, std::ostream& out, std::ostream& errors) {
    try {
        if (arguments.size() == 1 && (arguments[0] == "list" || arguments[0] == "help")) {
            out << "gantry_workbench list | play <bridge|crossing|freight>\n";
            for (const auto& definition : catalogue()) out << definition.id << ": " << definition.title << '\n';
            return out ? 0 : 2;
        }
        if (arguments.size() != 2 || arguments[0] != "play") {
            errors << "Usage: gantry_workbench list | play <bridge|crossing|freight>\n"; return 2;
        }
        const auto* definition = find(arguments[1]);
        if (!definition) { errors << "Unknown gantry puzzle. Use list.\n"; return 2; }
        Settings settings;
        out << definition->title << '\n';
        help(out);
        inspect(*definition, settings, out);
        for (std::string line;;) {
            out << "gantry> " << std::flush;
            if (!out) return 2;
            if (!std::getline(input, line)) {
                if (input.bad() || !input.eof()) { errors << "Input failed.\n"; return 2; }
                out << "Unfinished.\n"; return out ? 1 : 2;
            }
            if (line.size() > 256) { out << "Command too long. Settings unchanged.\n"; continue; }
            std::istringstream words(line);
            std::vector<std::string> tokens;
            for (std::string word; words >> word;) tokens.push_back(std::move(word));
            if (tokens.empty()) continue;
            const auto& verb = tokens[0];
            if ((verb == "height" || verb == "offset") && tokens.size() == 2) {
                auto candidate = settings;
                const bool parsed = verb == "height" ? integer(tokens[1], candidate.height) : integer(tokens[1], candidate.offset);
                if (!parsed || evaluate(definition->puzzle, candidate).error != Error::none) {
                    out << "Unavailable setting. Settings unchanged.\n"; continue;
                }
                settings = candidate;
                out << "Settings offset=" << settings.offset << " height=" << settings.height << '\n';
            } else if (tokens.size() != 1) out << "Invalid command. Type help.\n";
            else if (verb == "help") help(out);
            else if (verb == "inspect") inspect(*definition, settings, out);
            else if (verb == "hint") out << definition->hint << '\n';
            else if (verb == "quit") { out << "Unfinished.\n"; return out ? 1 : 2; }
            else if (verb == "run") {
                const auto report = evaluate(definition->puzzle, settings);
                if (report.error != Error::none) { errors << error_name(report.error) << '\n'; return 2; }
                if (report.conflict) {
                    const auto& conflict = *report.conflict;
                    out << "Blocked: interval=" << conflict.interval << " contact=" << conflict.contact.numerator
                        << '/' << conflict.contact.denominator << " of that interval; repeat=" << report.period << ".\n"
                           "Both settings remain available to correct.\n";
                } else {
                    out << "Clear: all " << report.period << " intervals repeat without interior overlap.\n";
                    return out ? 0 : 2;
                }
            } else out << "Invalid command. Type help.\n";
        }
    } catch (const std::exception&) {
        if (errors) errors << "Gantry workbench could not continue.\n";
        return 2;
    }
}
}  // namespace factory::gantries
