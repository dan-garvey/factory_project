#include "coordinator.hpp"

#include "native/tooling/local_resources.hpp"

#include <iostream>

int main(int argc, char** argv) {
    if (argc != 3 || std::string(argv[1]) != "--root") {
        std::cerr << "Usage: factory-commit-check --root CHECKOUT\n";
        return 2;
    }
    try {
        return factory::commit_gate::run(argv[2]);
    } catch (const factory::resources::AdmissionError& error) {
        std::cerr << "COMMIT CHECK DEFERRED: " << error.what() << '\n';
        return factory::resources::temporary_failure;
    } catch (const std::exception& error) {
        std::cerr << "COMMIT CHECK FAILED: " << error.what() << '\n';
        return 1;
    }
}
