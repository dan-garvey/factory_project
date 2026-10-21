#include "tree_manifest.hpp"

#include <cstdint>
#include <set>
#include <utility>

namespace factory::validation {
namespace {

bool valid_utf8(std::string_view text) {
    for (std::size_t index = 0; index < text.size();) {
        const auto lead = static_cast<unsigned char>(text[index++]);
        if (lead < 0x80) continue;
        std::size_t remaining;
        std::uint32_t value;
        std::uint32_t minimum;
        if (lead >= 0xc2 && lead <= 0xdf) {
            remaining = 1; value = lead & 0x1f; minimum = 0x80;
        } else if (lead >= 0xe0 && lead <= 0xef) {
            remaining = 2; value = lead & 0x0f; minimum = 0x800;
        } else if (lead >= 0xf0 && lead <= 0xf4) {
            remaining = 3; value = lead & 0x07; minimum = 0x10000;
        } else return false;
        if (remaining > text.size() - index) return false;
        for (std::size_t continuation = 0; continuation < remaining; ++continuation) {
            const auto next = static_cast<unsigned char>(text[index++]);
            if ((next & 0xc0) != 0x80) return false;
            value = (value << 6) | (next & 0x3f);
        }
        if (value < minimum || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) return false;
    }
    return true;
}

std::optional<Code> path_issue(std::string_view path) {
    if (path.empty() || path.size() > max_path_bytes || path.front() == '/' ||
        path.find('\\') != std::string_view::npos) return Code::path;
    if (path.size() >= 2 && path[1] == ':' &&
        ((path[0] >= 'a' && path[0] <= 'z') || (path[0] >= 'A' && path[0] <= 'Z'))) return Code::path;
    if (!valid_utf8(path)) return Code::utf8;
    for (std::size_t begin = 0; begin <= path.size();) {
        const auto slash = path.find('/', begin);
        const auto end = slash == std::string_view::npos ? path.size() : slash;
        const auto part = path.substr(begin, end - begin);
        if (part.empty() || part == "." || part == ".." || part == ".git") return Code::path;
        if (part == ".beads") return Code::private_path;
        if (slash == std::string_view::npos) break;
        begin = slash + 1;
    }
    return std::nullopt;
}

std::string json_string(std::string_view text) {
    constexpr char hex[] = "0123456789abcdef";
    std::string result = "\"";
    for (const unsigned char byte : text) {
        if (byte == '"' || byte == '\\') { result += '\\'; result += static_cast<char>(byte); }
        else if (byte < 0x20) {
            result += "\\u00";
            result += hex[byte >> 4];
            result += hex[byte & 15];
        } else result += static_cast<char>(byte);
    }
    return result + '"';
}
}  // namespace

Manifest::Manifest(ObjectFormat format, std::vector<Entry> entries)
    : format_(format), entries_(std::move(entries)) {}

const char* code_name(Code code) noexcept {
    switch (code) {
        case Code::format: return "object_format";
        case Code::input_limit: return "input_limit";
        case Code::entry_limit: return "entry_limit";
        case Code::truncated: return "truncated_record";
        case Code::record: return "malformed_record";
        case Code::mode: return "unsupported_mode";
        case Code::object_id: return "invalid_object_id";
        case Code::path: return "unsafe_path";
        case Code::private_path: return "private_path";
        case Code::utf8: return "invalid_utf8";
        case Code::duplicate: return "duplicate_path";
        case Code::path_conflict: return "file_directory_conflict";
        case Code::output_limit: return "output_limit";
        case Code::read_error: return "read_error";
    }
    return "unknown_error";
}

Parsed parse_listing(std::string_view input, ObjectFormat format) {
    auto fail = [](Code code, std::size_t record, std::size_t offset) -> Parsed {
        return {std::nullopt, Issue{code, record, offset}};
    };
    if (format != ObjectFormat::sha1 && format != ObjectFormat::sha256) return fail(Code::format, 0, 0);
    if (input.size() > max_input_bytes) return fail(Code::input_limit, 0, max_input_bytes);
    const std::size_t oid_length = format == ObjectFormat::sha1 ? 40 : 64;
    std::vector<Entry> entries;
    std::set<std::string> paths;
    for (std::size_t offset = 0; offset < input.size();) {
        const auto record_index = entries.size();
        if (record_index == max_entries) return fail(Code::entry_limit, record_index, offset);
        const auto end = input.find('\0', offset);
        if (end == std::string_view::npos) return fail(Code::truncated, record_index, offset);
        const auto record = input.substr(offset, end - offset);
        const auto tab = record.find('\t');
        if (tab == std::string_view::npos || tab < 12 || record[6] != ' ') return fail(Code::record, record_index, offset);
        const auto mode = record.substr(0, 6);
        if (mode != "100644" && mode != "100755") return fail(Code::mode, record_index, offset);
        if (record.substr(7, 5) != "blob ") return fail(Code::record, record_index, offset);
        const auto oid = record.substr(12, tab - 12);
        if (oid.size() != oid_length || oid.find_first_not_of("0123456789abcdef") != std::string_view::npos)
            return fail(Code::object_id, record_index, offset);
        const auto path = record.substr(tab + 1);
        if (const auto issue = path_issue(path)) return fail(*issue, record_index, offset);
        const std::string owned_path(path);
        if (paths.contains(owned_path)) return fail(Code::duplicate, record_index, offset);
        for (auto slash = path.find('/'); slash != std::string_view::npos; slash = path.find('/', slash + 1)) {
            if (paths.contains(std::string(path.substr(0, slash)))) return fail(Code::path_conflict, record_index, offset);
        }
        const auto prefix = owned_path + '/';
        const auto descendant = paths.lower_bound(prefix);
        if (descendant != paths.end() && descendant->starts_with(prefix)) return fail(Code::path_conflict, record_index, offset);
        paths.insert(owned_path);
        entries.push_back({std::string(mode), std::string(oid), std::string(path)});
        offset = end + 1;
    }
    return {Manifest(format, std::move(entries)), std::nullopt};
}

std::string issue_json(const Issue& issue) {
    return "{\"schema\":1,\"status\":\"fail\",\"code\":" + json_string(code_name(issue.code)) +
        ",\"record_index\":" + std::to_string(issue.record_index) +
        ",\"byte_offset\":" + std::to_string(issue.byte_offset) + "}";
}

Rendered render_json(const Manifest& manifest) {
    std::string output;
    auto append = [&](std::string_view value) {
        // Leave one byte for the CLI's final newline.
        if (value.size() > max_output_bytes - 1 - output.size()) return false;
        output += value;
        return true;
    };
    const auto format = manifest.format() == ObjectFormat::sha1 ? "sha1" : "sha256";
    if (!append("{\"schema\":1,\"status\":\"pass\",\"object_format\":" + json_string(format) +
                ",\"count\":" + std::to_string(manifest.entries().size()) + ",\"entries\":["))
        return {std::nullopt, Issue{Code::output_limit, 0, 0}};
    for (std::size_t index = 0; index < manifest.entries().size(); ++index) {
        const auto& entry = manifest.entries()[index];
        if (!append((index == 0 ? "" : ",") + std::string("{\"mode\":") + json_string(entry.mode) +
                    ",\"object_id\":" + json_string(entry.object_id) + ",\"path\":" + json_string(entry.path) + "}"))
            return {std::nullopt, Issue{Code::output_limit, index, 0}};
    }
    if (!append("]}")) return {std::nullopt, Issue{Code::output_limit, manifest.entries().size(), 0}};
    return {std::move(output), std::nullopt};
}
}  // namespace factory::validation
