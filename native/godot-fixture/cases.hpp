#pragma once

#include <span>
#include <string>
#include <string_view>

namespace factory::godot_fixture {
struct Case {
    std::string_view name;
    std::string_view script;
    std::string_view pass_line;
    unsigned seconds;
    std::span<const std::string_view> fixed_arguments;
    std::span<const std::string_view> value_prefixes;
};

const Case* find_case(std::string_view name) noexcept;
std::span<const Case> registered_cases() noexcept;
bool accepts_case_arguments(const Case& selected, std::span<const std::string> arguments);
}  // namespace factory::godot_fixture
