#pragma once

#include <filesystem>
#include <string>
#include <vector>

namespace factory_launch {

struct OpeningSource {
    std::filesystem::path relative;
    std::string sha256;
    std::size_t bytes;
    std::filesystem::perms permissions;
};

struct OpeningCopy {
    std::filesystem::path original;
    std::filesystem::path runtime;
    std::vector<OpeningSource> sources;
};

// Copy an existing pristine capture into a fresh, separate runtime directory.
// This does not import resources or start an engine. Caller owns both locations.
OpeningCopy copy_opening_project(const std::filesystem::path& original,
                                 const std::filesystem::path& runtime);

// Original closure stays exact. Runtime may add generated files, but no captured
// source may change. This intentionally refuses unreviewed import rewrites.
void verify_opening_sources(const OpeningCopy&);

struct OpeningResume {
    std::filesystem::path original;
    std::filesystem::path incoming;
    std::string sha256;
    std::size_t bytes;
    std::filesystem::perms original_permissions;
};

// Preserve an opaque existing Store binary. The native launcher never decodes or
// alters game state; the ordinary scene remains responsible for load validation.
OpeningResume copy_opening_resume(const std::filesystem::path& original,
                                  const std::filesystem::path& incoming);
void verify_opening_resume(const OpeningResume&);

struct OpeningExtensionInputs {
    std::filesystem::path descriptor;
    std::filesystem::path library;
    std::filesystem::path descriptor_relative;
    std::filesystem::path library_relative;
    std::string descriptor_sha256;
    std::string library_sha256;
};

struct OpeningExternalResource {
    std::filesystem::path original;
    std::filesystem::path runtime;
    std::filesystem::path relative;
    std::string sha256;
    std::size_t bytes;
    std::filesystem::perms original_permissions;
    std::filesystem::perms runtime_permissions;
};

// Add only the explicitly pinned bridge descriptor and Linux shared library.
// A tracked descriptor may already exist if its bytes match; never replace an
// existing source or a previously created runtime file. Declare the descriptor
// in a fresh runtime-only .godot/extension_list.cfg before the first import.
// Verification includes that exact generated entry and its safe path/mode.
std::vector<OpeningExternalResource> copy_opening_extension(
    const OpeningCopy&, const OpeningExtensionInputs&);
void verify_opening_extension(const std::vector<OpeningExternalResource>&);

struct OpeningCommands {
    std::vector<std::string> import;
    std::vector<std::string> startup;
};

// Explicitly bounded headless startup of the ordinary scene, without a custom
// script, observer, legacy fixture or game-state injection. Not a playability test.
OpeningCommands opening_commands(const std::filesystem::path& engine,
                                 const std::filesystem::path& project,
                                 const std::filesystem::path& save_slot,
                                 const std::filesystem::path& resume_input = {});

} // namespace factory_launch
