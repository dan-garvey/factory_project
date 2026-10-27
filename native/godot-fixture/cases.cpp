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
constexpr std::array raised_starter_fixed{
    std::string_view{"--native-check-mode=arrival-raised-starter-snap"},
    std::string_view{"--event-route-pointer"},
};
constexpr std::array raised_press_fixed{
    std::string_view{"--native-check-mode=arrival-raised-press"},
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
constexpr std::array cog_repair_fixed{std::string_view{"--native-check-mode=arrival-cog-resume"}};
constexpr std::array cog_reopen_fixed{std::string_view{"--native-check-mode=arrival-cog-finish-resume"}};
constexpr std::array cog_values{
    std::string_view{"--resume-input="},
    std::string_view{"--native-check-output="},
    std::string_view{"--save-slot="},
};
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
constexpr std::array incline_fixed{std::string_view{"--native-check-mode=arrival-nonhorizontal-incline"}};
constexpr std::array vertical_fixed{std::string_view{"--native-check-mode=arrival-nonhorizontal-vertical-resume"}};
constexpr std::array sideways_fixed{std::string_view{"--native-check-mode=arrival-nonhorizontal-sideways-resume"}};
constexpr std::array power_reopen_fixed{std::string_view{"--native-check-mode=arrival-nonhorizontal-power-reopen-resume"}};
constexpr std::array actor_block_fixed{std::string_view{"--native-check-mode=arrival-nonhorizontal-actor-block-resume"}};
constexpr std::array incline_values{
    std::string_view{"--resume-input="},
    std::string_view{"--native-check-output="},
    std::string_view{"--save-slot="},
};
constexpr std::array<std::string_view, 0> no_arguments{};
constexpr std::array endpoint_common_fixed{std::string_view{"--common-frame-only"}};
constexpr std::array endpoint_inspection_fixed{std::string_view{"--inspection-only"}};
constexpr std::array endpoint_terrain_fixed{std::string_view{"--terrain-host-only"}};
constexpr std::string_view script = "res://opening/native_adapter_check.gd";
constexpr std::string_view cog_script = "res://opening/native_cog_check.gd";
constexpr std::string_view endpoint_script = "res://opening/native_transmission_endpoint_check.gd";
const std::array cases{
    Case{"arrival-first-plate", script, "CHAPTER 1 SCENE EVENTS PASS: arrival-first-plate",
         180, first_plate_fixed, first_plate_values},
    Case{"arrival-nonhorizontal-incline", script, "CHAPTER 1 PLAYER-BUILT INCLINE PASS",
         300, incline_fixed, incline_values},
    Case{"arrival-nonhorizontal-vertical-resume", script,
         "CHAPTER 1 PLAYER-BUILT POWER BELT PASS: arrival-nonhorizontal-vertical-resume",
         300, vertical_fixed, incline_values},
    Case{"arrival-nonhorizontal-sideways-resume", script,
         "CHAPTER 1 PLAYER-BUILT POWER BELT PASS: arrival-nonhorizontal-sideways-resume",
         300, sideways_fixed, incline_values},
    Case{"arrival-nonhorizontal-power-reopen-resume", script,
         "CHAPTER 1 POWER BELT REOPEN PASS", 180, power_reopen_fixed, incline_values},
    Case{"arrival-nonhorizontal-actor-block-resume", script,
         "CHAPTER 1 BELT ACTOR OBSTRUCTION PASS", 180, actor_block_fixed, incline_values},
    Case{"arrival-cog-repair", cog_script,
         "CHAPTER 1 COG REPAIR CHECKS COMPLETE",
         300, cog_repair_fixed, cog_values},
    Case{"arrival-cog-reopen", cog_script,
         "CHAPTER 1 COG REOPEN CHECKS COMPLETE",
         180, cog_reopen_fixed, cog_values},
    Case{"arrival-raised-starter-snap", script,
         "CHAPTER 1 SCENE EVENTS PASS: arrival-raised-starter-snap",
         180, raised_starter_fixed, first_plate_values},
    Case{"arrival-raised-press", script, "CHAPTER 1 SCENE EVENTS PASS: arrival-raised-press",
         180, raised_press_fixed, first_plate_values},
    Case{"arrival-channel-small", script, "CHAPTER 1 SCENE EVENTS PASS: arrival-channel-small",
         300, channel_small_fixed, channel_small_values},
    Case{"arrival-channel-small-resume", script,
         "CHAPTER 1 SCENE EVENTS PASS: arrival-channel-small-resume",
         180, channel_resume_fixed, channel_resume_values},
    Case{"transmission-endpoint-default", endpoint_script,
         R"({"checks":316,"desktop_operations":0,"evidence":"isolated_shaft_tile_controls_and_pointer","failures":0,"models":0,"status":"pass"})",
         180, no_arguments, no_arguments},
    Case{"transmission-endpoint-common-frame", endpoint_script,
         R"({"checks":3,"desktop_operations":0,"evidence":"isolated_shaft_tile_controls_and_pointer","failures":0,"models":0,"status":"pass"})",
         180, endpoint_common_fixed, no_arguments},
    Case{"transmission-endpoint-inspection", endpoint_script,
         R"({"checks":40,"desktop_operations":0,"evidence":"synthetic_transmission_inspection","failures":0,"status":"pass"})",
         180, endpoint_inspection_fixed, no_arguments},
    Case{"transmission-endpoint-terrain-host", endpoint_script,
         R"({"checks":48,"desktop_operations":0,"evidence":"synthetic_terrain_pointer_native_host","failures":0,"status":"pass"})",
         180, endpoint_terrain_fixed, no_arguments},
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
