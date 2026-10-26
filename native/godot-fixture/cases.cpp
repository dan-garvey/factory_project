#include "cases.hpp"

#include <array>
#include <filesystem>
#include <set>
#include <vector>

namespace factory::godot_fixture {
namespace {
constexpr std::array first_plate_fixed{
    std::string_view{"--native-check-mode=arrival-first-plate"},
    std::string_view{"--event-route-pointer"},
};
constexpr std::array channel_small_fixed{
    std::string_view{"--native-check-mode=arrival-channel-small"},
    std::string_view{"--event-route-loose"},
};
constexpr std::array channel_resume_fixed{
    std::string_view{"--native-check-mode=arrival-channel-small-resume"},
    std::string_view{"--event-route-loose"},
};
constexpr std::array first_plate_values{std::string_view{"--native-check-output="}};
constexpr std::array channel_small_values{
    std::string_view{"--resume-input="},
    std::string_view{"--save-slot="},
    std::string_view{"--native-check-output="},
};
constexpr std::array channel_resume_values{
    std::string_view{"--resume-input="},
    std::string_view{"--save-slot="},
    std::string_view{"--native-check-prior="},
    std::string_view{"--native-check-output="},
};
constexpr std::string_view script = "res://opening/native_adapter_check.gd";
const std::array cases{
    Case{"arrival-first-plate", script, "CHAPTER 1 SCENE EVENTS PASS: arrival-first-plate",
         180, first_plate_fixed, first_plate_values},
    Case{"arrival-channel-small", script, "CHAPTER 1 SCENE EVENTS PASS: arrival-channel-small",
         300, channel_small_fixed, channel_small_values},
    Case{"arrival-channel-small-resume", script,
         "CHAPTER 1 SCENE EVENTS PASS: arrival-channel-small-resume",
         180, channel_resume_fixed, channel_resume_values},
};
}  // namespace

const Case* find_case(std::string_view name) noexcept {
    for (const auto& selected : cases)
        if (selected.name == name) return &selected;
    return nullptr;
}

std::span<const Case> registered_cases() noexcept { return cases; }

bool accepts_case_arguments(const Case& selected, std::span<const std::string> arguments) {
    if (arguments.size() != selected.fixed_arguments.size() + selected.value_prefixes.size()) return false;
    std::vector<bool> fixed_seen(selected.fixed_arguments.size());
    std::vector<bool> value_seen(selected.value_prefixes.size());
    for (const auto& argument : arguments) {
        bool matched = false;
        for (std::size_t i = 0; i < selected.fixed_arguments.size(); ++i) {
            if (argument == selected.fixed_arguments[i]) {
                if (fixed_seen[i]) return false;
                fixed_seen[i] = true;
                matched = true;
                break;
            }
        }
        if (matched) continue;
        for (std::size_t i = 0; i < selected.value_prefixes.size(); ++i) {
            const auto prefix = selected.value_prefixes[i];
            if (argument.starts_with(prefix) && argument.size() > prefix.size()) {
                if (value_seen[i]) return false;
                value_seen[i] = true;
                matched = true;
                break;
            }
        }
        if (!matched) return false;
    }
    return true;
}

bool distinct_case_output_paths(std::span<const std::string> arguments) {
    std::set<std::filesystem::path> destinations;
    for (const auto& argument : arguments) {
        if (!argument.starts_with("--native-check-output=") &&
            !argument.starts_with("--save-slot=")) continue;
        const std::filesystem::path path(argument.substr(argument.find('=') + 1));
        const auto destination = std::filesystem::canonical(path.parent_path()) / path.filename();
        if (!destinations.insert(destination).second) return false;
    }
    return true;
}
}  // namespace factory::godot_fixture
