#pragma once

#include <chrono>
#include <csignal>
#include <cstdint>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <vector>

namespace factory::build_support {
enum class Reason { options, scan, artifacts, log, timeout, cancelled, spawn, io, wait, accounting_namespace };
class Error : public std::runtime_error {
public:
    explicit Error(Reason reason);
    Reason reason() const noexcept { return reason_; }
private:
    Reason reason_;
};
const char* reason_name(Reason) noexcept;
inline constexpr std::uint64_t maximum_artifacts = 2ULL * 1024 * 1024 * 1024;
inline constexpr std::uint64_t maximum_log = 8ULL * 1024 * 1024;

// A cooperative snapshot, not a filesystem quota. Never follow cache symlinks.
// Only ordinary disappearance/replacement is tolerated; all other errors refuse.
std::uint64_t owned_bytes(const std::filesystem::path&, std::uint64_t limit);

// Optional Linux read adapter. Only the short-lived accounting worker enters a
// caller-mapped user namespace; no build runs there and no permission is changed.
// The parent retains the original identity. Unsupported mapping fails closed.
std::uint64_t owned_bytes_as_owner(const std::filesystem::path&, std::uint64_t limit,
                                  std::chrono::milliseconds timeout,
                                  const volatile std::sig_atomic_t* cancellation = nullptr);

struct Options {
    std::filesystem::path artifacts;
    std::filesystem::path log;
    std::filesystem::path admission_directory;
    std::chrono::milliseconds timeout{180000};
    std::uint64_t artifact_limit{maximum_artifacts};
    std::uint64_t log_limit{maximum_log};
    unsigned jobs{8};
    const volatile std::sig_atomic_t* cancellation{};
    bool owned_user_accounting{false};
};

// Run synchronously through the existing admission wrapper. This is not an
// admission replacement. Keep only its two inherited permit files in the child.
// Source, toolchain, argv and cache identity are sealed by the caller, not here.
int run(const Options&, const std::vector<std::string>&);
}  // namespace factory::build_support
