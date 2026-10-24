#pragma once

#include <chrono>
#include <cstddef>
#include <csignal>
#include <filesystem>
#include <string>
#include <vector>

namespace factory_launch {

// Complete tracked project inputs, including authored binary assets. Retained
// outputs and opaque save inputs have separate, unchanged allowances.
inline constexpr std::size_t maximum_project_source_bytes = 64 * 1024 * 1024;

struct ProcessResult {
    int exit_code;
    std::string output;
};

// A bounded utility child, never an engine or an unowned process. No shell is used.
ProcessResult run_process(const std::vector<std::string>& arguments,
                         std::chrono::milliseconds timeout,
                         std::size_t maximum_output,
                         const volatile std::sig_atomic_t* cancellation = nullptr,
                         bool merge_stderr = false);

std::string sha256(const std::string& bytes);
std::string json_string(const std::string& value);

struct CaptureOptions {
    std::filesystem::path repository;
    std::string tree;
    std::filesystem::path output;
    const volatile std::sig_atomic_t* cancellation = nullptr;
};

struct CaptureResult {
    std::string tree;
    std::size_t files;
    std::size_t scripts;
    std::size_t source_bytes;
    std::filesystem::path manifest;
};

// Captures the complete tracked Godot subtree from raw immutable Git objects.
// This function does not run a compiler, import resources or start the game.
CaptureResult capture_project(const CaptureOptions& options);

} // namespace factory_launch
