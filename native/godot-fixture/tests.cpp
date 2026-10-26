#include "cases.hpp"
#include "fixture.hpp"

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

namespace fixture = factory::godot_fixture;
namespace fs = std::filesystem;

namespace {
unsigned checks = 0;
void check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
    ++checks;
}
}

int main() {
    try {
        const std::string complete = "NATIVE_TRANSMISSION_VIEW_PASS 75";
        check(fixture::inspect_log("Godot Engine v4.7.2\n" + complete + "\n", complete)
                  == fixture::Verdict::pass,
              "A clean imported component result is accepted.");
        const std::string first_failure =
            "SCRIPT ERROR: Parse Error: Preload file has no resource loaders.\n"
            "SCRIPT ERROR: Compile Error: Failed to compile depended scripts.\n"
            "ERROR: Failed to load script with error Compilation failed.\n"
            "NATIVE_TRANSMISSION_VIEW_PASS 3\n";
        check(fixture::inspect_log(first_failure, "NATIVE_TRANSMISSION_VIEW_PASS 3")
                  == fixture::Verdict::diagnostic,
              "The actual zero-exit failure shape refuses despite its partial PASS marker.");
        check(fixture::inspect_log(first_failure, complete) == fixture::Verdict::diagnostic,
              "A partial fixture count cannot satisfy the complete expected line.");
        check(fixture::inspect_log("NATIVE_TRANSMISSION_VIEW_PASS 3\n", complete)
                  == fixture::Verdict::missing_marker,
              "A partial count alone is not a complete success.");
        check(fixture::inspect_log(complete + "\nParse Error: bad preload\n", complete)
                  == fixture::Verdict::diagnostic,
              "A diagnostic after the PASS line still refuses.");
        check(fixture::inspect_log("Failed to load script res://opening/test.gd\n" + complete + "\n", complete)
                  == fixture::Verdict::diagnostic,
              "Script-load failure without an ERROR prefix still refuses.");
        check(fixture::inspect_log("WARNING: glTF stride is inferred.\n" + complete + "\n", complete)
                  == fixture::Verdict::pass,
              "Visible asset warnings are not relabeled as script-load failure.");
        check(fixture::inspect_log(complete + "\n" + complete + "\n", complete)
                  == fixture::Verdict::missing_marker,
              "Two success markers do not describe one bounded fixture run.");
        check(fixture::inspect_log(std::string("noise\0", 6) + complete + "\n", complete)
                  == fixture::Verdict::malformed_log,
              "Binary controls cannot hide a diagnostic or forge a marker.");
        const auto* first = fixture::find_case("arrival-first-plate");
        const auto* small = fixture::find_case("arrival-channel-small");
        const auto* resumed = fixture::find_case("arrival-channel-small-resume");
        check(fixture::registered_cases().size() == 3 && first && small && resumed &&
                  !fixture::find_case("arrival-first-plste"),
              "Only the three declared scene event routes are registered.");
        check(first->script == "res://opening/native_adapter_check.gd" &&
                  first->pass_line == "CHAPTER 1 SCENE EVENTS PASS: arrival-first-plate" &&
                  small->pass_line == "CHAPTER 1 SCENE EVENTS PASS: arrival-channel-small" &&
                  resumed->pass_line == "CHAPTER 1 SCENE EVENTS PASS: arrival-channel-small-resume" &&
                  first->seconds == 180 && small->seconds == 300 && resumed->seconds == 180,
              "Named cases own the script, exact completion marker and deadline.");
        const std::vector<std::string> first_args{
            "--event-route-pointer", "--native-check-output=/tmp/first.result",
            "--native-check-mode=arrival-first-plate"};
        const std::vector<std::string> small_args{
            "--native-check-output=/tmp/small.result", "--save-slot=/tmp/small.worksite",
            "--event-route-loose", "--resume-input=/tmp/broad.worksite",
            "--native-check-mode=arrival-channel-small"};
        const std::vector<std::string> resume_args{
            "--native-check-mode=arrival-channel-small-resume", "--event-route-loose",
            "--resume-input=/tmp/small.worksite", "--save-slot=/tmp/recovered.worksite",
            "--native-check-prior=/tmp/small.result", "--native-check-output=/tmp/recovered.result"};
        check(fixture::accepts_case_arguments(*first, first_args) &&
                  fixture::accepts_case_arguments(*small, small_args) &&
                  fixture::accepts_case_arguments(*resumed, resume_args),
              "Every registered route accepts its required arguments in any order.");
        check(!fixture::accepts_case_arguments(*first, {first_args.data(), first_args.size() - 1}) &&
                  !fixture::accepts_case_arguments(*small, {small_args.data(), small_args.size() - 1}) &&
                  !fixture::accepts_case_arguments(*resumed, {resume_args.data(), resume_args.size() - 1}),
              "Omitted required inputs refuse for every route.");
        check(!fixture::accepts_case_arguments(*first,
                  std::vector<std::string>{"--native-check-mode=arrival-first-plate",
                                           "--event-route-pointer", "--native-check-output="}) &&
                  !fixture::accepts_case_arguments(*first,
                  std::vector<std::string>{"--native-check-mode=arrival-first-plate",
                                           "--event-route-pointer", "--native-check-output=/tmp/x",
                                           "--native-check-output=/tmp/y"}),
              "Empty or duplicated output inputs refuse.");
        check(!fixture::accepts_case_arguments(*first,
                  std::vector<std::string>{"--native-check-mode=arrival-first-plate",
                                           "--event-route-loose", "--native-check-output=/tmp/x"}) &&
                  !fixture::accepts_case_arguments(*small, first_args) &&
                  !fixture::accepts_case_arguments(*first,
                  std::vector<std::string>{"--native-check-mode=arrival-first-plate",
                                           "--event-route-pointer", "--unexpected=/tmp/x"}),
              "Wrong route, conflicting case or stray input cannot satisfy a named case.");
        std::string directory_template = (fs::temp_directory_path() / "factory-case-path-XXXXXX").string();
        std::vector<char> directory_bytes(directory_template.begin(), directory_template.end());
        directory_bytes.push_back('\0');
        char* created = ::mkdtemp(directory_bytes.data());
        check(created != nullptr, "The output-path controls own a fresh temporary directory.");
        struct TemporaryDirectory {
            fs::path path;
            ~TemporaryDirectory() {
                std::error_code error;
                fs::remove_all(path, error);
            }
        } temporary{created};
        fs::create_directory(temporary.path / "real");
        fs::create_directory_symlink(temporary.path / "real", temporary.path / "alias");
        const auto named_args = [&](const fs::path& save, const fs::path& result) {
            return std::vector<std::string>{"--native-check-mode=arrival-channel-small",
                "--event-route-loose", "--resume-input=/tmp/previous.worksite",
                "--save-slot=" + save.string(), "--native-check-output=" + result.string()};
        };
        const auto save = temporary.path / "real" / "channel.worksite";
        const auto equal = named_args(save, save);
        check(fixture::accepts_case_arguments(*small, equal) &&
                  !fixture::distinct_case_output_paths(equal),
              "A named channel cannot write its result over its own fresh worksite.");
        const auto symlink_alias = named_args(save, temporary.path / "alias" / "channel.worksite");
        check(fixture::accepts_case_arguments(*small, symlink_alias) &&
                  !fixture::distinct_case_output_paths(symlink_alias),
              "Distinct path spellings through a symlinked parent cannot share an output file.");
        const auto distinct = named_args(save, temporary.path / "alias" / "channel.result");
        check(fixture::accepts_case_arguments(*small, distinct) &&
                  fixture::distinct_case_output_paths(distinct),
              "Separate fresh worksite and result destinations remain selectable.");
        std::cout << "PASS " << checks << " native Godot fixture-log controls.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " controls: " << error.what() << '\n';
        return 1;
    }
}
