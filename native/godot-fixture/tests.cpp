#include "fixture.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

namespace fixture = factory::godot_fixture;

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
        std::cout << "PASS " << checks << " native Godot fixture-log controls.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " controls: " << error.what() << '\n';
        return 1;
    }
}
