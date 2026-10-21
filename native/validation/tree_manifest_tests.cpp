#include "tree_manifest.hpp"

#include <iostream>
#include <string>
#include <type_traits>

namespace v = factory::validation;
static_assert(!std::is_default_constructible_v<v::Manifest>);

namespace {
int checks = 0;
int failures = 0;

bool check(bool condition, const char* label) {
    ++checks;
    if (!condition) { ++failures; std::cerr << "FAIL: " << label << '\n'; }
    return condition;
}

std::string record(const std::string& path, const std::string& mode = "100644",
                   const std::string& oid = std::string(40, 'a'), const std::string& type = "blob") {
    return mode + ' ' + type + ' ' + oid + '\t' + path + '\0';
}

void refuses(const std::string& input, v::Code code, v::ObjectFormat format = v::ObjectFormat::sha1) {
    const auto parsed = v::parse_listing(input, format);
    check(!parsed.manifest.has_value(), "A refused listing returns no partial validated manifest.");
    check(parsed.issue && parsed.issue->code == code, "The refusal identifies its actual boundary.");
}

void framing_and_objects() {
    const auto empty = v::parse_listing({}, v::ObjectFormat::sha1);
    check(empty.manifest && empty.manifest->entries().empty(), "An empty Git tree is valid metadata, not a completed source gate.");
    const auto normal = v::parse_listing(record("scripts/check.py") + record("run", "100755"), v::ObjectFormat::sha1);
    if (check(normal.manifest.has_value(), "Regular and executable blob entries are accepted.")) {
        check(normal.manifest->entries().size() == 2, "Every supplied entry is preserved.");
        check(normal.manifest->entries()[0].path == "scripts/check.py", "Input order and path bytes are preserved.");
        check(normal.manifest->entries()[1].mode == "100755", "Executable mode remains explicit.");
    }
    const auto wide = v::parse_listing(record("wide", "100644", std::string(64, 'b')), v::ObjectFormat::sha256);
    check(wide.manifest && wide.manifest->format() == v::ObjectFormat::sha256, "SHA-256 width is an explicit caller choice.");
    refuses(record("wide", "100644", std::string(64, 'b')), v::Code::object_id);
    refuses(record("short", "100644", "ab12"), v::Code::object_id);
    refuses(record("uppercase", "100644", std::string(40, 'A')), v::Code::object_id);
    refuses(record("nonhex", "100644", std::string(40, 'g')), v::Code::object_id);
    refuses(record("tree", "100644", std::string(40, 'a'), "tree"), v::Code::record);
    refuses(record("link", "120000"), v::Code::mode);
    refuses(record("submodule", "160000", std::string(40, 'a'), "commit"), v::Code::mode);
    refuses(record("directory", "040000", std::string(40, 'a'), "tree"), v::Code::mode);
    refuses("not a NUL-terminated record", v::Code::truncated);
    refuses(std::string(1, '\0'), v::Code::record);
    refuses(record("valid") + std::string(1, '\0'), v::Code::record);
    refuses(std::string("100644blob ") + std::string(40, 'a') + "\tx" + '\0', v::Code::record);
    refuses({}, v::Code::format, static_cast<v::ObjectFormat>(99));
    const auto prefix = record("good");
    const auto later = v::parse_listing(prefix + record(".beads/issues.jsonl"), v::ObjectFormat::sha1);
    check(later.issue && later.issue->record_index == 1 && later.issue->byte_offset == prefix.size(),
          "A later failure retains its original record index and byte offset.");
    check(!later.manifest, "A good prefix cannot escape a later private-path failure.");
}

void paths_and_unicode() {
    for (const auto* path : {"", "/absolute", "../escape", "a/../escape", "a/./b", "a//b", "a/", ".git/config", "a/.git/config", "C:/outside", "a\\outside"})
        refuses(record(path), v::Code::path);
    for (const auto* path : {".beads", ".beads/issues.jsonl", "nested/.beads/export.jsonl"})
        refuses(record(path), v::Code::private_path);
    const auto distinct = v::parse_listing(record(".gitignore") + record(".beadsmith") + record("a/b") + record("a/c"), v::ObjectFormat::sha1);
    check(distinct.manifest && distinct.manifest->entries().size() == 4, "Private-name prefixes and sibling paths are not falsely rejected.");
    refuses(record("same") + record("same", "100755"), v::Code::duplicate);
    refuses(record("a") + record("a/b"), v::Code::path_conflict);
    refuses(record("a/b") + record("a"), v::Code::path_conflict);
    const auto unicode = v::parse_listing(record("docs/\xe2\x9c\x93.md") + record("docs/a\"b\t\n.md"), v::ObjectFormat::sha1);
    if (check(unicode.manifest.has_value(), "Valid UTF-8 and verbatim quoted/control path bytes retain their identity.")) {
        const auto rendered = v::render_json(*unicode.manifest);
        check(rendered.json && rendered.json->find("docs/\xe2\x9c\x93.md") != std::string::npos, "UTF-8 is retained without lossy conversion.");
        check(rendered.json && rendered.json->find("a\\\"b\\u0009\\u000a.md") != std::string::npos, "JSON quotes and control bytes are escaped unambiguously.");
        check(rendered.json && !rendered.issue, "A complete valid manifest has one complete JSON result.");
    }
    for (const auto& bytes : {std::string("x/\xc3"), std::string("x/\x80"), std::string("x/\xc0\xaf"),
                              std::string("x/\xed\xa0\x80"), std::string("x/\xf4\x90\x80\x80")})
        refuses(record(bytes), v::Code::utf8);
    const auto maximum_scalar = v::parse_listing(record("x/\xf4\x8f\xbf\xbf"), v::ObjectFormat::sha1);
    check(maximum_scalar.manifest.has_value(), "The last valid Unicode scalar is not rejected as an overflow.");
}

void limits_and_output() {
    refuses(std::string(v::max_input_bytes + 1, 'x'), v::Code::input_limit);
    refuses(record(std::string(v::max_path_bytes + 1, 'x')), v::Code::path);
    check(v::parse_listing(record(std::string(v::max_path_bytes, 'x')), v::ObjectFormat::sha1).manifest.has_value(),
          "The declared path-byte boundary is inclusive metadata policy.");
    std::string input;
    for (std::size_t index = 0; index < v::max_entries; ++index) input += record("p" + std::to_string(index));
    const auto full = v::parse_listing(input, v::ObjectFormat::sha1);
    check(full.manifest && full.manifest->entries().size() == v::max_entries, "The declared record limit is inclusive.");
    refuses(input + record("one-more"), v::Code::entry_limit);
    input.clear();
    for (int index = 0; index < 3500; ++index) input += record("p" + std::to_string(index) + '/' + std::string(480, '\1'));
    const auto escaped = v::parse_listing(input, v::ObjectFormat::sha1);
    if (check(escaped.manifest.has_value(), "A bounded raw listing may require more escaped JSON bytes.")) {
        const auto output = v::render_json(*escaped.manifest);
        check(!output.json && output.issue && output.issue->code == v::Code::output_limit,
              "Oversized serialization returns no partial passing payload.");
    }
    const auto diagnostic = v::issue_json({v::Code::private_path, 2, 99});
    check(diagnostic.find("\"status\":\"fail\"") != std::string::npos && diagnostic.find("\"entries\"") == std::string::npos,
          "A failure diagnostic contains no accepted source entries.");
}
}  // namespace

int main() {
    framing_and_objects();
    paths_and_unicode();
    limits_and_output();
    std::cout << "{\"status\":\"" << (failures == 0 ? "pass" : "fail")
              << "\",\"checks\":" << checks << ",\"failures\":" << failures << "}\n";
    return failures == 0 && checks > 0 ? 0 : 1;
}
