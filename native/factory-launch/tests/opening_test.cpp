#include "factory/opening.hpp"
#include "factory/capture.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <unistd.h>

namespace {
namespace fs = std::filesystem;
using namespace factory_launch;
int checks = 0;
void check(bool condition, const char* label) {
    if (!condition) throw std::runtime_error(label);
    ++checks;
}
void refuses(const std::function<void()>& operation, const char* label) {
    try { operation(); }
    catch (const std::exception&) { ++checks; return; }
    throw std::runtime_error(label);
}
void write(const fs::path& path, const std::string& value) {
    fs::create_directories(path.parent_path());
    std::ofstream file(path, std::ios::binary);
    check(static_cast<bool>(file) && static_cast<bool>(file.write(value.data(), static_cast<std::streamsize>(value.size()))),
          "Write only the owned native fixture.");
}
std::string read(const fs::path& path) {
    std::ifstream file(path, std::ios::binary);
    check(static_cast<bool>(file), "Read the owned native fixture.");
    return std::string(std::istreambuf_iterator<char>(file), {});
}
} // namespace

int main(int argc, char** argv) {
    try {
        check(argc == 2, "The native fixture requires its declared startup CLI runfile.");
        const auto executable = fs::canonical(argv[1]);
        const auto help = run_process({executable.string(), "--help"}, std::chrono::seconds(5), 8192, nullptr, true);
        check(help.exit_code == 0 && help.output.find("headless startup") != std::string::npos,
              "CLI help discloses the bounded startup scope without running an engine.");
        const auto missing = run_process({executable.string()}, std::chrono::seconds(5), 8192, nullptr, true);
        check(missing.exit_code == 1 && missing.output.find("All six startup options") != std::string::npos,
              "The CLI refuses missing source, binary and admission pins before engine startup.");
        const auto injected = run_process({executable.string(), "--script", "res://injected.gd"},
                                          std::chrono::seconds(5), 8192, nullptr, true);
        check(injected.exit_code == 1 && injected.output.find("documented startup option") != std::string::npos,
              "The CLI refuses caller script injection before engine startup.");
        const char* directory = std::getenv("TEST_UNDECLARED_OUTPUTS_DIR");
        check(directory && *directory, "The native fixture requires its Bazel-owned output directory.");
        const auto root = fs::canonical(directory) / "opening-copy";
        check(fs::create_directory(root), "Use a fresh retained fixture directory.");
        const auto original = root / "pristine";
        write(original / "project.godot", "[application]\nrun/main_scene=\"res://opening/opening.tscn\"\n");
        write(original / "opening/opening.tscn", "[gd_scene format=3]\n[node name=\"Opening\" type=\"Node\"]\n");
        write(original / "opening/entry.gd", "extends Node\n");
        write(original / "opening/new-assets/worker.tscn", "a new resource outside any fixed roster\n");
        const std::string binary("binary\0asset", 12);
        write(original / "opening/new-assets/pixels.bin", binary);
        fs::permissions(original / "opening/entry.gd", fs::perms::owner_all);
        const auto copy = copy_opening_project(original, root / "runtime");
        check(copy.sources.size() == 5, "All source files, including newly authored assets, are copied.");
        check(read(copy.runtime / "opening/new-assets/pixels.bin") == binary, "Binary resource bytes remain exact.");
        check(fs::status(copy.runtime / "opening/entry.gd").permissions() == fs::perms::owner_all,
              "Original source modes remain exact.");
        verify_opening_sources(copy);
        const auto commands = opening_commands("/opt/sealed-godot", copy.runtime, root / "worksite.factory");
        check(commands.import == std::vector<std::string>{"/opt/sealed-godot", "--headless", "--path",
              copy.runtime.string(), "--editor", "--import", "--quit"}, "Import uses only the declared captured project.");
        check(commands.startup == std::vector<std::string>{"/opt/sealed-godot", "--headless", "--path",
              copy.runtime.string(), "res://opening/opening.tscn", "--quit-after", "60", "--",
              "--save-slot=" + (root / "worksite.factory").string()},
              "Startup uses the ordinary scene without a custom observer, fixture or state injection.");
        const auto saved_path = root / "previous.factory";
        const auto incoming_path = root / "incoming.factory";
        const std::string saved_binary("store\0binary\xff", 13);
        write(saved_path, saved_binary);
        fs::permissions(saved_path, fs::perms::owner_read | fs::perms::owner_write);
        const auto resume = copy_opening_resume(saved_path, incoming_path);
        check(read(saved_path) == saved_binary && read(incoming_path) == saved_binary,
              "Opaque binary bytes remain identical in the original and incoming copy.");
        check(resume.bytes == saved_binary.size() && resume.sha256 == sha256(saved_binary),
              "The resume identity describes the original complete bytes.");
        check(fs::status(incoming_path).permissions() == fs::perms::owner_read &&
              fs::status(saved_path).permissions() == (fs::perms::owner_read | fs::perms::owner_write),
              "Only the incoming copy becomes read-only; original permissions remain unchanged.");
        const auto resume_commands = opening_commands("/opt/sealed-godot", copy.runtime,
                                                      root / "new.factory", incoming_path);
        auto expected_resume = commands.startup;
        expected_resume[expected_resume.size() - 1] = "--save-slot=" + (root / "new.factory").string();
        expected_resume.push_back("--resume-input=" + incoming_path.string());
        check(resume_commands.import == commands.import && resume_commands.startup == expected_resume,
              "Resume uses the same ordinary scene and Store input, without injecting state.");
        refuses([&] { copy_opening_resume(saved_path, incoming_path); }, "Existing incoming saves cannot be replaced.");
        refuses([&] { copy_opening_resume(saved_path, saved_path); }, "Resume cannot overwrite the original save.");
        // Keep the refusal fixture valid when Bazel archives this output tree.
        fs::create_symlink(saved_path.filename(), root / "save-alias.factory");
        refuses([&] { copy_opening_resume(root / "save-alias.factory", root / "alias-copy.factory"); },
                "A symlink cannot masquerade as the original save.");
        check(!fs::exists(root / "alias-copy.factory"), "Invalid original paths create no incoming copy.");
        write(root / "empty.factory", "");
        refuses([&] { copy_opening_resume(root / "empty.factory", root / "empty-copy.factory"); },
                "An empty save refuses before engine startup.");
        fs::permissions(incoming_path, fs::perms::owner_read | fs::perms::owner_write);
        refuses([&] { verify_opening_resume(resume); }, "Writable incoming save mode drift is detected.");
        write(incoming_path, "changed copy");
        fs::permissions(incoming_path, fs::perms::owner_read);
        refuses([&] { verify_opening_resume(resume); }, "Incoming binary corruption is detected.");
        fs::permissions(incoming_path, fs::perms::owner_read | fs::perms::owner_write);
        write(incoming_path, saved_binary);
        fs::permissions(incoming_path, fs::perms::owner_read);
        write(saved_path, "changed original");
        refuses([&] { verify_opening_resume(resume); }, "A concurrently changed original is detected.");
        write(saved_path, saved_binary);
        verify_opening_resume(resume);
        refuses([&] { opening_commands("/opt/godot", copy.runtime, root / "slot", root / "slot"); },
                "Resume and output slots must differ.");
        refuses([&] { opening_commands("/opt/godot", copy.runtime, root / "slot", copy.runtime / "input.factory"); },
                "Resume cannot be an imported source resource.");
        refuses([&] { opening_commands("/opt/godot", copy.runtime, root / "slot", "relative.factory"); },
                "Resume paths must be explicit absolute paths.");
        write(copy.runtime / ".godot/generated.cache", "generated import data");
        verify_opening_sources(copy);
        const auto script = read(original / "opening/entry.gd");
        write(copy.runtime / "opening/entry.gd", "changed runtime source\n");
        refuses([&] { verify_opening_sources(copy); }, "A rewritten original runtime source must refuse.");
        check(read(original / "opening/entry.gd") == script, "Runtime mutation never rewrites pristine source.");
        write(copy.runtime / "opening/entry.gd", script);
        fs::permissions(copy.runtime / "opening/entry.gd", fs::perms::owner_read);
        refuses([&] { verify_opening_sources(copy); }, "Runtime mode drift must refuse.");
        fs::permissions(copy.runtime / "opening/entry.gd", fs::perms::owner_all);
        write(original / "unexpected.txt", "unrecorded pristine source");
        refuses([&] { verify_opening_sources(copy); }, "Pristine closure additions must refuse.");
        fs::remove(original / "unexpected.txt");
        verify_opening_sources(copy);
        refuses([&] { copy_opening_project(original, copy.runtime); }, "Existing runtime output must refuse.");
        refuses([&] { copy_opening_project(original, original / "nested"); }, "Runtime nesting in pristine source must refuse.");
        fs::create_symlink(original / "opening/entry.gd", original / "alias.gd");
        refuses([&] { copy_opening_project(original, root / "symlink-output"); }, "Source symlinks must refuse.");
        check(!fs::exists(root / "symlink-output"), "Source refusal happens before runtime publication.");
        fs::remove(original / "alias.gd");
        write(original / ".beads/private", "must never copy");
        refuses([&] { copy_opening_project(original, root / "private-output"); }, "Private metadata must refuse.");
        check(!fs::exists(root / "private-output"), "Private metadata refusal creates no output.");
        fs::remove_all(original / ".beads");
        refuses([&] { opening_commands("relative-engine", copy.runtime, root / "slot"); }, "Relative executable must refuse.");
        refuses([&] { opening_commands("/opt/godot", copy.runtime, copy.runtime / "save.factory"); },
                "Save output inside runtime sources must refuse.");
        refuses([&] { opening_commands(copy.runtime / "godot", copy.runtime, root / "slot"); },
                "An executable inside captured sources must refuse.");
        refuses([&] { opening_commands("/opt/godot", "/tmp/../project", root / "slot"); },
                "Non-normalized project paths must refuse.");
        refuses([&] { opening_commands("/opt/godot", copy.runtime, root / ".git/slot"); },
                "Private save paths must refuse.");
        std::cout << "Opening copy and command controls passed " << checks << " checks; engine runs: 0.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Opening copy fixture failed: " << error.what() << '\n';
        return 1;
    }
}
