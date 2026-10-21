#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace factory::validation {

inline constexpr std::size_t max_input_bytes = 2 * 1024 * 1024;
inline constexpr std::size_t max_entries = 4096;
inline constexpr std::size_t max_path_bytes = 4096;
inline constexpr std::size_t max_output_bytes = 4 * 1024 * 1024;

enum class ObjectFormat { sha1, sha256 };
enum class Code {
    format, input_limit, entry_limit, truncated, record, mode, object_id,
    path, private_path, utf8, duplicate, path_conflict, output_limit, read_error,
};

struct Issue {
    Code code;
    std::size_t record_index;
    std::size_t byte_offset;
};

struct Entry {
    std::string mode;
    std::string object_id;
    std::string path;
};

struct Parsed;
class Manifest {
public:
    Manifest(const Manifest&) = default;
    Manifest(Manifest&&) noexcept = default;
    Manifest& operator=(const Manifest&) = default;
    Manifest& operator=(Manifest&&) noexcept = default;
    [[nodiscard]] ObjectFormat format() const noexcept { return format_; }
    [[nodiscard]] const std::vector<Entry>& entries() const noexcept { return entries_; }

private:
    Manifest(ObjectFormat format, std::vector<Entry> entries);
    ObjectFormat format_;
    std::vector<Entry> entries_;
    friend Parsed parse_listing(std::string_view, ObjectFormat);
};

struct Parsed {
    std::optional<Manifest> manifest;
    std::optional<Issue> issue;
};
struct Rendered {
    std::optional<std::string> json;
    std::optional<Issue> issue;
};

// Metadata validation only. The caller owns trusted Git acquisition, actual
// object-format selection, index binding and raw-blob provenance checks.
[[nodiscard]] Parsed parse_listing(std::string_view, ObjectFormat);
[[nodiscard]] Rendered render_json(const Manifest&);
[[nodiscard]] std::string issue_json(const Issue&);
[[nodiscard]] const char* code_name(Code) noexcept;

}  // namespace factory::validation
