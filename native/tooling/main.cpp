#include "local_resources.hpp"

#include <iostream>
#include <limits>

namespace {
void usage(std::ostream& out) {
    out << "Usage: factory-local [--root CHECKOUT] MODE [OPTIONS] -- COMMAND [ARG ...]\n"
        << "Modes: check, heavy, benchmark\n"
        << "Options: --jobs N, --disk-floor-gib N, --memory-reserve-gib N, --no-wait, --inherit-permits\n"
        << "The immediate supervisor holds admission until COMMAND exits. COMMAND receives no\n"
        << "admission descriptors unless --inherit-permits is set for a verified runner.\n"
        << "Defaults: caller checkout, 8 jobs, 20 GiB disk, 8 GiB memory; wait for admission.\n";
}
}

int main(int argc, char** argv) {
    using namespace factory::resources;
    Options options;
    bool have_mode = false;
    try {
        options.root = std::filesystem::current_path();
        for (int i = 1; i < argc; ++i) {
            const std::string argument(argv[i]);
            if (argument == "--") {
                for (++i; i < argc; ++i) options.command.emplace_back(argv[i]);
                break;
            }
            if (argument == "--help" || argument == "-h") { usage(std::cout); return 0; }
            if (argument == "--no-wait") { options.wait = false; continue; }
            if (argument == "--inherit-permits") { options.inherit_permits = true; continue; }
            const auto separator = argument.find('=');
            const auto key = argument.substr(0, separator);
            if (key == "--root" || key == "--jobs" || key == "--disk-floor-gib" || key == "--memory-reserve-gib") {
                std::string value;
                if (separator != std::string::npos) value = argument.substr(separator + 1);
                else {
                    if (++i == argc) throw std::invalid_argument("Missing value for " + key);
                    value = argv[i];
                }
                if (key == "--root") {
                    if (value.empty()) throw std::invalid_argument("Empty checkout root");
                    options.root = value;
                } else {
                    const auto number = unsigned_number(value);
                    if (key == "--jobs") {
                        if (!number) throw std::invalid_argument("Jobs must be greater than zero");
                        options.jobs = number;
                    } else {
                        if (number > std::numeric_limits<std::uint64_t>::max() / gib)
                            throw std::invalid_argument("Capacity floor is outside the supported range");
                        if (key == "--disk-floor-gib") options.disk_floor_gib = number;
                        else options.memory_reserve_gib = number;
                    }
                }
                continue;
            }
            if (!have_mode && (argument == "check" || argument == "heavy" || argument == "benchmark")) {
                options.mode = argument == "check" ? Mode::check : argument == "heavy" ? Mode::heavy : Mode::benchmark;
                have_mode = true;
                continue;
            }
            throw std::invalid_argument("Unknown or unexpected argument: " + argument);
        }
        if (!have_mode || options.command.empty()) throw std::invalid_argument("Provide a mode and -- followed by a command");
    } catch (const std::exception& error) {
        usage(std::cerr);
        std::cerr << "Argument error: " << error.what() << '\n';
        return 2;
    }
    try {
        return run(options);
    } catch (const AdmissionError& error) {
        std::cerr << "LOCAL WORK DEFERRED: " << error.what() << '\n';
        return temporary_failure;
    } catch (const std::exception& error) {
        std::cerr << "LOCAL WORK FAILED: " << error.what() << '\n';
        return 1;
    }
}
