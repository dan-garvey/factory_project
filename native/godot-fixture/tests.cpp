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
        const auto* incline = fixture::find_case("arrival-nonhorizontal-incline");
        const auto* vertical = fixture::find_case("arrival-nonhorizontal-vertical-resume");
        const auto* sideways = fixture::find_case("arrival-nonhorizontal-sideways-resume");
        const auto* power_reopen = fixture::find_case("arrival-nonhorizontal-power-reopen-resume");
        const auto* actor_block = fixture::find_case("arrival-nonhorizontal-actor-block-resume");
        const auto* cog_repair = fixture::find_case("arrival-cog-repair");
        const auto* cog_reopen = fixture::find_case("arrival-cog-reopen");
        const auto* raised_starter = fixture::find_case("arrival-raised-starter-snap");
        const auto* raised_press = fixture::find_case("arrival-raised-press");
        const auto* small = fixture::find_case("arrival-channel-small");
        const auto* resumed = fixture::find_case("arrival-channel-small-resume");
        const auto* endpoint_default = fixture::find_case("transmission-endpoint-default");
        const auto* endpoint_common = fixture::find_case("transmission-endpoint-common-frame");
        const auto* endpoint_inspection = fixture::find_case("transmission-endpoint-inspection");
        const auto* endpoint_terrain = fixture::find_case("transmission-endpoint-terrain-host");
        check(fixture::registered_cases().size() == 16 && first && incline && vertical && sideways && power_reopen && actor_block && cog_repair && cog_reopen &&
                  raised_starter && raised_press &&
                  small && resumed && endpoint_default && endpoint_common && endpoint_inspection &&
                  endpoint_terrain &&
                  !fixture::find_case("arrival-first-plste"),
              "Only the twelve scene routes and four endpoint modes are registered.");
        const std::vector<std::string> incline_args{
            "--native-check-mode=arrival-nonhorizontal-incline",
            "--resume-input=/tmp/first-plate.worksite", "--native-check-output=/tmp/incline.result",
            "--save-slot=/tmp/incline.worksite"};
        check(incline->script == first->script && incline->seconds == 300 &&
                  incline->pass_line == "CHAPTER 1 PLAYER-BUILT INCLINE PASS" &&
                  fixture::accepts_case_arguments(*incline, incline_args) &&
                  !fixture::accepts_case_arguments(*incline,
                      {incline_args.data(), incline_args.size() - 1}) &&
                  !fixture::accepts_case_arguments(*incline,
                      std::vector<std::string>{"--native-check-mode=arrival-nonhorizontal-incline",
                          "--resume-input=", "--native-check-output=/tmp/incline.result",
                          "--save-slot=/tmp/incline.worksite"}),
              "The paid incline route requires a real first-plate save and fresh outputs.");
        for (const auto* route : {vertical, sideways}) {
            const std::vector<std::string> args{
                std::string("--native-check-mode=") + std::string(route->name),
                "--resume-input=/tmp/paid-incline.worksite", "--native-check-output=/tmp/route.result",
                "--save-slot=/tmp/route.worksite"};
            check(route->script == first->script && route->seconds == 300 &&
                      fixture::accepts_case_arguments(*route, args) &&
                      !fixture::accepts_case_arguments(*route, {args.data(), args.size() - 1}),
                  "Each power route requires a paid incline input and its own fresh save.");
        }
        check(power_reopen->script == first->script && power_reopen->seconds == 180 &&
                  fixture::accepts_case_arguments(*power_reopen,
                      std::vector<std::string>{"--native-check-mode=arrival-nonhorizontal-power-reopen-resume",
                          "--resume-input=/tmp/power.worksite", "--native-check-output=/tmp/reopen.result",
                          "--save-slot=/tmp/reopen.worksite"}),
              "A fresh scene can reopen either paid power route without a fixture shortcut.");
        check(actor_block->script == first->script && actor_block->seconds == 180 &&
                  actor_block->pass_line == "CHAPTER 1 BELT ACTOR OBSTRUCTION PASS" &&
                  fixture::accepts_case_arguments(*actor_block,
                      std::vector<std::string>{"--native-check-mode=arrival-nonhorizontal-actor-block-resume",
                          "--resume-input=/tmp/sideways.worksite", "--native-check-output=/tmp/block.result",
                          "--save-slot=/tmp/recovered.worksite"}),
              "The physical belt obstruction route requires a paid sideways save and fresh outputs.");
        check(cog_repair->script == "res://opening/native_cog_check.gd" &&
                  cog_reopen->script == cog_repair->script &&
                  cog_repair->seconds == 300 && cog_reopen->seconds == 180 &&
                  cog_repair->pass_line ==
                      "CHAPTER 1 COG REPAIR CHECKS COMPLETE" &&
                  cog_reopen->pass_line ==
                      "CHAPTER 1 COG REOPEN CHECKS COMPLETE",
              "The two cog cases select stable completed repair and reopen markers.");
        const std::vector<std::string> cog_repair_args{
            "--native-check-output=/tmp/cog.result", "--resume-input=/tmp/plate.worksite",
            "--native-check-mode=arrival-cog-resume", "--save-slot=/tmp/cog.session"};
        const std::vector<std::string> cog_reopen_args{
            "--resume-input=/tmp/cog.final.worksite", "--native-check-mode=arrival-cog-finish-resume",
            "--native-check-output=/tmp/reopened.result", "--save-slot=/tmp/reopened.session"};
        check(fixture::accepts_case_arguments(*cog_repair, cog_repair_args) &&
                  fixture::accepts_case_arguments(*cog_reopen, cog_reopen_args) &&
                  !fixture::accepts_case_arguments(*cog_repair,
                      {cog_repair_args.data(), cog_repair_args.size() - 1}) &&
                  !fixture::accepts_case_arguments(*cog_reopen,
                      {cog_reopen_args.data(), cog_reopen_args.size() - 1}),
              "Both cog stages require a mode, previous worksite, fresh result and save slot.");
        check(!fixture::accepts_case_arguments(*cog_repair, cog_reopen_args) &&
                  !fixture::accepts_case_arguments(*cog_reopen, cog_repair_args) &&
                  !fixture::accepts_case_arguments(*cog_repair,
                      std::vector<std::string>{"--native-check-mode=arrival-cog-resume",
                          "--resume-input=/tmp/plate.worksite", "--native-check-output=",
                          "--save-slot=/tmp/cog.session"}) &&
                  !fixture::accepts_case_arguments(*cog_repair,
                      std::vector<std::string>{"--native-check-mode=arrival-cog-resume",
                          "--resume-input=/tmp/plate.worksite", "--native-check-output=/tmp/cog.result",
                          "--save-slot="}) &&
                  !fixture::accepts_case_arguments(*cog_repair,
                      std::vector<std::string>{"--native-check-mode=arrival-cog-resume",
                          "--resume-input=/tmp/plate.worksite", "--native-check-output=/tmp/a",
                          "--native-check-output=/tmp/b"}) &&
                  !fixture::accepts_case_arguments(*cog_reopen,
                      std::vector<std::string>{"--native-check-mode=arrival-cog-finish-resume",
                          "--resume-input=/tmp/cog.final.worksite", "--native-check-output=/tmp/result",
                          "--event-route-pointer"}),
              "Cog cases refuse a swapped mode, empty or duplicated paths, and unrelated routes.");
        check(fixture::inspect_log(std::string(cog_repair->pass_line) + "\n",
                  cog_repair->pass_line) == fixture::Verdict::pass &&
                  fixture::inspect_log(std::string(cog_reopen->pass_line) + "\n",
                  cog_repair->pass_line) == fixture::Verdict::missing_marker &&
                  fixture::inspect_log(std::string(cog_repair->pass_line) +
                      "\nSCRIPT ERROR: fixture failure\n", cog_repair->pass_line) ==
                      fixture::Verdict::diagnostic,
              "A cog stage needs its own complete receipt and a clean engine log.");
        check(first->script == "res://opening/native_adapter_check.gd" &&
                  first->pass_line == "CHAPTER 1 SCENE EVENTS PASS: arrival-first-plate" &&
                  raised_starter->script == first->script &&
                  raised_starter->pass_line ==
                      "CHAPTER 1 SCENE EVENTS PASS: arrival-raised-starter-snap" &&
                  raised_press->script == first->script &&
                  raised_press->pass_line == "CHAPTER 1 SCENE EVENTS PASS: arrival-raised-press" &&
                  small->pass_line == "CHAPTER 1 SCENE EVENTS PASS: arrival-channel-small" &&
                  resumed->pass_line == "CHAPTER 1 SCENE EVENTS PASS: arrival-channel-small-resume" &&
                  first->seconds == 180 && raised_starter->seconds == 180 &&
                  raised_press->seconds == 180 && small->seconds == 300 && resumed->seconds == 180,
              "Named cases own the script, exact completion marker and deadline.");
        check(endpoint_default->script == "res://opening/native_transmission_endpoint_check.gd" &&
                  endpoint_common->script == endpoint_default->script &&
                  endpoint_inspection->script == endpoint_default->script &&
                  endpoint_terrain->script == endpoint_default->script &&
                  endpoint_default->seconds == 180 && endpoint_common->seconds == 180 &&
                  endpoint_inspection->seconds == 180 && endpoint_terrain->seconds == 180 &&
                  fixture::accepts_case_arguments(*endpoint_default, {}) &&
                  fixture::accepts_case_arguments(*endpoint_common,
                      std::vector<std::string>{"--common-frame-only"}) &&
                  fixture::accepts_case_arguments(*endpoint_inspection,
                      std::vector<std::string>{"--inspection-only"}) &&
                  fixture::accepts_case_arguments(*endpoint_terrain,
                      std::vector<std::string>{"--terrain-host-only"}),
              "Every endpoint case owns its script, timeout and exact mode.");
        check(!fixture::accepts_case_arguments(*endpoint_default,
                  std::vector<std::string>{"--common-frame-only"}) &&
                  !fixture::accepts_case_arguments(*endpoint_common, {}) &&
                  !fixture::accepts_case_arguments(*endpoint_common,
                      std::vector<std::string>{"--inspection-only"}) &&
                  !fixture::accepts_case_arguments(*endpoint_common,
                      std::vector<std::string>{"--common-frame-only", "--common-frame-only"}) &&
                  !fixture::accepts_case_arguments(*endpoint_terrain,
                      std::vector<std::string>{"--terrain-host-only", "--inspection-only"}),
              "Named endpoint cases refuse omitted, wrong, repeated and competing modes.");
        check(fixture::inspect_log(std::string(endpoint_common->pass_line) + "\n",
                  endpoint_common->pass_line) == fixture::Verdict::pass &&
                  fixture::inspect_log(std::string(endpoint_default->pass_line) + "\n",
                  endpoint_common->pass_line) == fixture::Verdict::missing_marker &&
                  fixture::inspect_log(
                      "{\"checks\":3,\"failures\":1,\"status\":\"fail\"}\n",
                      endpoint_common->pass_line) == fixture::Verdict::missing_marker &&
                  fixture::inspect_log(std::string(endpoint_common->pass_line) +
                      "\nSCRIPT ERROR: failed assertion\n", endpoint_common->pass_line) ==
                      fixture::Verdict::diagnostic,
              "Only the selected complete endpoint receipt without engine errors can pass.");
        const std::vector<std::string> first_args{
            "--event-route-pointer", "--native-check-output=/tmp/first.result",
            "--native-check-mode=arrival-first-plate"};
        const std::vector<std::string> raised_starter_args{
            "--event-route-pointer", "--native-check-output=/tmp/raised-starter.result",
            "--native-check-mode=arrival-raised-starter-snap"};
        const std::vector<std::string> raised_press_args{
            "--event-route-pointer", "--native-check-output=/tmp/raised-press.result",
            "--native-check-mode=arrival-raised-press"};
        const std::vector<std::string> small_args{
            "--native-check-output=/tmp/small.result", "--save-slot=/tmp/small.worksite",
            "--event-route-loose", "--resume-input=/tmp/broad.worksite",
            "--native-check-mode=arrival-channel-small"};
        const std::vector<std::string> resume_args{
            "--native-check-mode=arrival-channel-small-resume", "--event-route-loose",
            "--resume-input=/tmp/small.worksite", "--save-slot=/tmp/recovered.worksite",
            "--native-check-prior=/tmp/small.result", "--native-check-output=/tmp/recovered.result"};
        check(fixture::accepts_case_arguments(*first, first_args) &&
                  fixture::accepts_case_arguments(*raised_starter, raised_starter_args) &&
                  fixture::accepts_case_arguments(*raised_press, raised_press_args) &&
                  fixture::accepts_case_arguments(*small, small_args) &&
                  fixture::accepts_case_arguments(*resumed, resume_args),
              "Every registered route accepts its required arguments in any order.");
        check(!fixture::accepts_case_arguments(*first, {first_args.data(), first_args.size() - 1}) &&
                  !fixture::accepts_case_arguments(*raised_starter,
                      {raised_starter_args.data(), raised_starter_args.size() - 1}) &&
                  !fixture::accepts_case_arguments(*raised_press,
                      {raised_press_args.data(), raised_press_args.size() - 1}) &&
                  !fixture::accepts_case_arguments(*small, {small_args.data(), small_args.size() - 1}) &&
                  !fixture::accepts_case_arguments(*resumed, {resume_args.data(), resume_args.size() - 1}),
              "Omitted required inputs refuse for every route.");
        check(!fixture::accepts_case_arguments(*raised_starter, first_args) &&
                  !fixture::accepts_case_arguments(*raised_press, raised_starter_args) &&
                  !fixture::accepts_case_arguments(*raised_press,
                      std::vector<std::string>{"--native-check-mode=arrival-raised-press",
                          "--event-route-pointer", "--native-check-output="}) &&
                  !fixture::accepts_case_arguments(*raised_press,
                      std::vector<std::string>{"--native-check-mode=arrival-raised-press",
                          "--event-route-pointer", "--native-check-output=/tmp/a",
                          "--native-check-output=/tmp/b"}),
              "Raised routes reject another mode, empty output and duplicate output.");
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
