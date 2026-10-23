#pragma once

#include <string_view>

namespace factory::godot_fixture {
enum class Verdict { pass, missing_marker, diagnostic, malformed_log };

// Inspect every byte of a bounded, retained Godot log. The marker must be one
// complete line; a partial fixture count cannot satisfy another run's result.
Verdict inspect_log(std::string_view log, std::string_view expected_line);
const char* verdict_name(Verdict verdict) noexcept;
}  // namespace factory::godot_fixture
