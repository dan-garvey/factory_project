#include "tree_manifest.hpp"

#include <iostream>
#include <string>

namespace validation = factory::validation;

int main(int argc, char** argv) {
    auto format = validation::ObjectFormat::sha1;
    if (argc != 1) {
        if (argc != 3 || std::string(argv[1]) != "--object-format" ||
            (std::string(argv[2]) != "sha1" && std::string(argv[2]) != "sha256")) {
            std::cerr << "Usage: tree_manifest [--object-format sha1|sha256] < raw-listing\n";
            return 2;
        }
        format = std::string(argv[2]) == "sha1" ? validation::ObjectFormat::sha1 : validation::ObjectFormat::sha256;
    }
    std::string input;
    char block[8192];
    while (std::cin.read(block, sizeof(block)) || std::cin.gcount() > 0) {
        const auto count = static_cast<std::size_t>(std::cin.gcount());
        if (count > validation::max_input_bytes - input.size()) {
            std::cout << validation::issue_json({validation::Code::input_limit, 0, validation::max_input_bytes}) << '\n';
            return 1;
        }
        input.append(block, count);
    }
    if (std::cin.bad()) {
        std::cout << validation::issue_json({validation::Code::read_error, 0, input.size()}) << '\n';
        return 1;
    }
    const auto parsed = validation::parse_listing(input, format);
    if (parsed.issue) {
        std::cout << validation::issue_json(*parsed.issue) << '\n';
        return 1;
    }
    const auto rendered = validation::render_json(*parsed.manifest);
    if (rendered.issue) {
        std::cout << validation::issue_json(*rendered.issue) << '\n';
        return 1;
    }
    std::cout << *rendered.json << '\n';
    return std::cout ? 0 : 1;
}
