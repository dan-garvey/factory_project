#include "coordinator.hpp"
#include "native_worker.hpp"

#include "native/tooling/local_resources.hpp"

#include <iostream>

int main(int argc, char** argv) {
    const bool native_worker = argc == 6 && std::string(argv[1]) == "--native-worker" &&
                               std::string(argv[2]) == "--root" &&
                               std::string(argv[4]) == "--expected-tree";
    if (!native_worker && (argc != 3 || std::string(argv[1]) != "--root")) {
        std::cerr << "Usage: factory-commit-check --root CHECKOUT\n";
        return 2;
    }
    try {
        if (native_worker) return factory::commit_gate::run_native_worker(argv[3], argv[5]);
        return factory::commit_gate::run(argv[2]);
    } catch (const factory::resources::AdmissionError& error) {
        std::cerr << "COMMIT CHECK DEFERRED: " << error.what() << '\n';
        return factory::resources::temporary_failure;
    } catch (const std::exception& error) {
        std::cerr << "COMMIT CHECK FAILED: " << error.what() << '\n';
        return 1;
    }
}
