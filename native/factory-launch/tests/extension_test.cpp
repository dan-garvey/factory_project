#include "factory/capture.hpp"
#include "factory/opening.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>

namespace {
namespace fs = std::filesystem;
using namespace factory_launch;
int checks = 0;
void check(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
    ++checks;
}
void refuses(const std::function<void()>& operation, const char* message) {
    try { operation(); }
    catch (const std::exception&) { ++checks; return; }
    throw std::runtime_error(message);
}
void write(const fs::path& path, const std::string& value) {
    fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary);
    check(static_cast<bool>(stream) && static_cast<bool>(stream.write(value.data(), value.size())),
          "Write the owned extension fixture.");
}
std::string read(const fs::path& path) {
    std::ifstream stream(path, std::ios::binary);
    check(static_cast<bool>(stream), "Read the owned extension fixture.");
    return std::string(std::istreambuf_iterator<char>(stream), {});
}
} // namespace

int main(int argc, char** argv) {
    try {
        check(argc == 2, "Supply the declared startup CLI runfile.");
        const auto executable = fs::canonical(argv[1]);
        const auto partial = run_process({executable.string(), "--repo", "/fixture", "--tree", std::string(40, '0'),
            "--output", "/fixture/output", "--godot", "/fixture/godot", "--engine-sha256", std::string(64, '0'),
            "--admission", "/fixture/admission", "--native-library", "/fixture/bridge.so"},
            std::chrono::seconds(5), 8192, nullptr, true);
        check(partial.exit_code == 1 && partial.output.find("all six compiled-extension") != std::string::npos,
              "A partial bridge specification refuses before any engine or filesystem work.");
        const auto* directory = std::getenv("TEST_UNDECLARED_OUTPUTS_DIR");
        check(directory && *directory, "Use the declared external fixture directory.");
        const auto root = fs::canonical(directory) / "extension";
        check(fs::create_directory(root), "The extension fixture must be fresh.");
        const auto original = root / "pristine";
        write(original / "project.godot", "[application]\n");
        write(original / "opening/opening.tscn", "[gd_scene format=3]\n[node name=\"Opening\" type=\"Node\"]\n");
        write(original / "opening/entry.gd", "extends Node\n");
        const std::string descriptor = "[configuration]\nentry_symbol=\"fixture_init\"\n";
        const std::string library("\x7f" "ELF\0bridge", 11);
        const auto descriptor_path = root / "inputs/bridge.gdextension";
        const auto library_path = root / "inputs/bridge.so";
        write(descriptor_path, descriptor);
        write(library_path, library);
        const auto source_mode = fs::status(library_path).permissions();
        const OpeningExtensionInputs inputs{descriptor_path, library_path, "native/bridge.gdextension",
                                             "native/bridge.so", sha256(descriptor), sha256(library)};
        unsigned sequence = 0;
        const auto fresh = [&] { return copy_opening_project(original, root / ("runtime-" + std::to_string(++sequence))); };
        const auto copy = fresh();
        const auto resources = copy_opening_extension(copy, inputs);
        check(resources.size() == 2, "Exactly the descriptor and library are recorded.");
        check(read(copy.runtime / inputs.descriptor_relative) == descriptor &&
              read(copy.runtime / inputs.library_relative) == library,
              "Descriptor and binary bytes survive the runtime copy exactly.");
        check(!fs::exists(original / "native"), "External resources never alter the pristine capture.");
        check(resources[0].sha256 == inputs.descriptor_sha256 && resources[1].sha256 == inputs.library_sha256,
              "The resource record contains the supplied content identities.");
        check(fs::status(resources[1].runtime).permissions() == fs::perms::owner_read &&
              fs::status(library_path).permissions() == source_mode,
              "The runtime copy is read-only while the original mode is preserved.");
        verify_opening_sources(copy);
        verify_opening_extension(resources);
        refuses([&] { copy_opening_extension(copy, inputs); }, "A second copy cannot replace existing runtime files.");
        fs::permissions(resources[1].runtime, fs::perms::owner_read | fs::perms::owner_write);
        refuses([&] { verify_opening_extension(resources); }, "Runtime permission drift is detected.");
        write(resources[1].runtime, "changed runtime library");
        fs::permissions(resources[1].runtime, fs::perms::owner_read);
        refuses([&] { verify_opening_extension(resources); }, "Runtime binary corruption is detected.");
        fs::permissions(resources[1].runtime, fs::perms::owner_read | fs::perms::owner_write);
        write(resources[1].runtime, library);
        fs::permissions(resources[1].runtime, fs::perms::owner_read);
        write(library_path, "changed original library");
        refuses([&] { verify_opening_extension(resources); }, "Original library drift is detected.");
        write(library_path, library);
        verify_opening_extension(resources);
        fs::permissions(library_path, fs::perms::owner_read);
        refuses([&] { verify_opening_extension(resources); }, "Original mode drift is detected.");
        fs::permissions(library_path, source_mode);
        verify_opening_extension(resources);
        auto bad = inputs;
        bad.library_sha256 = std::string(64, '0');
        refuses([&] { copy_opening_extension(fresh(), bad); }, "An incorrect library pin refuses the copy.");
        bad = inputs;
        bad.descriptor_sha256 = std::string(64, '0');
        refuses([&] { copy_opening_extension(fresh(), bad); }, "An incorrect descriptor pin refuses the copy.");
        for (const fs::path& target : {fs::path("../escape.gdextension"), fs::path("/absolute.gdextension"),
                                      fs::path(".godot/bridge.gdextension"), fs::path(".beads/bridge.gdextension")}) {
            bad = inputs;
            bad.descriptor_relative = target;
            refuses([&] { copy_opening_extension(fresh(), bad); }, "Unsafe extension destinations refuse.");
        }
        bad = inputs;
        bad.library_relative = "native/bridge.dll";
        refuses([&] { copy_opening_extension(fresh(), bad); }, "The explicit Linux profile refuses another library format.");
        fs::create_symlink(library_path, root / "library-alias.so");
        bad = inputs;
        bad.library = root / "library-alias.so";
        refuses([&] { copy_opening_extension(fresh(), bad); }, "Source library aliases refuse.");
        const auto redirected = fresh();
        fs::create_directory_symlink(root / "inputs", redirected.runtime / "native");
        refuses([&] { copy_opening_extension(redirected, inputs); }, "A runtime parent alias cannot redirect the copy.");
        write(root / "inputs/oversized.gdextension", std::string(65537, 'x'));
        bad = inputs;
        bad.descriptor = root / "inputs/oversized.gdextension";
        bad.descriptor_sha256 = sha256(std::string(65537, 'x'));
        refuses([&] { copy_opening_extension(fresh(), bad); }, "An oversized descriptor refuses before engine startup.");
        write(original / inputs.descriptor_relative, descriptor);
        const auto tracked = fresh();
        const auto tracked_resources = copy_opening_extension(tracked, inputs);
        verify_opening_sources(tracked);
        check(tracked_resources[0].runtime_permissions == fs::status(original / inputs.descriptor_relative).permissions(),
              "An already captured matching descriptor retains its exact mode and bytes.");
        bad = inputs;
        bad.descriptor = root / "inputs/other.gdextension";
        write(bad.descriptor, "different descriptor");
        bad.descriptor_sha256 = sha256("different descriptor");
        refuses([&] { copy_opening_extension(fresh(), bad); }, "A conflicting tracked descriptor cannot be replaced.");
        write(original / inputs.library_relative, "existing tracked source");
        refuses([&] { copy_opening_extension(fresh(), inputs); }, "A compiled library cannot replace tracked source.");
        check(read(original / inputs.library_relative) == "existing tracked source", "Refusal preserves the original source.");
        std::cout << "Extension resource controls passed " << checks << " checks; engine runs: 0.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Extension fixture failed: " << error.what() << '\n';
        return 1;
    }
}
