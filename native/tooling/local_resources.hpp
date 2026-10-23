#pragma once

#include <cstdint>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <vector>

namespace factory::resources {

constexpr std::uint64_t gib = 1024ULL * 1024 * 1024;
constexpr int temporary_failure = 75;
constexpr unsigned heavy_slots = 4;

enum class Mode { check, heavy, benchmark };

struct Options {
    std::filesystem::path root;
    Mode mode = Mode::check;
    std::uint64_t jobs = 8;
    std::uint64_t disk_floor_gib = 20;
    std::uint64_t memory_reserve_gib = 8;
    bool wait = true;
    bool inherit_permits = false;
    std::vector<std::string> command;
};

class AdmissionError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

class FileDescriptor {
public:
    explicit FileDescriptor(int fd = -1) noexcept : fd_(fd) {}
    ~FileDescriptor();
    FileDescriptor(const FileDescriptor&) = delete;
    FileDescriptor& operator=(const FileDescriptor&) = delete;
    FileDescriptor(FileDescriptor&& other) noexcept;
    FileDescriptor& operator=(FileDescriptor&& other) noexcept;
    int get() const noexcept { return fd_; }
    int release() noexcept;
private:
    int fd_;
};

class Admission {
public:
    Admission(const std::filesystem::path& common_dir, Mode mode, bool wait);
    Admission(const Admission&) = delete;
    Admission& operator=(const Admission&) = delete;
    std::vector<int> inherited_descriptors() const;
private:
    std::vector<FileDescriptor> handles_;
};

struct Capacity {
    std::uint64_t disk_available;
    std::uint64_t memory_available;
};

std::string mode_name(Mode mode);
std::uint64_t unsigned_number(const std::string& value);
std::uint64_t memory_available(const std::filesystem::path& meminfo = "/proc/meminfo");
void enforce_capacity(Capacity observed, std::uint64_t disk_floor_gib,
                      std::uint64_t memory_reserve_gib);
std::filesystem::path common_git_dir(const std::filesystem::path& root);
int run(const Options& options);

} // namespace factory::resources
