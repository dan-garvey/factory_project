#include "fixture.hpp"

#include <algorithm>
#include <cctype>
#include <string>

namespace factory::godot_fixture {
namespace {
bool diagnostic(std::string_view line) {
    if (line.find("SCRIPT ERROR:") != line.npos || line.find("ERROR:") != line.npos ||
        line.find("Parse Error:") != line.npos || line.find("Compile Error:") != line.npos)
        return true;
    std::string lower(line);
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return lower.find("failed to load script") != lower.npos ||
           lower.find("failed to compile depended scripts") != lower.npos;
}
}  // namespace

Verdict inspect_log(std::string_view log, std::string_view expected_line) {
    if (expected_line.empty() || expected_line.find_first_of("\r\n\0", 0, 3) != expected_line.npos)
        return Verdict::malformed_log;
    unsigned markers = 0;
    for (std::size_t start = 0; start < log.size();) {
        const auto end = log.find('\n', start);
        auto line = log.substr(start, end == log.npos ? log.npos : end - start);
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        for (unsigned char character : line)
            if ((character < 0x20 && character != '\t') || character == 0x7f)
                return Verdict::malformed_log;
        if (diagnostic(line)) return Verdict::diagnostic;
        if (line == expected_line) ++markers;
        if (end == log.npos) break;
        start = end + 1;
    }
    return markers == 1 ? Verdict::pass : Verdict::missing_marker;
}

const char* verdict_name(Verdict verdict) noexcept {
    switch (verdict) {
        case Verdict::pass: return "pass";
        case Verdict::missing_marker: return "missing_marker";
        case Verdict::diagnostic: return "godot_diagnostic";
        case Verdict::malformed_log: return "malformed_log";
    }
    return "unexpected";
}
}  // namespace factory::godot_fixture
